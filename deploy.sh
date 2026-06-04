#!/usr/bin/env bash
# deploy.sh - Master System Orchestrator

set -euo pipefail
source "./lib_utils.sh"

# 1. Enforce Environment Input Gate
if [[ $# -eq 0 ]]; then
    log_error "Usage: ./deploy.sh <path_to_env_file>"
    log_error "Example: sudo ./deploy.sh environment/staging.env"
    exit 1
fi

ENV_FILE="$1"

if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading targeted environment definitions: ${ENV_FILE}"
    source "$ENV_FILE"
else
    log_error "Specified environment file not found: ${ENV_FILE}"
    exit 1
fi

# 2. Lock down execution logic context entirely to root parameters
if [[ $EUID -ne 0 ]]; then
   log_error "This orchestrator engine requires root permission structures. Re-execute with sudo."
   exit 1
fi

# Lock down execution logic context entirely to root parameters
if [[ $EUID -ne 0 ]]; then
   log_error "This orchestrator engine requires root permission structures. Re-execute with sudo."
   exit 1
fi

main() {
    log_info "Launching homelab bare-metal orchestration lifecycle..."
    start_transaction

    # Phase 0: System Baseline Configuration
    log_info "========== Phase 0: System Core Upgrades =========="
    source ./modules/00_base.sh

    # Phase 1: Storage Layer Execution
    log_info "========== Phase 1: ZFS Platform Deployment =========="
    (./modules/01_zfs/install.sh && ./modules/01_zfs/configure.sh) || exit 1

    # Phase 2: Secure Transport Routing
    log_info "========== Phase 2: Tailscale Node Ingestion =========="
    (./modules/02_tailscale/install.sh && ./modules/02_tailscale/configure.sh) || exit 1

    # Phase 3: Isolated Runtime Orchestrator
    log_info "========== Phase 3: Docker Engine Infrastructure =========="
    (./modules/03_docker/install.sh && ./modules/03_docker/configure.sh) || exit 1

    # Phase 4: Reverse Proxy for all the services
    log_info "========== Phase 4: Nginx Proxy Matrix =========="
    ./modules/04_nginx/install.sh && ./modules/04_nginx/configure.sh

    # Phase 5: Local Version Control Tier
    log_info "========== Phase 5: Gitea Local Git Service =========="
    (./modules/05_gitea/install.sh && ./modules/05_gitea/configure.sh) || exit 1

     # Phase 6: DNS Resolution and Routing Domain Plane
    log_info "========== Phase 6: AdGuard Home DNS System =========="
    (./modules/06_adguard/install.sh && ./modules/06_adguard/configure.sh) || exit 1

    # Phase 7: Secure Identity Credential Storage Vault
    log_info "========== Phase 7: Vaultwarden Secrets Manager =========="
    (./modules/07_vaultwarden/install.sh && ./modules/07_vaultwarden/configure.sh) || exit 1

    # Phase 8: High Performance Media Backups
    log_info "========== Phase 8: Immich Photos Cluster =========="
    (./modules/08_immich/install.sh && ./modules/08_immich/configure.sh) || exit 1

    commit_transaction
    log_succ "Orchestrator finished processing components completely without errors."
}

main
