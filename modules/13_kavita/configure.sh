#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${REPO_ROOT}/environment/staging.env"
fi

log_info "Injecting Kavita reverse proxy configuration..."
cat << EOF > "${CONFIG_BASE_DIR:-/fastpool}/nginx/conf.d/kavita.conf"
server {
    listen 8447 ssl;
    server_name ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

log_info "Validating and reloading Nginx..."
docker exec homelab_nginx nginx -t && docker exec homelab_nginx nginx -s reload || exit 1

cd "$(dirname "$(readlink -f "$0")")/compose"
docker compose down 2>/dev/null || true
docker compose up -d --force-recreate
log_succ "Kavita deployment successfully routed via port 8447!"
