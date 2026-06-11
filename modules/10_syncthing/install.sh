#!/usr/bin/env bash
# modules/09_syncthing/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

log_info "Provisioning ZFS backing storage pathways for Syncthing node..."

# 1. Establish structural runtime state directories
sudo mkdir -p /fastpool/syncthing/config
sudo mkdir -p /datapool/syncthing/data

# 2. Sanitize ownership to match the deploying user/group execution space
# (Prevents permission drift when mounting bare-metal ZFS blocks into Docker)
TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"

log_info "Enforcing permissions boundary (${TARGET_UID}:${TARGET_GID}) on storage points..."
sudo chown -R "${TARGET_UID}:${TARGET_GID}" /fastpool/syncthing
sudo chown -R "${TARGET_UID}:${TARGET_GID}" /datapool/syncthing
sudo chmod -R 770 /fastpool/syncthing
sudo chmod -R 770 /datapool/syncthing

log_succ "Syncthing baseline environment layout prepared."
