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
  local waited="${1:-0}" id
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
    docker inspect --format '{{ range .State.Health.Log }}{{ .Start }} exit={{ .ExitCode }} took={{ .End.Sub .Start }} {{ printf "%q" .Output }}
{{ end }}' "${id}" || true
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
      echo "  still ${status} after ${waited}s (failed probes in a row: ${streak:-unknown})"
    fi
  done

  echo "The database did not become healthy within ${limit}s." >&2
  pc_explain_startup_failure "${limit}"
  return 1
}

# Start the database on its own so a slow boot is reported as a slow boot.
# Starting both at once leaves the failure as Compose's dependency message.
pc_bring_up() {
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
  PLUGIN_PATH="${PLUGIN_PATH:-}"
  PLUGIN_SLUG="${PLUGIN_SLUG:-}"
  EXTRA_PLUGIN_PATH="${EXTRA_PLUGIN_PATH:-}"
  EXTRA_PLUGIN_SLUG="${EXTRA_PLUGIN_SLUG:-}"
  GENERIC_TEST_WC_INACTIVE="${GENERIC_TEST_WC_INACTIVE:-1}"
  PC_SKIP_GENERIC_TESTS="${PC_SKIP_GENERIC_TESTS:-0}"
  PC_SKIP_PLUGIN_TESTS="${PC_SKIP_PLUGIN_TESTS:-0}"
  PC_DB_WAIT_SECONDS="${PC_DB_WAIT_SECONDS:-240}"

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

  export PHP_VERSION WP_VERSION WC_VERSION HPOS_MODE WP_PORT
  export PLUGIN_PATH PLUGIN_SLUG EXTRA_PLUGIN_PATH EXTRA_PLUGIN_SLUG PLUGIN_TEST_COMMAND
  export GENERIC_TEST_WC_INACTIVE PC_SKIP_GENERIC_TESTS PC_SKIP_PLUGIN_TESTS
  export PC_DB_WAIT_SECONDS
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
