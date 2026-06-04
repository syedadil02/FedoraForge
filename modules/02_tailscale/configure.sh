#!/usr/bin/env bash
# modules/02_tailscale/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Read variables loaded from environment/staging.env
TS_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

if [[ -z "$TS_AUTH_KEY" ]]; then
    log_error "Missing TAILSCALE_AUTH_KEY variable in your environment profile!"
    exit 1
fi

log_info "Initializing tailscaled systemd service parameters..."
systemctl daemon-reload
systemctl enable --now tailscaled || exit 1

# Check if already authenticated to prevent consuming keys repeatedly
if tailscale status &>/dev/null; then
    log_info "Machine is already authenticated and active on the Tailnet. Skipping registration."
    log_succ "Tailscale mesh network interface state verified active."
    exit 0
fi

log_info "Authenticating staging node to the Tailscale mesh network..."
# --accept-dns=true ensures MagicDNS is respected
# --timeout keeps the script from hanging indefinitely if keys expire
sudo tailscale up --authkey="${TAILSCALE_AUTH_KEY}" --accept-dns=true --timeout=30s || exit 1

# Idempotency Verification Check
log_info "Verifying kernel tunnel interface generation..."
if ip addr show dev tailscale0 &>/dev/null; then
    LOCAL_TS_IP=$(tailscale ip -4)
    log_succ "Tailscale interface online! Staging node IP address: ${LOCAL_TS_IP}"
else
    log_error "Tailscale service running, but kernel network interface 'tailscale0' failed allocation."
    exit 1
fi
