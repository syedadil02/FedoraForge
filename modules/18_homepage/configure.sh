#!/usr/bin/env bash
# modules/17_homepage/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

generate_dynamic_config() {
    log_info "Generating dynamic Homepage configuration from templates..."

    # Render services.yaml from the .tmpl file using envsubst
    TAILSCALE_HOSTNAME="${TS_HOSTNAME}" \
    TAILSCALE_TAILNET="${TS_TAILNET}" \
    envsubst < "${SCRIPT_DIR}/config/services.yaml.tmpl" > /fastpool/homepage/config/services.yaml

    log_succ "Homepage services.yaml rendered for domain: ${FULL_DOMAIN}"
}

inject_nginx_dashboard_routing() {
    log_info "Injecting central dashboard landing configurations into Nginx..."

    cat << EOF > /fastpool/nginx/conf.d/homepage.conf
server {
    listen 80;
    listen 443 ssl;

    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:8085;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

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
    cd "${SCRIPT_DIR}/compose"

    log_info "Recycling out-of-date dashboard runtime layers..."
    docker compose down 2>/dev/null || true

    log_info "Starting Homepage UI compilation engine..."
    docker compose up -d --force-recreate || exit 1
    log_succ "Homepage Dashboard engine online!"
}

generate_dynamic_config
launch_dashboard
inject_nginx_dashboard_routing
