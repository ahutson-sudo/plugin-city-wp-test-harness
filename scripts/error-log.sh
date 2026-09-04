#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker

echo "=== wp-content/debug.log ==="
pc_compose exec -T wordpress sh -c 'if [ -f /var/www/html/wp-content/debug.log ]; then cat /var/www/html/wp-content/debug.log; else echo "(empty)"; fi'

echo
echo "=== wp-content/php-error.log ==="
pc_compose exec -T wordpress sh -c 'if [ -f /var/www/html/wp-content/php-error.log ]; then cat /var/www/html/wp-content/php-error.log; else echo "(empty)"; fi'
