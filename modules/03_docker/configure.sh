#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

log_info "Configuring Docker runtime engine data root to use fastpool..."
mkdir -p /etc/docker
cat << EOF > /etc/docker/daemon.json
{
  "data-root": "${CONFIG_BASE_DIR:-/fastpool}/docker"
}
EOF

log_info "Re-routing Containerd image snapshotter storage to fastpool..."
systemctl stop docker containerd 2>/dev/null || true

# Remove stale symlink from previous fix attempt
if [ -L /var/lib/containerd ]; then
    rm -f /var/lib/containerd
fi

# Generate containerd config that points root to fastpool
mkdir -p /etc/containerd "${CONFIG_BASE_DIR:-/fastpool}/containerd"
containerd config default > /etc/containerd/config.toml 2>/dev/null || true
# Set root directory in the config — this is the ONLY reliable way
sed -i "s|^root = .*|root = \"${CONFIG_BASE_DIR:-/fastpool}/containerd\"|" /etc/containerd/config.toml
# If root line doesn't exist, prepend it
if ! grep -q "^root = " /etc/containerd/config.toml 2>/dev/null; then
    echo "root = \"${CONFIG_BASE_DIR:-/fastpool}/containerd\"" > /tmp/containerd_header.toml
    cat /etc/containerd/config.toml >> /tmp/containerd_header.toml
    mv /tmp/containerd_header.toml /etc/containerd/config.toml
fi

# Migrate any existing containerd data if present
if [ -d /var/lib/containerd ] && [ ! -L /var/lib/containerd ]; then
    log_info "Migrating existing containerd data to ZFS..."
    cp -a /var/lib/containerd/. "${CONFIG_BASE_DIR:-/fastpool}/containerd/" 2>/dev/null || true
    rm -rf /var/lib/containerd
fi

log_info "Initializing systemd operational constraints for Docker runtime engine..."
systemctl daemon-reload
systemctl enable containerd docker || exit 1
systemctl restart containerd docker || exit 1

# Validation verification step
if systemctl is-active --quiet docker; then
    log_succ "Docker daemon is active and operating cleanly."
    log_info "Containerd root: $(grep '^root = ' /etc/containerd/config.toml 2>/dev/null || echo 'default')"
else
    log_error "Docker failed validation initialization checks."
    exit 1
fi
