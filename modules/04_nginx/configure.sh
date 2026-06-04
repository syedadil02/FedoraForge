#!/usr/bin/env bash
# modules/04_nginx/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-staging}"
TS_TAILNET="${TAILSCALE_TAILNET:-tailfb0549.ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

fetch_tailscale_certificates() {
    log_info "Provisioning Let's Encrypt TLS certificates from Tailscale MagicDNS..."

    # Ensure Tailscale daemon is accessible before requesting keys
    if ! tailscale status &>/dev/null; then
        log_error "Tailscale daemon is unresponsive. Cannot fetch mesh certificates."
        exit 1
    fi

    # Fetch fresh keys directly into our ZFS certificates mount point
    tailscale cert --cert-file /fastpool/nginx/certs/ts.crt --key-file /fastpool/nginx/certs/ts.key "${FULL_DOMAIN}" || exit 1

    # Lock down file system keys so they aren't globally readable
    chmod 600 /fastpool/nginx/certs/ts.key
    chmod 644 /fastpool/nginx/certs/ts.crt
}

generate_ssl_routing_block() {
    log_info "Generating active Nginx routing matrix for ${FULL_DOMAIN}..."

    # Write out a default secure SSL catch-all block for your tailnet domain
    cat << EOF > /fastpool/nginx/conf.d/default_ssl.conf
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name ${FULL_DOMAIN};

    ssl_certificate /etc/nginx/certs/ts.crt;
    ssl_certificate_key /etc/nginx/certs/ts.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        root /usr/share/nginx/html;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

launch_proxy_runtime() {
    log_info "Starting Nginx reverse proxy stack via Docker Compose..."

    local script_dir
    script_dir=$(dirname "$(readlink -f "$0")")

    # Run the Compose up sequence
    docker compose -f "${script_dir}/compose/docker-compose.yml" up -d || exit 1

    # Health Verification Loop
    log_info "Validating reverse proxy interface stability..."
    sleep 3

    if curl -k -s -I "https://${FULL_DOMAIN}" | grep -q "HTTP/"; then
        log_succ "Nginx reverse proxy is actively answering TLS requests securely over your Tailnet!"
    else
        log_error "Nginx initialized but failed TLS resolution loop checks."
        exit 1
    fi
}

fetch_tailscale_certificates
generate_ssl_routing_block
launch_proxy_runtime
