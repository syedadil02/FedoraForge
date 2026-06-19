#!/usr/bin/env bash
# modules/16_wolf/install.sh
# Wolf Streaming Server - Installation & Storage Provisioning
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"
source "$(dirname "$0")/../../environment/staging.env"

verify_gpu_availability() {
    log_info "Verifying GPU state wrappers for low-latency streaming pipeline..."
    if [ "${WOLF_GPU_RUNTIME:-}" = "nvidia" ] || command -v nvidia-smi &> /dev/null; then
        log_succ "Hardware acceleration assets confirmed available."
    else
        log_warn "Running in virtualized environment. Bypassing hardware acceleration targets."
    fi
}

provision_storage_assets() {
    log_info "Validating ZFS pool allocation maps..."
    local pool_name
    pool_name=$(echo "${CONFIG_BASE_DIR}" | sed 's|^/||')

    if ! zfs list -H -o name | grep -q "^${pool_name}/wolf$"; then
        log_info "Provisioning native ZFS isolated storage dataset: ${pool_name}/wolf..."
        zfs create "${pool_name}/wolf" || exit 1
    fi

    mkdir -p "${CONFIG_BASE_DIR}/wolf"/{config,logs,wolf-den}
    sudo chmod -R 777 "${CONFIG_BASE_DIR}/wolf"

    # Set up runtime shared IPC boundaries
    mkdir -p /tmp/runtime-root
    sudo mkdir -p /var/run/wolf
    sudo chmod 777 /tmp/runtime-root /var/run/wolf

    if command -v chcon &> /dev/null; then
        log_info "Enforcing SELinux file runtime security profiles for storage paths..."
        chcon -Rt container_file_t "${CONFIG_BASE_DIR}/wolf" || true
        chcon -Rt container_file_t /tmp/runtime-root || true
        chcon -Rt container_file_t /var/run/wolf || true
    fi
    log_succ "Storage provisioning pass achieved."
}

verify_host_state() {
    log_info "Validating network interface socket availability..."
    if ss -tulpn | grep -q ":8585 "; then
        log_error "Target port 8585 is blocked. Clean up host resources."
        exit 1
    fi
}

verify_gpu_availability
verify_host_state
provision_storage_assets
