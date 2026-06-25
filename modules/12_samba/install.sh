#!/usr/bin/env bash
set -euo pipefail

# Find the project root directory relative to this script
REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

# Samba shares live on the HDD datapool, not the NVMe fastpool
SAMBA_SHARES_DIR="${STORAGE_BASE_DIR:-/datapool}/shares"

log_info "Creating Samba shared directory layout using HDD path: ${SAMBA_SHARES_DIR}..."
mkdir -p "${SAMBA_SHARES_DIR}/books" "${SAMBA_SHARES_DIR}/public"

TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"
chown -R "${TARGET_UID}:${TARGET_GID}" "${SAMBA_SHARES_DIR}"
chmod -R 775 "${SAMBA_SHARES_DIR}"

# Enforce SELinux contexts for container access
if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${SAMBA_SHARES_DIR}" || true
fi

log_succ "Samba file systems structured successfully (${SAMBA_SHARES_DIR})."
