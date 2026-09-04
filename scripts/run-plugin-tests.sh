#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker

commands=()
while IFS= read -r line; do
  if [[ -n "${line}" ]]; then
    commands+=("${line}")
  fi
done < <(php "${HARNESS_ROOT}/scripts/discover-plugin-tests.php" "${PLUGIN_PATH}")

if [[ ${#commands[@]} -eq 0 ]]; then
  echo "No plugin-specific tests discovered in ${PLUGIN_PATH}."
  echo "Add tests/run-tests.php, tests/wp-integration.php, tests/run-harness.sh,"
  echo "bin/plugin-city-tests.sh, or a composer script named plugin-city-tests."
  exit 0
fi

echo "Discovered plugin tests:"
printf '  - %s\n' "${commands[@]}"

failed=0
for command in "${commands[@]}"; do
  echo
  echo ">>> ${command}"
  set +e
  if [[ "${command}" == wp\ * ]]; then
    # shellcheck disable=SC2086
    pc_compose run --rm --workdir "/var/www/html/wp-content/plugins/${PLUGIN_SLUG}" wpcli ${command#wp }
    status=$?
  elif [[ "${command}" == php\ * ]]; then
    # shellcheck disable=SC2086
    pc_php_in_plugin ${command#php }
    status=$?
  else
    pc_compose run --rm \
      --workdir "/var/www/html/wp-content/plugins/${PLUGIN_SLUG}" \
      --entrypoint sh \
      wpcli \
      -lc "${command}"
    status=$?
  fi
  set -e
  if [[ $status -ne 0 ]]; then
    echo "Plugin test failed: ${command}" >&2
    failed=1
  fi
done

exit "${failed}"
