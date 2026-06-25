#!/usr/bin/env bash
# modules/16_wolf/configure.sh
# Wolf Streaming Server - Docker Deployment Configuration
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

launch_wolf_stack() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Wiping dead or stale Wolf Den instances..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    # Dynamic GPU Passthrough for Bare-Metal
    rm -f docker-compose.override.yml
    if detect_physical_gpu; then
        log_succ "Physical GPU detected! Injecting hardware passthrough into Wolf engine..."
        cat << 'EOF_OVERRIDE' > docker-compose.override.yml
services:
  wolf:
    devices:
      - /dev/dri:/dev/dri
EOF_OVERRIDE
    else
        log_warn "No physical GPU detected (or running in VM). Bypassing hardware passthrough."
    fi

    log_info "Launching Wolf gaming orchestrator..."

    export TIMEZONE CONFIG_BASE_DIR
    export WOLF_CPU_LIMIT WOLF_MEMORY_LIMIT WOLF_CPU_RESERVE WOLF_MEMORY_RESERVE

    docker compose up -d --force-recreate || exit 1
    log_info "Waiting for streaming daemon and companion UI to stabilize..."
    sleep 5
}

cleanup_stale_nginx_rules() {
    if [ -f "${CONFIG_BASE_DIR}/nginx/conf.d/wolf.conf" ]; then
        log_info "Removing obsolete Nginx config overrides..."
        rm -f "${CONFIG_BASE_DIR}/nginx/conf.d/wolf.conf"
        docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || true
    fi
}

launch_wolf_stack
cleanup_stale_nginx_rules
log_succ "Wolf core stack and Wolf Den UI are completely operational!"
log_info "Web Management Dashboard Endpoint: http://${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET}:8585"
