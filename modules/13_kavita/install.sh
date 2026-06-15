#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"
source "${REPO_ROOT}/environment/staging.env"

log_info "Staging Kavita instance layouts on ${CONFIG_BASE_DIR}..."
sudo mkdir -p "${CONFIG_BASE_DIR}/kavita/config"

sudo chown -R "${SYSTEM_UID:-1000}:${SYSTEM_GID:-1000}" "${CONFIG_BASE_DIR}/kavita"
log_succ "Kavita filesystem definitions updated."
