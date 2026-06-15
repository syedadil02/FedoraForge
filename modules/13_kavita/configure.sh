#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(dirname "$(readlink -f "$0")")/../.."
source "${REPO_ROOT}/lib_utils.sh"
source "${REPO_ROOT}/environment/staging.env"

log_info "Injecting Kavita reverse proxy configuration..."
cat << EOF > ${CONFIG_BASE_DIR}/nginx/conf.d/kavita.conf
server {
    listen 8447 ssl;
    server_name ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://172.17.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

docker exec homelab_nginx nginx -s reload || true

cd "$(dirname "$0")/compose"
docker compose down 2>/dev/null || true
docker compose up -d --force-recreate
log_succ "Kavita deployment successfully routed via port 8447!"
