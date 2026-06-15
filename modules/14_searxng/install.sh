#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="${SCRIPT_DIR}/../.."

source "${REPO_ROOT}/lib_utils.sh"
source "${REPO_ROOT}/environment/staging.env"

log_info "Building SearXNG localized configuration paths..."
sudo mkdir -p "${CONFIG_BASE_DIR}/searxng"

sudo cp "${SCRIPT_DIR}/config/settings.yml" "${CONFIG_BASE_DIR}/searxng/settings.yml"
sudo chown -R "${SYSTEM_UID:-1000}:${SYSTEM_GID:-1000}" "${CONFIG_BASE_DIR}/searxng"

log_succ "SearXNG templates generated successfully."
