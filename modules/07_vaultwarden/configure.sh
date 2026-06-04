#!/usr/bin/env bash
# modules/07_vaultwarden/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging-2}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_vault_routing() {
    log_info "Injecting Vaultwarden proxy profiles into Nginx core..."

    cat << EOF > /fastpool/nginx/conf.d/vaultwarden.conf
server {
    listen 443 ssl;
    server_name vault.${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    # Core Web Vault Application
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Real-Time WebSocket Synchronization Hub
    location /notifications/hub {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    log_info "Triggering hot reload on Nginx configuration blocks..."
    docker exec homelab_nginx nginx -s reload || exit 1
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
    sleep 3
    if docker ps | grep -q "homelab_vaultwarden"; then
        log_succ "Vaultwarden framework deployed live across your mesh network!"
    else
        log_error "Vaultwarden engine failed runtime verification states."
        exit 1
    fi
}

inject_nginx_vault_routing
launch_vaultwarden
