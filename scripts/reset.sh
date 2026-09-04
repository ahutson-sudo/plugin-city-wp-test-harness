#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

pc_require_plugin
pc_require_docker
echo "Removing containers and volumes for ${COMPOSE_PROJECT_NAME}..."
pc_compose down -v --remove-orphans
echo "Environment reset. Run ./scripts/start.sh then ./scripts/install.sh."
