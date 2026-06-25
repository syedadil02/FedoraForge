#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
REPO_ROOT="${SCRIPT_DIR}/../.."

source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

log_info "Injecting SearXNG proxy rules to Nginx stack..."
cat << EOF > "${CONFIG_BASE_DIR:-/fastpool}/nginx/conf.d/searxng.conf"
server {
    listen 8448 ssl;
    server_name ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:8888;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

log_info "Validating and reloading Nginx..."
docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1

log_info "Spinning up SearXNG container engines..."
docker compose -f "${SCRIPT_DIR}/compose/docker-compose.yml" down 2>/dev/null || true
docker compose -f "${SCRIPT_DIR}/compose/docker-compose.yml" up -d --force-recreate

log_succ "SearXNG privacy matrix online via port 8448!"
