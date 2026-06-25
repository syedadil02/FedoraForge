#!/usr/bin/env bash
# modules/10_syncthing/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_syncthing_routing() {
    log_info "Injecting Syncthing secure UI proxy route mapping..."

    cat << EOF > /fastpool/nginx/conf.d/syncthing.conf
server {
    listen 8446 ssl;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    client_max_body_size 100M;

    location / {
        proxy_pass http://127.0.0.1:8384;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }
}
EOF

    log_info "Validating configuration updates and recycling Nginx hot-engine..."
    docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1
}

launch_syncthing() {
    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    log_info "Wiping dead or out-of-spec Syncthing configurations..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    log_info "Booting Syncthing data replication container..."
    docker compose up -d --force-recreate || exit 1
    log_succ "Syncthing sync engine active!"
}

# Execution Chain Order
launch_syncthing
inject_nginx_syncthing_routing
