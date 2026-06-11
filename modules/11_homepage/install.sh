#!/usr/bin/env bash
# modules/13_homepage/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

log_info "Creating storage layout on ZFS fastpool for Homepage..."
sudo mkdir -p /fastpool/homepage/config

log_info "Syncing declarative configuration templates..."
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
sudo cp -r "${SCRIPT_DIR}/config/"* /fastpool/homepage/config/

# Align file permissions with host runtime contexts
TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"
sudo chown -R "${TARGET_UID}:${TARGET_GID}" /fastpool/homepage
sudo chmod -R 775 /fastpool/homepage/config

log_succ "Homepage file systems successfully staged."
