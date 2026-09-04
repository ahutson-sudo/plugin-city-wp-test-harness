#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker
pc_compose down
echo "Environment stopped. Database volume is kept. Use ./scripts/reset.sh to wipe it."
