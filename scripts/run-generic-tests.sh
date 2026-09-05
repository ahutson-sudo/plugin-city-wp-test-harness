#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker

failed=0

run_eval() {
  local file="$1"
  set +e
  pc_wp eval-file "${file}"
  local status=$?
  set -e
  if [[ $status -ne 0 ]]; then
    failed=1
  fi
}

run_eval /opt/pc-harness/tests/generic/run.php

echo
echo "=== Plugin deactivate / activate ==="
pc_wp plugin deactivate "${PLUGIN_SLUG}"
run_eval /opt/pc-harness/tests/generic/test-after-deactivate.php
pc_wp plugin activate "${PLUGIN_SLUG}"
if [[ -n "${EXTRA_PLUGIN_SLUG}" ]]; then
  pc_wp plugin activate "${EXTRA_PLUGIN_SLUG}" >/dev/null || true
fi

if [[ "${GENERIC_TEST_WC_INACTIVE}" == "1" ]]; then
  echo
  echo "=== WooCommerce inactive ==="
  pc_wp plugin deactivate woocommerce
  run_eval /opt/pc-harness/tests/generic/test-woocommerce-inactive.php
  pc_wp plugin activate woocommerce
  pc_wp plugin activate "${PLUGIN_SLUG}"
  if [[ -n "${EXTRA_PLUGIN_SLUG}" ]]; then
    pc_wp plugin activate "${EXTRA_PLUGIN_SLUG}" >/dev/null || true
  fi
fi

exit "${failed}"
