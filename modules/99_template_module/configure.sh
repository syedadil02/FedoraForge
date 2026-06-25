#!/usr/bin/env bash
# modules/99_template_module/configure.sh
# 
# Description: Boilerplate template for launching a new Docker Compose service
# and injecting an Nginx reverse proxy routing configuration.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib_utils.sh"

# Load Environment Variables
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${SCRIPT_DIR}/../../environment/staging.env"
fi

# 1. (Optional) Inject Nginx Proxy Configuration
inject_nginx_routing() {
    log_info "Injecting secure reverse proxy routing for custom service..."
    
    # Change port 8450 to whatever external port you want
    # Change 127.0.0.1:8080 to the internal port your container exposes
    cat << EOF > /fastpool/nginx/conf.d/custom_service.conf
server {
    listen 8450 ssl;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Websocket Support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$http_connection;
    }
}
EOF

    log_info "Hot-reloading Nginx rules..."
    docker exec homelab_nginx nginx -s reload || true
}

# 2. Launch Docker Container
launch_service() {
    log_info "Wiping stale instances of custom service..."
    cd "${SCRIPT_DIR}/compose"
    docker compose down 2>/dev/null || true

    log_info "Launching custom service..."
    # Export variables so docker-compose.yml can read them
    export TIMEZONE CONFIG_BASE_DIR STORAGE_BASE_DIR
    
    docker compose up -d --force-recreate || exit 1
    log_succ "Custom service deployed successfully!"
}

# Execute Functions
launch_service
inject_nginx_routing
