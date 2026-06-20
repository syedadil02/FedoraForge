#!/usr/bin/env bash
# modules/11_homepage/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

log_info "Creating storage layout on ZFS fastpool for Homepage..."
sudo mkdir -p /fastpool/homepage/config
sudo mkdir -p /fastpool/homepage/icons

log_info "Syncing declarative configuration templates..."
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
sudo cp -r "${SCRIPT_DIR}/config/"* /fastpool/homepage/config/

log_info "Syncing custom service icons..."
if [ -d "${SCRIPT_DIR}/icons" ] && [ -n "$(ls -A "${SCRIPT_DIR}/icons" 2>/dev/null)" ]; then
    sudo cp -r "${SCRIPT_DIR}/icons/"* /fastpool/homepage/icons/
else
    log_info "No bundled icons found in module repo — skipping (drop files in modules/11_homepage/icons/ to ship them)."
fi

# Align file permissions with host runtime contexts
TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"
sudo chown -R "${TARGET_UID}:${TARGET_GID}" /fastpool/homepage
sudo chmod -R 775 /fastpool/homepage/config /fastpool/homepage/icons

log_succ "Homepage file systems successfully staged."
