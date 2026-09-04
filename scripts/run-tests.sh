#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker
pc_print_config

"${HARNESS_ROOT}/scripts/start.sh"
"${HARNESS_ROOT}/scripts/install.sh"

failed=0

if [[ "${PC_SKIP_GENERIC_TESTS}" != "1" ]]; then
  echo
  echo "=== Generic harness tests ==="
  set +e
  "${HARNESS_ROOT}/scripts/run-generic-tests.sh"
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    failed=1
  fi
fi

if [[ "${PC_SKIP_PLUGIN_TESTS}" != "1" ]]; then
  echo
  echo "=== Plugin-specific tests ==="
  set +e
  "${HARNESS_ROOT}/scripts/run-plugin-tests.sh"
  status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    failed=1
  fi
fi

if [[ $failed -ne 0 ]]; then
  echo
  echo "Tests failed. Recent error logs:"
  "${HARNESS_ROOT}/scripts/error-log.sh" || true
  exit 1
fi

echo
echo "All requested tests passed."
