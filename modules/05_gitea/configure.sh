#!/usr/bin/env bash
# modules/05_gitea/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_proxy_routing() {
    log_info "Injecting Gitea reverse proxy routing matrix into Nginx..."

    # Drop a configuration file directly into Nginx's ZFS runtime folder
    # CORRECTED: Listens on 8443 and maps cleanly to internal host port 3000
    cat << EOF > /fastpool/nginx/conf.d/gitea.conf
server {
    listen 8443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Gracefully reload Nginx configuration without dropping active connections
    log_info "Reloading Nginx runtime configuration parameters..."
    docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1
}

launch_gitea_stack() {
    # 1. Define script directory first thing so it is available safely
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Sanitizing any existing stale container states on port 3000..."
    # 2. Shift context to compose directory to isolate project scopes
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Initializing Gitea container platform infrastructure..."

    # Securely evaluate database passwords
    if [[ -z "${GITEA_DB_PASSWORD:-}" ]]; then
        log_warn "No GITEA_DB_PASSWORD variable discovered. Generating single-session transaction token..."
        export GITEA_DB_PASSWORD=$(openssl rand -hex 16)
    fi

    # 3. Bring up the stack natively using 'up -d'.
    docker compose up -d || exit 1

    # Health Verification — retry loop (Gitea needs time to run migrations on first boot)
    log_info "Awaiting service convergence verification..."
    local success=1
    for i in {1..15}; do
        if docker ps --filter "name=homelab_gitea" --filter "status=running" -q | grep -q .; then
            success=0
            break
        fi
        sleep 2
    done

    if [[ $success -eq 0 ]]; then
        log_succ "Gitea stack deployed and routing securely over your private mesh network!"
    else
        log_error "Gitea container failed to stay running after 30s."
        log_error "Last 20 lines of container logs:"
        docker logs homelab_gitea --tail 20 2>&1 || true
        exit 1
    fi
}

inject_nginx_proxy_routing
launch_gitea_stack
