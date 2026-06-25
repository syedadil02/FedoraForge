#!/usr/bin/env bash
# modules/11_monitoring/configure.sh
# Launches the full monitoring stack:
#   - Node Exporter  (port 9100) — host CPU, memory, disk, network metrics
#   - cAdvisor       (port 9338) — per-container resource usage metrics
#   - Promtail       (port 9080) — log shipping to Loki
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "$(dirname "$0")/../../environment/staging.env"
fi

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Utility: launch a compose stack and verify a port is listening
launch_and_verify() {
    local name="$1"
    local compose_dir="$2"
    local port="$3"

    log_info "Starting ${name}..."
    cd "${compose_dir}"
    docker compose down 2>/dev/null || true
    docker compose up -d || exit 1

    local success=1
    for i in {1..15}; do
        if ss -tulpn | grep -q -w "${port}"; then
            success=0
            break
        fi
        sleep 1
    done

    if [[ $success -eq 0 ]]; then
        log_succ "${name} active on port ${port}."
    else
        log_warn "${name} started but port ${port} not detected within timeout. Check logs."
    fi
}

# Launch all three monitoring components
launch_and_verify "Node Exporter" "${SCRIPT_DIR}/node_exporter" "9100"
launch_and_verify "cAdvisor"      "${SCRIPT_DIR}/cadvisor"       "9338"
launch_and_verify "Prometheus"    "${SCRIPT_DIR}/prometheus"     "9090"
launch_and_verify "Promtail"      "${SCRIPT_DIR}/promtail"       "9080"

log_succ "Full monitoring stack online (Node Exporter :9100 | cAdvisor :9338 | Prometheus :9090 | Promtail :9080)."
