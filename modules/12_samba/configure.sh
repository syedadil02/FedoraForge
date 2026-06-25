#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd "${SCRIPT_DIR}/compose"

log_info "Launching Samba file sharing stack..."
docker compose down 2>/dev/null || true
docker compose up -d --force-recreate

log_succ "Samba engine is online (Ports 139/445)!"
