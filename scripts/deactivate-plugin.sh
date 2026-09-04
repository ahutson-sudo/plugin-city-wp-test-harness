#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_wp plugin deactivate "${PLUGIN_SLUG}"
echo "Deactivated ${PLUGIN_SLUG}"
