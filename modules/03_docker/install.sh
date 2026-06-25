#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

if command -v docker &>/dev/null; then
    log_info "Docker deployment detected on system. Skipping target install."
    exit 0
fi

log_info "Injecting official Docker-CE architecture repository definitions..."
dnf5 config-manager addrepo --from-repofile="https://download.docker.com/linux/fedora/docker-ce.repo" || exit 1

log_info "Deploying docker-ce suite binaries..."
dnf5 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || exit 1

log_succ "Docker-CE dependencies successfully structured."
