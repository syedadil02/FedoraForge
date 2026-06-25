#!/usr/bin/env bash
# modules/18_disaster_recovery/install.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib_utils.sh"

if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${SCRIPT_DIR}/../../environment/staging.env"
fi

log_info "Creating persistent storage directories for Duplicati Disaster Recovery..."

mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/duplicati/config"
mkdir -p "${STORAGE_BASE_DIR:-/datapool}/backups/db_dumps"

log_info "Configuring firewall for Duplicati Dashboard (Port 8455)..."
if command -v firewall-cmd &>/dev/null; then
    firewall-cmd --add-port=8455/tcp --permanent
    firewall-cmd --reload
fi

log_succ "Pre-requisite setup completed for Duplicati."
