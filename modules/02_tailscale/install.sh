#!/usr/bin/env bash
# modules/02_tailscale/install.sh
set -euo pipefail

# Pull down global error logging and validation engines
source "$(dirname "$0")/../../lib_utils.sh"

if command -v tailscale &>/dev/null; then
    log_info "Tailscale binary detected on host. Skipping installation."
    exit 0
fi

log_info "Injecting official Tailscale repository configuration..."
# DNF5 native repo injection
dnf5 config-manager addrepo --from-repofile="https://pkgs.tailscale.com/stable/fedora/tailscale.repo" || exit 1

log_info "Installing Tailscale package suite via DNF5..."
dnf5 install -y tailscale || exit 1

log_succ "Tailscale packages successfully installed."
