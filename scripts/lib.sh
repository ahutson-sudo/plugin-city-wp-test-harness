#!/usr/bin/env bash
# Shared helpers for Plugin City WordPress/WooCommerce test harness.

set -euo pipefail

pc_harness_root() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${here}/.." && pwd
}

HARNESS_ROOT="${HARNESS_ROOT:-$(pc_harness_root)}"

pc_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "${HARNESS_ROOT}/docker-compose.yml" "$@"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "${HARNESS_ROOT}/docker-compose.yml" "$@"
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
  GENERIC_TEST_WC_INACTIVE="${GENERIC_TEST_WC_INACTIVE:-1}"
  PC_SKIP_GENERIC_TESTS="${PC_SKIP_GENERIC_TESTS:-0}"
  PC_SKIP_PLUGIN_TESTS="${PC_SKIP_PLUGIN_TESTS:-0}"

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
  export PLUGIN_PATH PLUGIN_SLUG PLUGIN_TEST_COMMAND
  export GENERIC_TEST_WC_INACTIVE PC_SKIP_GENERIC_TESTS PC_SKIP_PLUGIN_TESTS
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
  echo "PHP:         ${PHP_VERSION}"
  echo "WordPress:   ${WP_VERSION} (image tag ${WP_IMAGE_TAG})"
  echo "WooCommerce: ${WC_VERSION}"
  echo "HPOS:        ${HPOS_MODE}"
  echo "Project:     ${COMPOSE_PROJECT_NAME}"
  echo "Site:        http://localhost:${WP_PORT}"
}
