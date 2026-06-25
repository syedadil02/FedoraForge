#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="${SCRIPT_DIR}/../.."

source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

log_info "Building SearXNG localized configuration paths..."
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/searxng"

cp "${SCRIPT_DIR}/config/settings.yml" "${CONFIG_BASE_DIR:-/fastpool}/searxng/settings.yml"
chown -R "${SYSTEM_UID:-1000}:${SYSTEM_GID:-1000}" "${CONFIG_BASE_DIR:-/fastpool}/searxng"

# SELinux context for container access
if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${CONFIG_BASE_DIR:-/fastpool}/searxng" || true
fi

log_succ "SearXNG templates generated successfully."
