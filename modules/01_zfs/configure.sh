#!/usr/bin/env bash
# modules/01_zfs/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

log_info "Verifying DKMS build status for ZFS modules..."
# Give the kernel tree a moment to settle and check if DKMS successfully bound the module
if ! dkms status | grep -i "zfs" | grep -q "installed"; then
    log_warn "DKMS status check unconfirmed. Attempting manual kernel tree trigger..."
    dkms autoinstall "$(uname -r)" || exit 1
fi

log_info "Injecting ZFS module definitions into the running kernel namespace..."
modprobe zfs || exit 1

log_info "Enforcing persistent boot-time module mappings..."
mkdir -p /etc/modules-load.d
echo "zfs" > /etc/modules-load.d/zfs.conf

log_info "Protecting ZFS runtime binaries from aggressive unexpected package wipes..."
mkdir -p /etc/dnf/protected.d
echo "zfs" > /etc/dnf/protected.d/zfs.conf

# Idempotency Verification Step: Confirming pool utilities can communicate with kernel driver
if zfs upgrade &>/dev/null; then
    log_succ "ZFS kernel module initialized and responsive."
else
    log_error "ZFS driver initialized but failed verification handshakes."
    exit 1
fi

# Disk variable mapping — set by the wizard (active.env) or fallback for VMs
FAST_DISK="${FASTPOOL_DISK:-/dev/vdb}"
DATA_DISK="${DATAPOOL_DISK:-/dev/vdc}"

create_storage_pools() {
    log_info "Evaluating bare-metal disk topology for ZFS allocation..."

    # 1. Provision Fastpool (NVMe)
    if ! zpool list -H -o name | grep -q "^fastpool$"; then
        log_info "Attempting to import existing 'fastpool'..."
        if zpool import -f fastpool 2>/dev/null; then
            log_succ "Successfully imported 'fastpool' from existing disk state."
        else
            log_info "Initializing 'fastpool' on target device: ${FAST_DISK}"
            # If the script previously crashed, a stale /fastpool directory might exist.
            # If it's a regular directory and NOT a mountpoint, remove it so zpool create works.
            if [ -d "/fastpool" ] && ! mountpoint -q /fastpool; then
                rm -rf /fastpool
            fi
            # -f forces creation, -O sets root pool properties
            zpool create -f -O compression=lz4 -O atime=off -m /fastpool fastpool "${FAST_DISK}" || return 1
        fi
    else
        log_info "'fastpool' already online. Skipping pool generation."
    fi

    # 2. Provision Datapool (HDD)
    if ! zpool list -H -o name | grep -q "^datapool$"; then
        log_info "Attempting to import existing 'datapool'..."
        if zpool import -f datapool 2>/dev/null; then
            log_succ "Successfully imported 'datapool' from existing disk state."
        else
            log_info "Initializing 'datapool' on target device: ${DATA_DISK}"
            if [ -d "/datapool" ] && ! mountpoint -q /datapool; then
                rm -rf /datapool
            fi
            zpool create -f -O compression=lz4 -O atime=off -m /datapool datapool "${DATA_DISK}" || return 1
        fi
    else
        log_info "'datapool' already online. Skipping pool generation."
    fi
}

create_service_datasets() {
    log_info "Structuring nested service datasets..."

    # --- FASTPOOL DATASETS (NVMe optimized) ---
    # Core Docker infrastructure
    if ! zfs list -H -o name | grep -q "^fastpool/docker$"; then
        zfs create fastpool/docker
    fi

    # High-performance application databases (Gitea, Immich, Vaultwarden)
    if ! zfs list -H -o name | grep -q "^fastpool/databases$"; then
        zfs create fastpool/databases
        # Optimize block allocation sizes specifically for relational databases
        zfs set recordsize=16k fastpool/databases
    fi

    # KVM/libvirt virtual machine disk images
    if ! zfs list -H -o name | grep -q "^fastpool/vms$"; then
        zfs create fastpool/vms
    fi


    # --- DATAPOOL DATASETS (HDD optimized) ---
    # General Samba network file shares
    if ! zfs list -H -o name | grep -q "^datapool/shares$"; then
        zfs create datapool/shares
    fi

    # Books/Kavita dedicated share subfolder
    if ! zfs list -H -o name | grep -q "^datapool/shares/books$"; then
        zfs create datapool/shares/books
    fi

    # Massive sequential storage for Immich photos/videos
    if ! zfs list -H -o name | grep -q "^datapool/media$"; then
        zfs create datapool/media
        # Large recordsizes prevent file system fragmentation on raw HDDs
        zfs set recordsize=1M datapool/media
    fi

    # Syncthing persistent data on HDD
    if ! zfs list -H -o name | grep -q "^datapool/syncthing$"; then
        zfs create datapool/syncthing
    fi
}

verify_and_mount_permissions() {
    log_info "Enforcing directory structures and permission layers..."

    # Ensure system mount paths exist and match target boundaries
    zfs mount -a

    # Fix basic permissions so Docker and local processes can bind clean mount paths
    chmod 755 /fastpool /datapool
    mkdir -p /fastpool/docker /fastpool/databases /fastpool/vms
    mkdir -p /datapool/shares /datapool/shares/books /datapool/media /datapool/syncthing

    log_succ "ZFS storage pool hierarchy successfully mounted and optimized."
}

# Run execution segments
create_storage_pools || exit 1
create_service_datasets || exit 1
verify_and_mount_permissions || exit 1
