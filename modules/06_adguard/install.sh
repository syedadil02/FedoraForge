#!/usr/bin/env bash
# modules/06_adguard/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

disable_systemd_resolved_stub() {
    log_info "Executing absolute systemd-resolved termination strategy..."

    # 1. Forcefully stop and disable the service
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true

    # 2. Mask the service to prevent NetworkManager from waking it up
    systemctl mask systemd-resolved || exit 1

    # 3. Destroy the old stub symlink and drop a clean static loopback resolution file
    rm -f /etc/resolv.conf
    log_info "Creating static local resolution loopback matrix..."

    cat << EOF > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
options edns0 trust-ad
EOF

    log_succ "systemd-resolved permanently neutralized and masked."
}

configure_host_firewall() {
    log_info "Automating host firewalld ingress rules for DNS plane..."

    # Check if firewalld is running before adding rules to prevent execution crashes
    if systemctl is-active --quiet firewalld; then
        log_info "Active firewalld instance discovered. Injecting port parameters..."

        # 1. Open Port 8080 for AdGuard Web UI Setup Console
        firewall-cmd --permanent --add-port=8080/tcp >/dev/null

        # 2. Open Port 53 for standard DNS traffic (TCP and UDP)
        firewall-cmd --permanent --add-port=53/tcp >/dev/null
        firewall-cmd --permanent --add-port=53/udp >/dev/null

        # 3. Reload firewall engine to push configuration changes live immediately
        firewall-cmd --reload >/dev/null
        log_succ "Host firewalld matrices successfully configured and reloaded."
    else
        log_warn "Firewalld daemon is inactive or not installed. Skipping port binding rules."
    fi
}

provision_adguard_storage() {
    log_info "Allocating storage footprints on NVMe pools..."

    if ! zfs list -H -o name | grep -q "^fastpool/adguard$"; then
        zfs create fastpool/fastpool/adguard || zfs create fastpool/adguard || true
    fi

    # Handle directory tree boundaries safely
    if [ ! -d "/fastpool/adguard" ]; then
        mkdir -p /fastpool/adguard/{work,conf}
    fi

    # Seed initial configuration parameters to force port 8080 setup rules
    cat << EOF > /fastpool/adguard/conf/AdGuardHome.yaml
http:
  address: 0.0.0.0:8080
  dns:
    bind_hosts:
      - 0.0.0.0
    port: 53
EOF

    # Apply Fedora 44 SELinux compliance boundaries
    chcon -Rt container_file_t /fastpool/adguard || exit 1

    log_succ "Host platform layer prepared for AdGuard deployment."
}

# Main Execution Flow Array
disable_systemd_resolved_stub
configure_host_firewall
provision_adguard_storage
