#!/usr/bin/env bash
# modules/07_vaultwarden/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_vault_routing() {
    log_info "Injecting Vaultwarden proxy profiles into Nginx core..."

    # CORRECTED: Added backslashes to escape all native Nginx routing variables
    cat << EOF > /fastpool/nginx/conf.d/vaultwarden.conf
server {
    listen 8444 ssl;
    server_name _;

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host:\$server_port;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    log_info "Verifying syntax and triggering hot reload on Nginx configuration..."
    # CORRECTED: Runs a configuration pre-flight validation check before applying changes
    docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1
}

launch_vaultwarden() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Sanitizing stale Vaultwarden matrix instances..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Launching Vaultwarden secure payload systems..."
    docker compose up -d || exit 1

    # Verify container state convergence
    local success=1
    for i in {1..10}; do
        if docker ps --filter "name=homelab_vaultwarden" --filter "status=running" -q | grep -q .; then
            success=0
            break
        fi
        sleep 2
    done

    if [[ $success -eq 0 ]]; then
        log_succ "Vaultwarden framework deployed live across your mesh network!"
    else
        log_error "Vaultwarden container failed to stay running after 20s."
        docker logs homelab_vaultwarden --tail 20 2>&1 || true
        exit 1
    fi
}

inject_nginx_vault_routing
launch_vaultwarden
