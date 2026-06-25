#!/usr/bin/env bash
# modules/10_syncthing/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

log_info "Provisioning ZFS backing storage pathways for Syncthing node..."

# Syncthing config lives on fastpool (NVMe, fast); data on datapool (HDD)
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/syncthing/config"
mkdir -p "${STORAGE_BASE_DIR:-/datapool}/syncthing/data"

TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"

log_info "Enforcing permissions boundary (${TARGET_UID}:${TARGET_GID}) on storage points..."
chown -R "${TARGET_UID}:${TARGET_GID}" "${CONFIG_BASE_DIR:-/fastpool}/syncthing"
chown -R "${TARGET_UID}:${TARGET_GID}" "${STORAGE_BASE_DIR:-/datapool}/syncthing"
chmod -R 770 "${CONFIG_BASE_DIR:-/fastpool}/syncthing"
chmod -R 770 "${STORAGE_BASE_DIR:-/datapool}/syncthing"

# SELinux contexts for container access
if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${CONFIG_BASE_DIR:-/fastpool}/syncthing" || true
    chcon -Rt container_file_t "${STORAGE_BASE_DIR:-/datapool}/syncthing" || true
fi

log_succ "Syncthing baseline environment layout prepared."
