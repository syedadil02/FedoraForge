#!/usr/bin/env bash
# modules/17_homepage/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

log_info "Creating storage layout on ZFS fastpool for Homepage..."
mkdir -p /fastpool/homepage/config
mkdir -p /fastpool/homepage/icons

log_info "Syncing declarative configuration templates (static files)..."
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Copy all non-template config files into place
for f in "${SCRIPT_DIR}/config/"*; do
    fname="$(basename "$f")"
    # Skip .tmpl files — configure.sh handles them via envsubst
    [[ "$fname" == *.tmpl ]] && continue
    cp -r "$f" "/fastpool/homepage/config/${fname}"
done

log_info "Syncing custom service icons..."
if [ -d "${SCRIPT_DIR}/icons" ] && [ -n "$(ls -A "${SCRIPT_DIR}/icons" 2>/dev/null)" ]; then
    cp -r "${SCRIPT_DIR}/icons/"* /fastpool/homepage/icons/
else
    log_info "No bundled icons found in module repo — skipping."
fi

TARGET_UID="${SYSTEM_UID:-1000}"
TARGET_GID="${SYSTEM_GID:-1000}"
chown -R "${TARGET_UID}:${TARGET_GID}" /fastpool/homepage

if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t /fastpool/homepage || true
fi

log_succ "Homepage file systems successfully staged."
