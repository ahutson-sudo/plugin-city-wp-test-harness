#!/usr/bin/env bash
# Shared helpers for Plugin City WordPress/WooCommerce test harness.

set -euo pipefail

pc_harness_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${here}/.." && pwd
}

HARNESS_ROOT="${HARNESS_ROOT:-$(pc_harness_root)}"

pc_compose_files() {
  local files=( -f "${HARNESS_ROOT}/docker-compose.yml" )
  if [[ -n "${EXTRA_PLUGIN_PATH:-}" ]]; then
    files+=( -f "${HARNESS_ROOT}/docker-compose.extra.yml" )
  fi
  printf '%s\n' "${files[@]}"
}

pc_compose() {
  local files=()
  while IFS= read -r part; do
    files+=( "${part}" )
  done < <(pc_compose_files)

  if docker compose version >/dev/null 2>&1; then
    docker compose "${files[@]}" "$@"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "${files[@]}" "$@"
    return
  fi
  echo "Docker Compose is required. Install Docker Desktop and ensure 'docker compose' works." >&2
  exit 1
}

pc_require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required. Install Docker Desktop, then retry." >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker is installed but the daemon is not running." >&2
    exit 1
  fi
}

# Compose says "dependency failed to start: container ... is unhealthy" and
# nothing more: no probe output, no MariaDB log, and no way to tell a database
# that was still booting from one that was broken. Establishing that nothing had
# run took reading the whole job log, so the harness now says what it saw.
pc_explain_startup_failure() {
  local waited="${1:-0}" id probes
  id="$(pc_compose ps -aq db 2>/dev/null | head -n1)"

  echo
  echo "=== The database did not come up (waited ${waited}s) ==="
  echo "A slow first boot and a broken database look the same from outside the"
  echo "container. What follows is what tells them apart."
  echo
  echo "--- Containers ---"
  pc_compose ps -a || true

  if [[ -n "${id}" ]]; then
    echo
    echo "--- db container ---"
    docker inspect --format 'state={{ .State.Status }} exit={{ .State.ExitCode }} restarts={{ .RestartCount }} health={{ if .State.Health }}{{ .State.Health.Status }} failed_in_a_row={{ .State.Health.FailingStreak }}{{ else }}(none){{ end }}' "${id}" || true
    echo
    echo "--- Health probes (Docker keeps the last five) ---"
    probes="$(docker inspect --format '{{ range .State.Health.Log }}{{ .Start }} exit={{ .ExitCode }} took={{ .End.Sub .Start }} {{ printf "%q" .Output }}
{{ end }}' "${id}" 2>/dev/null || true)"
    if [[ -n "${probes//[[:space:]]/}" ]]; then
      echo "${probes}"
    else
      echo "(no probe has finished yet)"
    fi
  fi

  echo
  echo "--- db log (last 200 lines) ---"
  pc_compose logs --no-color --tail 200 db || true
  echo
  echo "Restarts above zero is a crash and a restart, not a slow boot. Probes"
  echo "that took the whole timeout mean the server was reachable but too busy"
  echo "to answer, which is the same disk contention seen from the other side."
}

# The ceiling matches the health check budget in docker-compose.yml, and is
# enforced here as well because health state resets when a container restarts
# and db restarts unless stopped: a database crash-looping every few seconds
# would otherwise sit in "starting" indefinitely and never trip Compose's gate.
pc_wait_for_db() {
  local limit="${PC_DB_WAIT_SECONDS}" waited=0 status streak id

  id="$(pc_compose ps -aq db 2>/dev/null | head -n1)"
  if [[ -z "${id}" ]]; then
    echo "The db container was never created." >&2
    pc_explain_startup_failure 0
    return 1
  fi

  echo "Waiting for the database (up to ${limit}s)..."
  while (( waited < limit )); do
    status="$(docker inspect --format '{{ if .State.Health }}{{ .State.Health.Status }}{{ else }}none{{ end }}' "${id}" 2>/dev/null || echo gone)"
    case "${status}" in
      healthy)
        # Printed on every successful run on purpose: it is the only record of
        # how close a normal boot comes to the budget above.
        echo "Database healthy after ${waited}s."
        return 0
        ;;
      none)
        return 0
        ;;
      unhealthy|gone)
        echo "Database reported ${status} after ${waited}s." >&2
        pc_explain_startup_failure "${waited}"
        return 1
        ;;
    esac
    sleep 2
    waited=$(( waited + 2 ))
    if (( waited % 30 == 0 )); then
      streak="$(docker inspect --format '{{ .State.Health.FailingStreak }}' "${id}" 2>/dev/null || true)"
      echo "  still ${status} after ${waited}s (counted probe failures: ${streak:-unknown}; failures inside the start period do not count)"
    fi
  done

  echo "The database did not become healthy within ${limit}s." >&2
  pc_explain_startup_failure "${limit}"
  return 1
}

pc_images() {
  pc_compose config --images 2>/dev/null | awk 'NF' | sort -u
}

# A registry that answers and refuses gives the same answer every time, so these
# are reported on the first attempt rather than the third: a tag or a repository
# that does not exist, and anything that cannot be read without credentials this
# machine has not got. The way a harness run usually meets the first of them is a
# WordPress and PHP pair that was never published as a tag.
pc_pull_answer_is_final() {
  grep -Eqi 'manifest unknown|manifest for .+ not found|: not found|repository does not exist|pull access denied|requested access to the resource is denied|unauthorized|authentication required|invalid reference format|no matching manifest' "$1"
}

pc_pull_image() {
  local image="$1" attempts="${PC_PULL_ATTEMPTS}" pause="${PC_PULL_RETRY_SECONDS}"
  local attempt=1 log
  log="$(mktemp)"

  while :; do
    if (( attempt == 1 )); then
      echo "Pulling ${image}..."
    else
      echo "Pulling ${image} again (attempt ${attempt} of ${attempts})..."
    fi

    if docker pull "${image}" 2>&1 | tee "${log}"; then
      if (( attempt > 1 )); then
        echo "Pulled ${image} on attempt ${attempt} of ${attempts}."
      fi
      rm -f "${log}"
      return 0
    fi

    if pc_pull_answer_is_final "${log}"; then
      echo >&2
      echo "=== ${image} cannot be pulled, and asking again would not change that ===" >&2
      echo "The registry answered and refused: the image, the tag or the" >&2
      echo "permission to read it is the thing that is missing, and that is the" >&2
      echo "same answer every time, so this was tried once. Not every WordPress" >&2
      echo "and PHP pair exists as a published tag; check WP_VERSION and" >&2
      echo "PHP_VERSION against the tags on Docker Hub." >&2
      rm -f "${log}"
      return 1
    fi

    if (( attempt >= attempts )); then
      echo >&2
      echo "=== Could not pull ${image} after ${attempts} attempts ===" >&2
      echo "Every attempt failed to reach or finish with the registry, and what" >&2
      echo "it said last is above. Nothing in the plugin and nothing in this" >&2
      echo "harness has run yet, so this is not a test result." >&2
      echo >&2
      echo "${attempts} failures in a row is more than a dropped connection, so" >&2
      echo "re-running the job is a guess rather than a fix. Check that the" >&2
      echo "registry is reachable from this machine first." >&2
      rm -f "${log}"
      return 1
    fi

    echo "Pulling ${image} failed; waiting ${pause}s before attempt $(( attempt + 1 )) of ${attempts}."
    sleep "${pause}"
    attempt=$(( attempt + 1 ))
    pause=$(( pause * 2 ))
  done
}

# Compose fetches an image it has not got as part of `up`, which is invisible
# until the registry drops the connection: the fetch is then half of the command
# that starts the database, the whole `up` dies, and the harness has said nothing
# because pc_wait_for_db was never reached. A CI job read as one line of Compose
# output about a manifest, with no hint that no code had run.
#
# Fetching first is what makes a retry possible at all. Wrapped around `up`, a
# retry would also cover a database that came up and failed its health check —
# which is a real failure, and one that takes the whole health budget to fail
# again, so three attempts turn a red job into a slow red job. This covers the
# fetch and nothing else: the health check, the WordPress install, WooCommerce
# and the tests are all left to fail once.
#
# Only images this machine has not got are fetched, which is what `up` did. A
# moving tag such as mariadb:11 or wordpress:php8.3-apache is not refreshed by
# either, and a machine holding all three still starts with no registry at all.
pc_pull_images() {
  local images=() missing=() image

  while IFS= read -r image; do
    images+=( "${image}" )
  done < <(pc_images)

  if (( ${#images[@]} == 0 )); then
    # Compose older than `config --images` cannot be asked what it would fetch.
    # Nothing is lost that was not already the case: `up` fetches what it needs,
    # unretried, exactly as it did before this existed.
    echo "Could not read the image list from Compose; leaving the fetch to 'up'."
    return 0
  fi

  for image in "${images[@]}"; do
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
      missing+=( "${image}" )
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    echo "Images already on this machine: ${images[*]}"
    return 0
  fi

  for image in "${missing[@]}"; do
    pc_pull_image "${image}"
  done
}

# Start the database on its own so a slow boot is reported as a slow boot.
# Starting both at once leaves the failure as Compose's dependency message.
pc_bring_up() {
  pc_pull_images
  pc_compose up -d db
  pc_wait_for_db
  pc_compose up -d wordpress db
}

pc_load_env() {
  if [[ -f "${HARNESS_ROOT}/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${HARNESS_ROOT}/.env"
    set +a
  fi

  PHP_VERSION="${PHP_VERSION:-8.3}"
  WP_VERSION="${WP_VERSION:-latest}"
  WC_VERSION="${WC_VERSION:-latest}"
  HPOS_MODE="${HPOS_MODE:-enabled}"
  WP_PORT="${WP_PORT:-8080}"
  # Right for tests and wrong for screenshots. A suite wants one fixed timezone
  # so a date assertion reads the same everywhere; a screenshot wants the
  # timezone of the shop it is pretending to be, because the dates in the
  # picture are the thing being sold. Default unchanged.
  WP_TIMEZONE="${WP_TIMEZONE:-Europe/London}"
  PLUGIN_PATH="${PLUGIN_PATH:-}"
  PLUGIN_SLUG="${PLUGIN_SLUG:-}"
  EXTRA_PLUGIN_PATH="${EXTRA_PLUGIN_PATH:-}"
  EXTRA_PLUGIN_SLUG="${EXTRA_PLUGIN_SLUG:-}"
  GENERIC_TEST_WC_INACTIVE="${GENERIC_TEST_WC_INACTIVE:-1}"
  PC_SKIP_GENERIC_TESTS="${PC_SKIP_GENERIC_TESTS:-0}"
  PC_SKIP_PLUGIN_TESTS="${PC_SKIP_PLUGIN_TESTS:-0}"
  PC_DB_WAIT_SECONDS="${PC_DB_WAIT_SECONDS:-240}"
  # Three attempts, 10s and 20s apart, is enough for a registry that dropped one
  # connection and short enough that an outage is still reported inside a minute.
  PC_PULL_ATTEMPTS="${PC_PULL_ATTEMPTS:-3}"
  PC_PULL_RETRY_SECONDS="${PC_PULL_RETRY_SECONDS:-10}"

  if [[ -n "${PLUGIN_PATH}" ]]; then
    if [[ ! -d "${PLUGIN_PATH}" ]]; then
      echo "PLUGIN_PATH is not a directory: ${PLUGIN_PATH}" >&2
      exit 1
    fi
    PLUGIN_PATH="$(cd "${PLUGIN_PATH}" && pwd)"
  fi

  if [[ -z "${PLUGIN_SLUG}" && -n "${PLUGIN_PATH}" ]]; then
    PLUGIN_SLUG="$(basename "${PLUGIN_PATH}")"
  fi

  if [[ -n "${EXTRA_PLUGIN_PATH}" ]]; then
    if [[ ! -d "${EXTRA_PLUGIN_PATH}" ]]; then
      echo "EXTRA_PLUGIN_PATH is not a directory: ${EXTRA_PLUGIN_PATH}" >&2
      exit 1
    fi
    EXTRA_PLUGIN_PATH="$(cd "${EXTRA_PLUGIN_PATH}" && pwd)"
    if [[ -z "${EXTRA_PLUGIN_SLUG}" ]]; then
      EXTRA_PLUGIN_SLUG="$(basename "${EXTRA_PLUGIN_PATH}")"
    fi
    if [[ "${EXTRA_PLUGIN_SLUG}" == "${PLUGIN_SLUG}" ]]; then
      echo "EXTRA_PLUGIN_SLUG must be different from PLUGIN_SLUG." >&2
      exit 1
    fi
  else
    EXTRA_PLUGIN_SLUG=""
  fi

  case "${HPOS_MODE}" in
    enabled|disabled) ;;
    *)
      echo "HPOS_MODE must be 'enabled' or 'disabled' (got '${HPOS_MODE}')." >&2
      exit 1
      ;;
  esac

  if [[ "${WP_VERSION}" == "latest" ]]; then
    WP_IMAGE_TAG="php${PHP_VERSION}-apache"
  else
    WP_IMAGE_TAG="${WP_VERSION}-php${PHP_VERSION}-apache"
  fi
  WPCLI_IMAGE_TAG="cli-php${PHP_VERSION}"
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-pc-${PLUGIN_SLUG:-harness}}"

  export PHP_VERSION WP_VERSION WC_VERSION HPOS_MODE WP_PORT WP_TIMEZONE
  export PLUGIN_PATH PLUGIN_SLUG EXTRA_PLUGIN_PATH EXTRA_PLUGIN_SLUG PLUGIN_TEST_COMMAND
  export GENERIC_TEST_WC_INACTIVE PC_SKIP_GENERIC_TESTS PC_SKIP_PLUGIN_TESTS
  export PC_DB_WAIT_SECONDS PC_PULL_ATTEMPTS PC_PULL_RETRY_SECONDS
  export WP_IMAGE_TAG WPCLI_IMAGE_TAG COMPOSE_PROJECT_NAME
  export HARNESS_ROOT
}

pc_require_plugin() {
  pc_load_env
  if [[ -z "${PLUGIN_PATH}" ]]; then
    echo "PLUGIN_PATH is required. Example: PLUGIN_PATH=../due-date-for-woocommerce" >&2
    exit 1
  fi
  if [[ -z "${PLUGIN_SLUG}" ]]; then
    echo "PLUGIN_SLUG is required." >&2
    exit 1
  fi
  if [[ ! -d "${PLUGIN_PATH}" ]]; then
    echo "PLUGIN_PATH does not exist: ${PLUGIN_PATH}" >&2
    exit 1
  fi
  if [[ -n "${EXTRA_PLUGIN_PATH}" && ! -d "${EXTRA_PLUGIN_PATH}" ]]; then
    echo "EXTRA_PLUGIN_PATH does not exist: ${EXTRA_PLUGIN_PATH}" >&2
    exit 1
  fi
}

pc_wp() {
  pc_require_plugin
  pc_require_docker
  pc_compose run --rm wpcli "$@"
}

pc_php_in_plugin() {
  pc_require_plugin
  pc_require_docker
  pc_compose run --rm \
    --workdir "/var/www/html/wp-content/plugins/${PLUGIN_SLUG}" \
    --entrypoint php \
    wpcli \
    "$@"
}

pc_run_plugin_command() {
  local slug="$1"
  local command="$2"

  pc_require_plugin
  pc_require_docker

  if [[ "${command}" == wp\ * ]]; then
    # shellcheck disable=SC2086
    pc_compose run --rm --workdir "/var/www/html/wp-content/plugins/${slug}" wpcli ${command#wp }
    return
  fi
  if [[ "${command}" == php\ * ]]; then
    # shellcheck disable=SC2086
    pc_compose run --rm \
      --workdir "/var/www/html/wp-content/plugins/${slug}" \
      --entrypoint php \
      wpcli \
      ${command#php }
    return
  fi
  pc_compose run --rm \
    --workdir "/var/www/html/wp-content/plugins/${slug}" \
    --entrypoint sh \
    wpcli \
    -lc "${command}"
}

pc_wait_for_wp() {
  local attempt
  echo "Waiting for WordPress..."
  for attempt in $(seq 1 60); do
    if pc_compose run --rm wpcli core version >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "WordPress did not become ready in time." >&2
  return 1
}

pc_print_config() {
  echo "Harness:     ${HARNESS_ROOT}"
  echo "Plugin path: ${PLUGIN_PATH}"
  echo "Plugin slug: ${PLUGIN_SLUG}"
  if [[ -n "${EXTRA_PLUGIN_PATH}" ]]; then
    echo "Extra path:  ${EXTRA_PLUGIN_PATH}"
    echo "Extra slug:  ${EXTRA_PLUGIN_SLUG}"
  fi
  echo "PHP:         ${PHP_VERSION}"
  echo "WordPress:   ${WP_VERSION} (image tag ${WP_IMAGE_TAG})"
  echo "WooCommerce: ${WC_VERSION}"
  echo "HPOS:        ${HPOS_MODE}"
  echo "Project:     ${COMPOSE_PROJECT_NAME}"
  echo "Site:        http://localhost:${WP_PORT}"
}
