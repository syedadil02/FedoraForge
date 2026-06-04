#!/usr/bin/env bash
# modules/08_immich/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

provision_immich_storage() {
    log_info "Provisioning high-performance ZFS datasets for media stack..."

    # Create root dataset boundary
    if ! zfs list -H -o name | grep -q "^fastpool/immich$"; then
        zfs create fastpool/immich || exit 1
    fi

    # 1. Isolate Database layer and align blocks to 16k
    if ! zfs list -H -o name | grep -q "^fastpool/immich/db$"; then
        zfs create fastpool/immich/db && zfs set recordsize=16k fastpool/immich/db || true
    fi

    # 2. Isolate Upload media layer and maximize performance blocks to 1M
    if ! zfs list -H -o name | grep -q "^fastpool/immich/upload$"; then
        zfs create fastpool/immich/upload && zfs set recordsize=1M fastpool/immich/upload || true
    fi

    mkdir -p /fastpool/immich/{db,upload,cache}

    # Ensure local firewalld clears host port 8082
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=8082/tcp >/dev/null
        firewall-cmd --reload >/dev/null
    fi

    # Inject Fedora SELinux execution labels
    chcon -Rt container_file_t /fastpool/immich || exit 1
    log_succ "ZFS datasets successfully optimized for media ingestion handling."
}

provision_immich_storage
