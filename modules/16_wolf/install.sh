#!/usr/bin/env bash
# modules/16_wolf/install.sh
# Wolf Streaming Server - Installation & Storage Provisioning
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

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
    chmod -R 777 "${CONFIG_BASE_DIR}/wolf"

    # Set up runtime shared IPC boundaries
    mkdir -p /tmp/runtime-root
    mkdir -p /var/run/wolf
    chmod 777 /tmp/runtime-root /var/run/wolf

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

    # Tear down orphaned Wolf containers from previous runs so they don't trigger the port conflict
    if docker ps -a -q -f name=homelab_wolf 2>/dev/null | grep -q .; then
        log_info "Clearing orphaned Wolf framework containers from previous execution..."
        local script_dir
        script_dir=$(dirname "$(readlink -f "$0")")
        docker compose -f "${script_dir}/compose/docker-compose.yml" down 2>/dev/null || \
            docker rm -f homelab_wolf homelab_wolf_den 2>/dev/null || true
        sleep 2
    fi

    if ss -tulpn | grep -q ":8585 "; then
        log_error "Target port 8585 is blocked. Clean up host resources."
        exit 1
    fi
}

verify_gpu_availability
verify_host_state
provision_storage_assets
