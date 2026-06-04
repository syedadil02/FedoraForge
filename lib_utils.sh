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
