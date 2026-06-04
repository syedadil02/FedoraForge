#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

if command -v docker &>/dev/null; then
    log_info "Docker deployment detected on system. Skipping target install."
    exit 0
fi

log_info "Injecting official Docker-CE architecture repository definitions..."
# Using standard Fedora repository engine
sudo dnf5 config-manager addrepo --from-repofile="https://download.docker.com/linux/fedora/docker-ce.repo" || exit 1

log_info "Deploying docker-ce suite binaries..."
sudo dnf5 install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || exit 1

log_succ "Docker-CE dependencies successfully structured."
