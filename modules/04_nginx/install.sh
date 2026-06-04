#!/usr/bin/env bash
# modules/04_nginx/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Staging Environment Variables Fallback
TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

verify_host_state() {
    log_info "Verifying host network state for Nginx proxy binding..."

    # Check if anything is already occupying port 80 or 443 on the host
    if ss -tulpn | grep -E -q ":(80|443) "; then
        log_error "Port conflict detected! Another service is running on port 80 or 443."
        ss -tulpn | grep -E ":(80|443) "
        exit 1
    fi
}

provision_storage_assets() {
    log_info "Configuring NVMe storage paths for Nginx reverse proxy..."

    # Create dedicated ZFS dataset for your reverse proxy configurations
    if ! zfs list -H -o name | grep -q "^fastpool/nginx$"; then
        log_info "Provisioning fastpool/nginx dataset..."
        zfs create fastpool/nginx || exit 1
    fi

    # Build internal directory skeleton
    mkdir -p /fastpool/nginx/{conf.d,certs,logs}

    # Enforce SELinux contexts for Fedora 44 container runtimes
    log_info "Applying SELinux container security labels to ZFS paths..."
    chcon -Rt container_file_t /fastpool/nginx || exit 1
}

stage_configurations() {
    log_info "Staging Nginx template assets into production data layers..."

    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    # Copy base configuration file safely
    cp "${script_dir}/templates/nginx.conf.tmpl" /fastpool/nginx/nginx.conf

    log_succ "Nginx target deployment dependencies successfully staged."
}

verify_host_state
provision_storage_assets
stage_configurations
