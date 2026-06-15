#!/usr/bin/env bash
set -euo pipefail

# Find the project root directory relative to this script
REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"
source "${REPO_ROOT}/environment/staging.env"

log_info "Creating Samba shared directory layout using base path: ${CONFIG_BASE_DIR}..."
sudo mkdir -p "${CONFIG_BASE_DIR}/shares/books" "${CONFIG_BASE_DIR}/shares/public"

TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"
sudo chown -R "${TARGET_UID}:${TARGET_GID}" "${CONFIG_BASE_DIR}/shares"
sudo chmod -R 775 "${CONFIG_BASE_DIR}/shares"

log_succ "Samba file systems structured successfully."
