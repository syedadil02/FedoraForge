#!/usr/bin/env bash
# modules/08_immich/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging-2}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_immich_routing() {
    log_info "Injecting Immich secure reverse proxy routes..."

    cat << EOF > /fastpool/nginx/conf.d/immich.conf
server {
    listen 443 ssl;
    server_name photos.${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    # Crucial parameters for massive raw media backups
    client_max_body_size 50000M;

    # Fast proxy buffer properties for video streaming acceleration
    proxy_read_timeout 600s;
    proxy_send_timeout 600s;
    send_timeout 600s;

    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Enable HTTP/1.1 for persistent connection tracking
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    log_info "Hot-reloading Nginx rules configuration engine..."
    docker exec homelab_nginx nginx -s reload || exit 1
}

launch_immich() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Wiping dead or stale Immich instances..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Launching Immich system processing nodes..."
    docker compose up -d || exit 1
    log_succ "Immich microservices cluster running smoothly!"
}

inject_nginx_immich_routing
launch_immich
