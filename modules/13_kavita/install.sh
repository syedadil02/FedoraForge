#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

log_info "Staging Kavita instance layouts on ${STORAGE_BASE_DIR}/shares/books..."

# Kavita config lives on fastpool (NVMe, fast); books live on datapool (HDD)
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/kavita/config"
mkdir -p "${STORAGE_BASE_DIR:-/datapool}/shares/books"

chown -R "${SYSTEM_UID:-1000}:${SYSTEM_GID:-1000}" "${CONFIG_BASE_DIR:-/fastpool}/kavita"

# SELinux contexts for container access
if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${CONFIG_BASE_DIR:-/fastpool}/kavita" || true
    chcon -Rt container_file_t "${STORAGE_BASE_DIR:-/datapool}/shares/books" || true
fi

log_succ "Kavita filesystem definitions updated."
