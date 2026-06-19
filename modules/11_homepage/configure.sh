#!/usr/bin/env bash
# modules/11_homepage/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging-2}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_dashboard_routing() {
    log_info "Injecting central dashboard landing configurations into Nginx..."

    cat << EOF > /fastpool/nginx/conf.d/homepage.conf
server {
    listen 80; # Dropped default_server here to respect internal nginx.conf targets
    listen 443 ssl; # Dropped default_server here to respect internal nginx.conf targets

    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://172.17.0.1:8085;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Web socket upgrade parameters for live terminal/resource streaming
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

    log_info "Validating proxy syntax and reloading server block..."
    docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1
}

launch_dashboard() {
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    cd "${SCRIPT_DIR}/compose"

    log_info "Recycling out-of-date dashboard runtime layers..."
    docker compose down 2>/dev/null || true

    log_info "Starting Homepage UI compilation engine..."
    docker compose up -d --force-recreate || exit 1
    log_succ "Homepage Dashboard engine online!"
}

launch_dashboard
inject_nginx_dashboard_routing
