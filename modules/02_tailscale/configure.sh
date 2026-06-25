#!/usr/bin/env bash
# modules/02_tailscale/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

# Read variables loaded from environment
TS_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"

if [[ -z "$TS_AUTH_KEY" ]]; then
    log_warn "No TAILSCALE_AUTH_KEY found. Launching tailscale up interactively..."
    log_warn "You will need to visit the login URL and authenticate manually."
fi

# Ensure systemd-resolved is active — Tailscale's MagicDNS depends on it on Fedora
log_info "Configuring systemd-resolved for Tailscale MagicDNS integration..."
systemctl unmask systemd-resolved 2>/dev/null || true
systemctl enable --now systemd-resolved || exit 1

# /etc/resolv.conf MUST be a symlink to the systemd-resolved stub.
# If it's a static file, Tailscale can't inject its MagicDNS resolver.
if [ ! -L /etc/resolv.conf ] || [ "$(readlink /etc/resolv.conf)" != "/run/systemd/resolve/stub-resolv.conf" ]; then
    log_info "Re-linking /etc/resolv.conf to systemd-resolved stub..."
    rm -f /etc/resolv.conf
    ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
fi

log_info "Initializing tailscaled systemd service parameters..."
systemctl daemon-reload
systemctl enable --now tailscaled || exit 1

# Check if already authenticated to prevent consuming keys repeatedly
if tailscale status &>/dev/null; then
    log_info "Machine is already authenticated and active on the Tailnet. Skipping registration."
else
    log_info "Authenticating node to the Tailscale mesh network..."
    # --accept-dns=true ensures MagicDNS is respected
    if [[ -n "$TS_AUTH_KEY" ]]; then
        tailscale up \
            --authkey="${TS_AUTH_KEY}" \
            --hostname="${TAILSCALE_HOSTNAME}" \
            --accept-dns=true \
            --timeout=60s || exit 1
    else
        # Fallback: interactive auth (prints login URL)
        tailscale up \
            --hostname="${TAILSCALE_HOSTNAME}" \
            --accept-dns=true || exit 1
    fi
fi

# Idempotency verification
log_info "Verifying kernel tunnel interface generation..."
if ip addr show dev tailscale0 &>/dev/null; then
    LOCAL_TS_IP=$(tailscale ip -4)
    log_succ "Tailscale interface online! Node IP address: ${LOCAL_TS_IP}"

    if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        log_info "Adding tailscale0 interface to trusted firewall zone..."
        firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 || true
        firewall-cmd --reload || true
    fi
else
    log_error "Tailscale service running, but kernel network interface 'tailscale0' failed allocation."
    exit 1
fi

# Dynamically discover and export the actual tailnet DNS name
log_info "Discovering actual tailnet domain suffix from MagicDNS..."
ACTUAL_TAILNET=$(tailscale status --json | python3 -c \
    "import json,sys; s=json.load(sys.stdin); print(list(s['TailscaleIPs'])[0] if 'TailscaleIPs' in s else '')" 2>/dev/null || true)

# Better way: get the FQDN from tailscale status
TS_FQDN=$(tailscale status --json 2>/dev/null | python3 -c \
    "import json,sys; s=json.load(sys.stdin); print(s.get('Self', {}).get('DNSName', '').rstrip('.'))" 2>/dev/null || true)

if [[ -n "$TS_FQDN" ]]; then
    # Extract tailnet suffix (everything after the first dot)
    DETECTED_TAILNET="${TS_FQDN#*.}"
    DETECTED_HOSTNAME="${TS_FQDN%%.*}"

    log_info "Detected Tailnet DNS: ${TS_FQDN}"
    log_info "Detected Hostname: ${DETECTED_HOSTNAME}, Tailnet: ${DETECTED_TAILNET}"

    # Update the active env file with real tailnet values if it exists
    if [[ -n "${ENV_FILE:-}" && -f "${ENV_FILE}" ]]; then
        sed -i "s|^export TAILSCALE_TAILNET=.*|export TAILSCALE_TAILNET=\"${DETECTED_TAILNET}\"|" "${ENV_FILE}"
        sed -i "s|^export TAILSCALE_HOSTNAME=.*|export TAILSCALE_HOSTNAME=\"${DETECTED_HOSTNAME}\"|" "${ENV_FILE}"
    fi

    # Re-export the live vars for all subsequent modules in this session
    export TAILSCALE_TAILNET="${DETECTED_TAILNET}"
    export TAILSCALE_HOSTNAME="${DETECTED_HOSTNAME}"
    log_succ "Tailnet domain updated: ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET}"
else
    log_warn "Could not auto-detect tailnet suffix. Keeping configured value: ${TAILSCALE_TAILNET:-unknown}"
fi
