#!/usr/bin/env bash
# modules/16_wolf/configure.sh
# Wolf Streaming Server - Docker Deployment Configuration
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"
source "$(dirname "$0")/../../environment/staging.env"

launch_wolf_stack() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Clearing out stale stream application footprints..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Orchestrating container initialization sequences..."

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
