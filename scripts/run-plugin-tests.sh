#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker

failed=0
found_any=0

run_discovered_tests() {
  local slug="$1"
  local path="$2"
  local label="$3"
  local -a commands=()
  local line command status

  while IFS= read -r line; do
    if [[ -n "${line}" ]]; then
      commands+=( "${line}" )
    fi
  done < <(php "${HARNESS_ROOT}/scripts/discover-plugin-tests.php" "${path}")

  if [[ ${#commands[@]} -eq 0 ]]; then
    echo "No ${label} tests discovered in ${path}."
    return 0
  fi

  found_any=1
  echo "Discovered ${label} tests:"
  printf '  - %s\n' "${commands[@]}"

  for command in "${commands[@]}"; do
    echo
    echo ">>> [${slug}] ${command}"
    set +e
    pc_run_plugin_command "${slug}" "${command}"
    status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      echo "Plugin test failed (${slug}): ${command}" >&2
      failed=1
    fi
  done
}

run_discovered_tests "${PLUGIN_SLUG}" "${PLUGIN_PATH}" "plugin"

if [[ -n "${EXTRA_PLUGIN_PATH}" ]]; then
  echo
  PLUGIN_TEST_COMMAND="" run_discovered_tests "${EXTRA_PLUGIN_SLUG}" "${EXTRA_PLUGIN_PATH}" "extra plugin"
fi

if [[ ${found_any} -eq 0 ]]; then
  echo "Add tests/run-tests.php, tests/wp-integration.php, tests/run-harness.sh,"
  echo "bin/plugin-city-tests.sh, or a composer script named plugin-city-tests."
fi

exit "${failed}"
