#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_wp plugin activate "${PLUGIN_SLUG}"
echo "Activated ${PLUGIN_SLUG}"
