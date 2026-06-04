#!/usr/bin/env bash
# modules/07_vaultwarden/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

provision_vaultwarden_storage() {
    log_info "Carving out optimized ZFS storage sets for credentials vault..."

    # Create dedicated dataset if it doesn't exist
    if ! zfs list -H -o name | grep -q "^fastpool/vaultwarden$"; then
        zfs create fastpool/vaultwarden || exit 1
        # Set database-optimized record sizes for SQLite page alignment
        zfs set recordsize=64k fastpool/vaultwarden || exit 1
    fi

    mkdir -p /fastpool/vaultwarden/data

    # Apply Fedora 44 SELinux compliance contexts
    chcon -Rt container_file_t /fastpool/vaultwarden || exit 1

    log_succ "Storage fabric allocated and optimized for Vaultwarden."
}

provision_vaultwarden_storage
