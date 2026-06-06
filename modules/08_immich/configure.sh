#!/usr/bin/env bash
# modules/08_immich/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging-2}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_immich_routing() {
    log_info "Injecting Immich secure reverse proxy routes with clean backend forwarding..."

    cat << EOF > /fastpool/nginx/conf.d/immich.conf
server {
    listen 8445 ssl;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    client_max_body_size 50000M;

    # 1. Clear out the spoofed hardcoded /api/server/ping route so the modern backend can handle it natively
    location = /api/server/ping {
        proxy_pass http://172.17.0.1:8082;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 2. Catch-all location block for UI assets and production API calls
    location / {
        # Using the Docker bridge IP to route from inside the nginx container out to the host mapping cleanly
        proxy_pass http://172.17.0.1:8082;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSockets support (Mandatory for modern layout rendering)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_connect_timeout 600s;
    }
}
EOF

    log_info "Verifying syntax and hot-reloading Nginx rules configuration engine..."
    docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1
}

launch_immich() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Wiping dead or stale Immich instances..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Launching Immich system processing nodes..."
    docker compose up -d --force-recreate || exit 1
    log_succ "Immich microservices cluster running smoothly!"
}

# FIXED ORDER: Containers boot up and bind sockets completely BEFORE Nginx shifts traffic routing targets
launch_immich
inject_nginx_immich_routing
