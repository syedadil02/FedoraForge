#!/usr/bin/env bash
# modules/15_freshrss/install.sh
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="${SCRIPT_DIR}/../.."

source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

log_info "Prepping FreshRSS storage directories..."

# Ensure directories exist
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/freshrss/data"
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/freshrss/extensions"

# Set permissions so the internal webserver user (www-data/uid 33) can write to the data volumes
chown -R 33:33 "${CONFIG_BASE_DIR:-/fastpool}/freshrss"

# SELinux context for container access
if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${CONFIG_BASE_DIR:-/fastpool}/freshrss" || true
fi

log_info "Launching FreshRSS Container..."
compose_up_with_retry "${SCRIPT_DIR}/compose" 3

log_succ "FreshRSS is up and listening on port 8449!"
