#!/usr/bin/env bash
# modules/99_template_module/install.sh
# 
# Description: Boilerplate template for installing a new service.
# Use this file to run pre-requisite host commands (e.g. creating directories).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib_utils.sh"

# Load Environment Variables
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${SCRIPT_DIR}/../../environment/staging.env"
fi

log_info "Creating persistent storage directories for custom service..."

# Example: Create a directory on the fastpool (NVMe)
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/custom_service/config"
# Example: Create a directory on the datapool (HDD)
mkdir -p "${STORAGE_BASE_DIR:-/datapool}/custom_service/data"

log_succ "Pre-requisite setup completed for custom service."
