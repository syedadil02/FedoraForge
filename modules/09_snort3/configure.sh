#!/usr/bin/env bash
# modules/09_snort3/configure.sh
#
# Deploys and validates the Snort3 configuration:
#   1. Creates runtime directories
#   2. Downloads community rules
#   3. Deploys snort.lua from template
#   4. Validates config with `snort -T`
#   5. Deploys and starts the systemd service
#
# Run after install.sh. Safe to re-run — rules are always refreshed,
# config is redeployed from template, service restarted if config changed.
#
# Rollback: if any step fails, lib_utils rollback_engine restores any file
# pushed into BACKUP_FILES[] and the ERR trap fires automatically.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib_utils.sh"
source "${SCRIPT_DIR}/../../environment/staging.env"

# ─── Defaults ─────────────────────────────────────────────────────────────────
SNORT_CONF_DIR="${SNORT_CONF_DIR:-/usr/local/etc/snort}"
SNORT_RULES_DIR="${SNORT_RULES_DIR:-/usr/local/etc/snort/rules}"
SNORT_LOG_DIR="${SNORT_LOG_DIR:-/var/log/snort}"
SNORT_ALERT_LOG="${SNORT_ALERT_LOG:-${SNORT_LOG_DIR}/alert_json.txt}"
SNORT_RULES_URL="${SNORT_RULES_URL:-https://www.snort.org/downloads/community/snort3-community-rules.tar.gz}"

# Export so envsubst can expand these inside templates
export SNORT_INTERFACE SNORT_HOME_NET \
       SNORT_CONF_DIR SNORT_RULES_DIR \
       SNORT_LOG_DIR SNORT_ALERT_LOG

TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# ─── 1. Runtime directories ───────────────────────────────────────────────────
create_dirs() {
    log_info "Creating Snort3 runtime directories..."
    local dirs=("${SNORT_CONF_DIR}" "${SNORT_RULES_DIR}" "${SNORT_LOG_DIR}")
    for d in "${dirs[@]}"; do
        if [[ ! -d "${d}" ]]; then
            mkdir -p "${d}"
            chmod 0755 "${d}"
            log_info "  Created: ${d}"
        else
            log_info "  Already exists: ${d}"
        fi
    done
}

# ─── 2. Community rules ───────────────────────────────────────────────────────
# Always re-downloads to keep rules current.
# The update script in /usr/local/bin can also be run manually.
download_rules() {
    log_info "Downloading Snort3 community rules..."
    local tmp_archive
    tmp_archive=$(mktemp /tmp/homelab_tx_snort3_rules_XXXXXX.tar.gz)

    curl -fSL "${SNORT_RULES_URL}" -o "${tmp_archive}"

    log_info "Cleaning stale rule artifacts from ${SNORT_RULES_DIR}..."
    rm -f "${SNORT_RULES_DIR}/snort3-community.rules"

    log_info "Extracting rules to ${SNORT_RULES_DIR}..."
    tar -xzf "${tmp_archive}" --strip-components=1 -C "${SNORT_RULES_DIR}"
    rm -f "${tmp_archive}"
    log_succ "Community rules installed."
}

deploy_rules_update_script() {
    local script=/usr/local/bin/snort-update-rules
    log_info "Deploying rules update script to ${script}..."
    cat > "${script}" <<EOF
#!/usr/bin/env bash
# Update Snort3 community rules.
# Run manually or via a systemd timer (Week 9+ hardening task).
set -euo pipefail
TMP=\$(mktemp -d)
curl -fSL "${SNORT_RULES_URL}" -o "\${TMP}/rules.tar.gz"
tar -xzf "\${TMP}/rules.tar.gz" --strip-components=1 -C "${SNORT_RULES_DIR}"
rm -rf "\${TMP}"
systemctl restart snort3
echo "Rules updated and Snort3 restarted."
EOF
    chmod 0750 "${script}"
    log_succ "Update script deployed."
}

# ─── 3. Deploy snort.lua ──────────────────────────────────────────────────────
deploy_config() {
    log_info "Deploying snort.lua from template..."
    local dest="${SNORT_CONF_DIR}/snort.lua"
    local tmpl="${TEMPLATES_DIR}/snort.lua.tmpl"

    [[ -f "${tmpl}" ]] || { log_error "Template not found: ${tmpl}"; exit 1; }

    # Back up existing config and register it with the rollback engine.
    # If anything fails after this point, rollback_engine restores it via the
    # ERR trap bound in lib_utils.
    if [[ -f "${dest}" ]]; then
        cp "${dest}" "${dest}.bak"
        BACKUP_FILES+=("${dest}.bak")
        log_info "Existing snort.lua backed up → ${dest}.bak"
    fi

    envsubst < "${tmpl}" > "${dest}"
    chmod 0644 "${dest}"
    log_succ "snort.lua deployed to ${dest}"
}

# ─── 4. Validate config ───────────────────────────────────────────────────────
# Run `snort -T` (test mode) before touching the live service.
# On failure: log_error triggers the ERR trap → rollback_engine restores backup.
validate_config() {
    log_info "Validating Snort3 configuration..."
    local output
    if ! output=$(
        /usr/local/bin/snort \
            -c "${SNORT_CONF_DIR}/snort.lua" \
            --daq-dir /usr/local/lib/daq \
            -T 2>&1
    ); then
        log_error "Snort3 config validation failed. Output:"
        echo "${output}" >&2
        exit 1   # ERR trap fires → rollback_engine restores snort.lua from BACKUP_FILES
    fi

    # Snort prints its validation summary in the last 3 lines
    log_info "Validation passed:"
    echo "${output}" | tail -3 | while IFS= read -r line; do
        log_info "  ${line}"
    done
}

# ─── 5. Systemd service ───────────────────────────────────────────────────────
deploy_service() {
    log_info "Deploying Snort3 systemd service..."
    local dest="/etc/systemd/system/snort3.service"
    local tmpl="${TEMPLATES_DIR}/snort3.service.tmpl"

    [[ -f "${tmpl}" ]] || { log_error "Template not found: ${tmpl}"; exit 1; }
    envsubst < "${tmpl}" > "${dest}"
    chmod 0644 "${dest}"
    log_succ "snort3.service deployed."
}

start_service() {
    log_info "Starting Snort3 service..."
    systemctl daemon-reload
    systemctl enable snort3
    systemctl restart snort3

    # Poll until active — mirrors Ansible until/retries/delay pattern
    local retries=5
    local delay=3
    local i=0
    while (( i < retries )); do
        local state
        state=$(systemctl is-active snort3 2>/dev/null || true)
        if [[ "${state}" == "active" ]]; then
            log_succ "Snort3 service is active."
            return 0
        fi
        log_warn "Waiting for Snort3 (attempt $((i+1))/${retries})..."
        sleep "${delay}"
        (( i++ ))
    done

    log_warn "Snort3 failed to start. Last 20 journal lines:"
    journalctl -u snort3 -n 20 --no-pager >&2
    exit 1
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    start_transaction
    log_info "=== Snort3 Configure ==="

    create_dirs
    download_rules
    deploy_rules_update_script
    deploy_config
    validate_config
    deploy_service
    start_service

    commit_transaction
    log_succ "=== Snort3 Configure Complete ==="
    log_info "Alert log: ${SNORT_ALERT_LOG}"
}

main "$@"
