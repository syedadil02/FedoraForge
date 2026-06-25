#!/usr/bin/env bash
# modules/08_immich/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

inject_nginx_immich_routing() {
    log_info "Injecting Immich secure reverse proxy routes..."

    cat << EOF > /fastpool/nginx/conf.d/immich.conf
server {
    listen 8445 ssl;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    client_max_body_size 50000M;

    location / {
        proxy_pass http://127.0.0.1:2283;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        # Only upgrade connection if the client requested it
        proxy_set_header Connection \$http_connection;

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

    log_info "Generating Immich environment config from template..."
    # Use envsubst to render the .env.tmpl into the compose .env file
    # DB password re-uses GITEA_DB_PASSWORD to reduce secret sprawl
    STORAGE_BASE_DIR="${STORAGE_BASE_DIR:-/datapool}" \
    TAILSCALE_HOSTNAME="${TS_HOSTNAME}" \
    TAILSCALE_TAILNET="${TS_TAILNET}" \
    GITEA_DB_PASSWORD="${GITEA_DB_PASSWORD:-$(openssl rand -hex 12)}" \
    envsubst < "${script_dir}/compose/.env.tmpl" > "${script_dir}/compose/.env"

    log_info "Wiping dead or stale Immich instances..."
    cd "${script_dir}/compose"
    docker compose down 2>/dev/null || true

    # Dynamic GPU Passthrough for Bare-Metal
    rm -f docker-compose.override.yml
    if detect_physical_gpu; then
        log_succ "Physical GPU detected! Injecting hardware passthrough into Immich..."
        cat << 'EOF_OVERRIDE' > docker-compose.override.yml
services:
  immich-server:
    devices:
      - /dev/dri:/dev/dri
  immich-machine-learning:
    devices:
      - /dev/dri:/dev/dri
EOF_OVERRIDE
    else
        log_warn "No physical GPU detected (or running in VM). Bypassing hardware passthrough."
    fi

    log_info "Launching Immich system processing nodes..."
    docker compose up -d --force-recreate || exit 1
    log_succ "Immich microservices cluster running smoothly!"
}

# Containers boot up BEFORE Nginx shifts traffic routing targets
launch_immich
inject_nginx_immich_routing
