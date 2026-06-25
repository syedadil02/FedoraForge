#!/usr/bin/env bash
# modules/11_monitoring/install.sh
# Provisions storage and config paths for the full monitoring stack:
#   - Node Exporter (host metrics)
#   - cAdvisor (container metrics)
#   - Promtail (log aggregation)
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

log_info "Provisioning storage paths for monitoring stack..."
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/monitoring/data"
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/monitoring/config"
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/monitoring/promtail"
mkdir -p "${CONFIG_BASE_DIR:-/fastpool}/monitoring/prometheus/data"

# Stage Promtail config into the persistent volume
log_info "Staging Promtail and Prometheus configurations..."
cp "${SCRIPT_DIR}/promtail/promtail-config.yaml" \
   "${CONFIG_BASE_DIR:-/fastpool}/monitoring/promtail/promtail-config.yaml"

cp "${SCRIPT_DIR}/prometheus/prometheus.yml" \
   "${CONFIG_BASE_DIR:-/fastpool}/monitoring/prometheus/prometheus.yml"

if command -v chcon &>/dev/null; then
    chcon -Rt container_file_t "${CONFIG_BASE_DIR:-/fastpool}/monitoring" || true
fi

log_succ "Monitoring storage and configs prepared (Node Exporter + cAdvisor + Promtail)."
