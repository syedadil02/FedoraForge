#!/usr/bin/env bash
# modules/04_nginx/configure.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

TS_HOSTNAME="${TAILSCALE_HOSTNAME:-homelab-server}"
TS_TAILNET="${TAILSCALE_TAILNET:-ts.net}"
FULL_DOMAIN="${TS_HOSTNAME}.${TS_TAILNET}"

log_info "Configuring host firewall for HTTP/HTTPS traffic..."
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload
    log_succ "Firewall rules for port 80/443 successfully applied."
else
    log_warn "firewalld not active or missing; assuming ports are open."
fi

fetch_tailscale_certificates() {
    log_info "Provisioning TLS certificates from Tailscale for: ${FULL_DOMAIN}"

    # Ensure Tailscale daemon is accessible before requesting keys
    if ! tailscale status &>/dev/null; then
        log_error "Tailscale daemon is unresponsive. Cannot fetch mesh certificates."
        exit 1
    fi

    local max_attempts=10
    local attempt=1
    local wait_sec=5

    log_info "Requesting HTTPS certificate from Tailscale ACME provider..."
    while [ ${attempt} -le ${max_attempts} ]; do
        if tailscale cert --cert-file /fastpool/nginx/certs/ts.crt --key-file /fastpool/nginx/certs/ts.key "${FULL_DOMAIN}"; then
            log_succ "TLS certificates provisioned on attempt ${attempt}."
            break
        else
            log_warn "Certificate challenge pending... Retrying in ${wait_sec}s (Attempt ${attempt}/${max_attempts})"
            sleep ${wait_sec}
            attempt=$((attempt + 1))
        fi
    done

    # Hard barrier if all attempts fail
    if [ ${attempt} -gt ${max_attempts} ]; then
        log_error "Failed to provision Tailscale certificates after ${max_attempts} attempts."
        log_error "Ensure HTTPS Certificates are ENABLED in your Tailscale Admin Console:"
        log_error "  → https://login.tailscale.com/admin/dns (toggle 'HTTPS Certificates')"
        log_error "Also ensure MagicDNS is enabled."
        exit 1
    fi

    # Lock down file system keys so they aren't globally readable
    chmod 600 /fastpool/nginx/certs/ts.key
    chmod 644 /fastpool/nginx/certs/ts.crt
}

generate_ssl_routing_block() {
    log_info "Generating active Nginx routing matrix fallback..."

    # Write out a generic catch-all fallback block
    cat << EOF > /fastpool/nginx/conf.d/default_ssl.conf
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _; # Changed from ${FULL_DOMAIN} to an anonymous catch-all wildcard

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

    log_info "Validating reverse proxy interface stability..."

    local max_checks=6
    local check=1
    local wait_interval=2
    local validated=0

    while [ ${check} -le ${max_checks} ]; do
        # --- FIXED FOR SINGLE-RUN SUCCESS ---
        # Forces curl to map your domain to localhost (127.0.0.1) on ports 80 and 443
        # instantly bypassing cold host-routing table issues.
        if curl -k -s --max-time 2 \
            --resolve "${FULL_DOMAIN}:443:127.0.0.1" \
            -I "https://${FULL_DOMAIN}" | grep -q "HTTP/"; then

            log_succ "Nginx reverse proxy is actively answering TLS requests securely over your Tailnet!"
            validated=1
            break
        else
            log_warn "TLS interface pending stabilization... Retrying in ${wait_interval}s (Check ${check}/${max_checks})"
            sleep ${wait_interval}
            check=$((check + 1))
        fi
    done

    if [ ${validated} -eq 0 ]; then
        log_error "Nginx initialized but failed TLS resolution loop checks after complete timeout."
        exit 1
    fi
}
fetch_tailscale_certificates
generate_ssl_routing_block
launch_proxy_runtime
