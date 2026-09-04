#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker
pc_print_config
pc_compose up -d wordpress db
pc_wait_for_wp
echo "WordPress is up at http://localhost:${WP_PORT}"
