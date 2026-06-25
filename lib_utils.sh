#!/usr/bin/env bash
# lib_utils.sh - Core Transaction and Safety Utilities

# Text formatting colors
export CLR_RST="\033[0m"
export CLR_RED="\033[0;31m"
export CLR_GRN="\033[0;32m"
export CLR_YLW="\033[0;33m"
export CLR_BLU="\033[0;34m"

# Track structural system state changes for rollback engine
TRANSACTION_ACTIVE=false
declare -g -a BACKUP_FILES=()
declare -g -a INSTALLED_PACKAGES=()

log_info()  { echo -e "${CLR_BLU}[INFO]  $(date '+%Y-%m-%d %H:%M:%S') - $1${CLR_RST}"; }
log_warn()  { echo -e "${CLR_YLW}[WARN]  $(date '+%Y-%m-%d %H:%M:%S') - $1${CLR_RST}"; }
log_error() { echo -e "${CLR_RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1${CLR_RST}"; }
log_succ()  { echo -e "${CLR_GRN}[SUCCESS] $1${CLR_RST}"; }

rollback_engine() {
    if [ "$TRANSACTION_ACTIVE" = true ]; then
        log_warn "Execution execution anomaly detected. Reverting system state..."

        # 1. Restore configuration backups
        for bak in "${BACKUP_FILES[@]}"; do
            orig="${bak%.bak}"
            if [ -f "$bak" ]; then
                mv "$bak" "$orig"
                log_info "Restored configuration asset: $orig"
            fi
        done

        # 2. Cleanup partial files
        rm -rf /tmp/homelab_tx_*

        # 3. Aggressive Space Reclamation (Docker)
        # If the script fails, clean up stopped containers, unused networks, and dangling images
        # to ensure the next run doesn't hit a "No space left on device" error.
        if command -v docker &>/dev/null; then
            log_info "Reclaiming storage: pruning orphaned containers and dangling images..."
            docker system prune -a -f --volumes 2>/dev/null || true
        fi

        log_succ "System state successfully reverted to baseline consistency."
    fi
}

# Bind global trap constraints
trap rollback_engine EXIT ERR SIGINT SIGTERM

start_transaction() {
    TRANSACTION_ACTIVE=true
    log_info "Transactional boundary context established."
}

commit_transaction() {
    TRANSACTION_ACTIVE=false
    # Purge working staging artifacts
    rm -f "${BACKUP_FILES[@]}" 2>/dev/null || true
    rm -rf /tmp/homelab_tx_*
    log_succ "System modifications committed completely."
}

# Dynamic Hardware Detection
# Detects if a real, physical GPU (Intel, AMD, Nvidia) exists.
# Ignores virtual GPUs (VirtIO, QXL, VMware) which can crash hardware encoders.
detect_physical_gpu() {
    if command -v lspci &>/dev/null; then
        if lspci | grep -iE 'vga|3d|display' | grep -ivE 'virtio|qxl|vmware|virtualbox' &>/dev/null; then
            if [[ -d /dev/dri ]]; then
                return 0 # True: Physical GPU exists and /dev/dri is exposed
            fi
        fi
    fi
    return 1 # False: No physical GPU found
}

# Retry-aware Docker Compose launcher.
# Usage: compose_up_with_retry [compose_dir] [max_retries]
# Handles transient Docker Hub 503s and network blips.
compose_up_with_retry() {
    local compose_dir="${1:-.}"
    local max_retries="${2:-3}"
    local attempt=1

    cd "$compose_dir"
    docker compose down 2>/dev/null || true

    while [ ${attempt} -le ${max_retries} ]; do
        log_info "Docker Compose pull+up attempt ${attempt}/${max_retries}..."
        if docker compose pull 2>&1 && docker compose up -d --force-recreate 2>&1; then
            return 0
        fi

        if [ ${attempt} -lt ${max_retries} ]; then
            local wait=$((attempt * 10))
            log_warn "Registry pull failed (attempt ${attempt}/${max_retries}). Retrying in ${wait}s..."
            sleep ${wait}
        fi
        attempt=$((attempt + 1))
    done

    log_error "Docker Compose failed after ${max_retries} attempts in ${compose_dir}."
    return 1
}
