#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker
pc_print_config

if ! pc_compose ps -q wordpress 2>/dev/null | grep -q .; then
  pc_compose up -d wordpress db
fi
pc_wait_for_wp

if ! pc_wp core is-installed >/dev/null 2>&1; then
  echo "Installing WordPress..."
  pc_wp core install \
    --url="http://localhost:${WP_PORT}" \
    --title="Plugin City Test" \
    --admin_user=admin \
    --admin_password=admin \
    --admin_email=admin@example.test \
    --skip-email
fi

pc_wp option update timezone_string "Europe/London" >/dev/null
pc_wp rewrite structure '/%postname%/' --hard >/dev/null

if pc_wp plugin is-installed woocommerce >/dev/null 2>&1; then
  current_wc="$(pc_wp plugin get woocommerce --field=version || true)"
else
  current_wc=""
fi

if [[ "${WC_VERSION}" == "latest" ]]; then
  echo "Installing latest WooCommerce..."
  pc_wp plugin install woocommerce --activate --force
else
  if [[ "${current_wc}" != "${WC_VERSION}" ]]; then
    echo "Installing WooCommerce ${WC_VERSION}..."
    pc_wp plugin install woocommerce --version="${WC_VERSION}" --activate --force
  else
    pc_wp plugin activate woocommerce >/dev/null || true
    echo "WooCommerce ${current_wc} already installed."
  fi
fi

pc_wp plugin activate woocommerce >/dev/null || true

echo "Applying HPOS mode: ${HPOS_MODE}"
pc_wp eval-file /opt/pc-harness/tests/helpers/hpos-cli.php

if ! pc_wp plugin is-installed "${PLUGIN_SLUG}" >/dev/null 2>&1; then
  echo "Mounted plugin '${PLUGIN_SLUG}' was not found in wp-content/plugins." >&2
  echo "Check PLUGIN_PATH and PLUGIN_SLUG." >&2
  exit 1
fi

pc_wp plugin activate "${PLUGIN_SLUG}"

if [[ -n "${EXTRA_PLUGIN_SLUG}" ]]; then
  if ! pc_wp plugin is-installed "${EXTRA_PLUGIN_SLUG}" >/dev/null 2>&1; then
    echo "Mounted extra plugin '${EXTRA_PLUGIN_SLUG}' was not found in wp-content/plugins." >&2
    echo "Check EXTRA_PLUGIN_PATH and EXTRA_PLUGIN_SLUG." >&2
    exit 1
  fi
  pc_wp plugin activate "${EXTRA_PLUGIN_SLUG}"
fi

echo "Install complete."
pc_wp plugin list --status=active
