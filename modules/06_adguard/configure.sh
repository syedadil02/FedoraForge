#!/usr/bin/env bash
# modules/06_adguard/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

launch_dns_engine() {
    log_info "Initializing AdGuard Home container core..."

    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    # Shift context cleanly to ensure proper compose project namespace
    cd "${script_dir}/compose"

    # Fire up the container deployment cycle
    docker compose up -d || exit 1

    log_info "Awaiting service convergence verification on Port 53..."

    # Retry loop: Gives Docker time to establish network plumbing
    local success=1
    for i in {1..10}; do
        # -w enforces exact word match for 53, catching ':53' without strict space dependencies
        if ss -tulpn | grep -q -w "53"; then
            success=0
            break
        fi
        sleep 1
    done

    if [[ $success -eq 0 ]]; then
        log_succ "AdGuard Home DNS Engine successfully verified active on Port 53!"
    else
        log_error "AdGuard container initialized, but socket failed to bind within the window."
        exit 1
    fi
}
launch_dns_engine
