#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

log_info "Initializing systemd operational constraints for Docker runtime engine..."
systemctl daemon-reload
systemctl enable --now docker || exit 1

# Validation verification step
if systemctl is-active --quiet docker; then
    log_succ "Docker daemon is active and operating cleanly."
else
    log_error "Docker failed validation initialization checks."
    exit 1
fi
