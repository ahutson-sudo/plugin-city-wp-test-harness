#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker

matrix="${HARNESS_ROOT}/config/matrix.tsv"
failed=0
ran=0

while IFS=$'\t' read -r php_version wp_version wc_version hpos_mode; do
  [[ -z "${php_version}" || "${php_version}" == \#* ]] && continue

  echo
  echo "######## matrix: PHP=${php_version} WP=${wp_version} WC=${wc_version} HPOS=${hpos_mode} ########"
  ran=$((ran + 1))

  PHP_VERSION="${php_version}" \
  WP_VERSION="${wp_version}" \
  WC_VERSION="${wc_version}" \
  HPOS_MODE="${hpos_mode}" \
  PLUGIN_PATH="${PLUGIN_PATH}" \
  PLUGIN_SLUG="${PLUGIN_SLUG}" \
  EXTRA_PLUGIN_PATH="${EXTRA_PLUGIN_PATH:-}" \
  EXTRA_PLUGIN_SLUG="${EXTRA_PLUGIN_SLUG:-}" \
  "${HARNESS_ROOT}/scripts/reset.sh"

  set +e
  PHP_VERSION="${php_version}" \
  WP_VERSION="${wp_version}" \
  WC_VERSION="${wc_version}" \
  HPOS_MODE="${hpos_mode}" \
  PLUGIN_PATH="${PLUGIN_PATH}" \
  PLUGIN_SLUG="${PLUGIN_SLUG}" \
  EXTRA_PLUGIN_PATH="${EXTRA_PLUGIN_PATH:-}" \
  EXTRA_PLUGIN_SLUG="${EXTRA_PLUGIN_SLUG:-}" \
  "${HARNESS_ROOT}/scripts/run-tests.sh"
  status=$?
  set -e

  if [[ $status -ne 0 ]]; then
    echo "Matrix row failed: PHP=${php_version} WP=${wp_version} WC=${wc_version} HPOS=${hpos_mode}" >&2
    failed=1
  fi
done < "${matrix}"

echo
echo "Matrix rows run: ${ran}"
exit "${failed}"
