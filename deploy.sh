#!/usr/bin/env bash
# deploy.sh - Master System Orchestrator

set -euo pipefail

# Load helper utilities before anything else (provides log_info/log_error etc.)
source "./lib_utils.sh"

# Lock down execution logic context entirely to root parameters
if [[ $EUID -ne 0 ]]; then
   log_error "This orchestrator engine requires root permission structures. Re-execute with sudo."
   exit 1
fi

# 2. Enforce Environment Input Gate or run interactive wizard
ENV_FILE=""

run_wizard() {
    log_info "=================================================="
    log_info "   Welcome to FedoraForge Auto-Deployment Wizard!     "
    log_info "=================================================="
    
    local target_env="environment/active.env"
    mkdir -p "$(dirname "$target_env")"
    
    # Check if active.env already exists to resume or overwrite
    if [[ -f "$target_env" ]]; then
        read -rp "[?] Detected existing environment config. Overwrite and re-detect? (y/N): " overwrite_config
        if [[ ! "$overwrite_config" =~ ^[Yy]$ ]]; then
            ENV_FILE="$target_env"
            return
        fi
    fi
    
    log_info "Scanning for available block devices..."
    local all_disks
    all_disks=$(lsblk -dno NAME | sort -u)
    local os_disks
    os_disks=$(lsblk -no PKNAME,MOUNTPOINTS | awk '$2 != "" {print $1}' | sort -u)
    
    local nvme_candidates=()
    local hdd_candidates=()
    
    for disk in $all_disks; do
        if [[ " ${os_disks} " =~ " ${disk} " ]]; then
            continue
        fi
        
        if [ -f "/sys/class/block/${disk}/queue/rotational" ]; then
            local rota
            rota=$(cat "/sys/class/block/${disk}/queue/rotational")
            if [ "$rota" -eq 0 ]; then
                nvme_candidates+=("/dev/${disk}")
            else
                hdd_candidates+=("/dev/${disk}")
            fi
        fi
    done
    
    local selected_nvme=""
    local selected_hdd=""
    
    # NVMe/SSD selection
    if [ ${#nvme_candidates[@]} -gt 0 ]; then
        log_info "Detected available NVMe/SSD disks:"
        for i in "${!nvme_candidates[@]}"; do
            echo "  [$i] ${nvme_candidates[$i]}"
        done
        read -rp "[?] Select SSD for ZFS fastpool [Default: 0 - ${nvme_candidates[0]}]: " nvme_idx
        nvme_idx="${nvme_idx:-0}"
        selected_nvme="${nvme_candidates[$nvme_idx]}"
    fi
    
    # HDD selection
    if [ ${#hdd_candidates[@]} -gt 0 ]; then
        log_info "Detected available HDD disks:"
        for i in "${!hdd_candidates[@]}"; do
            echo "  [$i] ${hdd_candidates[$i]}"
        done
        read -rp "[?] Select HDD for ZFS datapool [Default: 0 - ${hdd_candidates[0]}]: " hdd_idx
        hdd_idx="${hdd_idx:-0}"
        selected_hdd="${hdd_candidates[$hdd_idx]}"
    fi
    
    # Check fallback if none detected (VM/staging loopback files)
    if [[ -z "$selected_nvme" || -z "$selected_hdd" ]]; then
        log_warn "Could not auto-detect separate NVMe/SSD and HDD devices."
        read -rp "[?] Are you deploying in a staging VM and want to create loop-back disk images? (Y/n): " use_loop
        use_loop="${use_loop:-y}"
        if [[ "$use_loop" =~ ^[Yy]$ ]]; then
            local disk_dir="/var/tmp/homelab-zfs-disks"
            mkdir -p "$disk_dir"
            log_info "Creating ZFS backing storage image files in $disk_dir..."
            truncate -s 10G "$disk_dir/nvme.img"
            truncate -s 10G "$disk_dir/hdd.img"
            selected_nvme="$disk_dir/nvme.img"
            selected_hdd="$disk_dir/hdd.img"
        else
            read -rp "[?] Enter path to NVMe/SSD device: " selected_nvme
            read -rp "[?] Enter path to HDD device: " selected_hdd
        fi
    fi
    
    log_info "Selected NVMe/SSD: $selected_nvme"
    log_info "Selected HDD: $selected_hdd"
    
    # Tailscale Auth Key
    read -rp "[?] Enter your Tailscale Auth Key (leave empty to authenticate manually): " ts_auth_key
    
    # Hostname & Timezone
    read -rp "[?] Enter Hostname [Default: fedoraforge-server]: " host_name
    host_name="${host_name:-fedoraforge-server}"
    
    local tz="UTC"
    if command -v timedatectl &>/dev/null; then
        tz=$(timedatectl show --property=Timezone --value || echo "UTC")
    fi
    read -rp "[?] Enter Timezone [Default: $tz]: " user_tz
    user_tz="${user_tz:-$tz}"
    
    # Detect primary network interface
    local primary_if
    primary_if=$(ip route show default | awk '/default/ { print $5; exit }' || echo "eth0")
    
    # Detect subnet for Snort
    local ip_cidr
    ip_cidr=$(ip -o -f inet addr show dev "${primary_if}" | awk '{print $4; exit}' || echo "192.168.1.1/24")
    local snort_net="192.168.1.0/24"
    if [[ "$ip_cidr" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/([0-9]+)$ ]]; then
        snort_net="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}.0/${BASH_REMATCH[5]}"
    fi
    
    # Samba config
    read -rp "[?] Enter Samba username [Default: administrator]: " smb_user
    smb_user="${smb_user:-administrator}"
    read -rsp "[?] Enter Samba password [Default: admin123]: " smb_pass
    echo ""
    smb_pass="${smb_pass:-admin123}"
    
    # Passwords
    read -s -rp "[?] Create a password for the Duplicati Backup Dashboard: " duplicati_pass
    echo ""
    
    # Generate database password & searxng key
    local db_pass
    db_pass=$(openssl rand -hex 12)
    local sx_key
    sx_key=$(openssl rand -hex 16)
    
    # Write environment profile
    log_info "Writing configurations to $target_env..."
    cat << EOF > "$target_env"
# Auto-generated by FedoraForge deployment wizard
# Tailnet suffix is auto-detected by modules/02_tailscale/configure.sh after auth
export HOSTNAME="${host_name}"
export TIMEZONE="${user_tz}"
export SYSTEM_UID="$(id -u)"
export SYSTEM_GID="$(id -g)"
export FASTPOOL_DISK="${selected_nvme}"
export DATAPOOL_DISK="${selected_hdd}"
export TAILSCALE_HOSTNAME="${host_name}"
export TAILSCALE_TAILNET="pending-detection"
export TAILSCALE_AUTH_KEY="${ts_auth_key}"
export GITEA_DB_PASSWORD="${db_pass}"
export IMMICH_DB_PASSWORD="${db_pass}"
export DUPLICATI_PASSWORD="${duplicati_pass:-admin}"
export CONFIG_BASE_DIR="/fastpool"
export STORAGE_BASE_DIR="/datapool"
export PRIMARY_INTERFACE="${primary_if}"
export SNORT_INTERFACE="${primary_if}"
export SNORT_HOME_NET="${snort_net}"
export SAMBA_USER="${smb_user}"
export SAMBA_PASSWORD="${smb_pass}"
export SEARXNG_SECRET_KEY="${sx_key}"
export WOLF_WEB_PORT="8451"
export WOLF_INTERNAL_PORT="47989"
export WOLF_RDP_PORT="3389"
export WOLF_AUDIO_ENABLED="1"
export WOLF_HEVC_ENCODING="1"
export WOLF_CPU_LIMIT="4"
export WOLF_MEMORY_LIMIT="8G"
export WOLF_CPU_RESERVE="2"
export WOLF_MEMORY_RESERVE="4G"
EOF
    
    ENV_FILE="$target_env"
    log_succ "Environment setup complete."
}

if [[ $# -eq 0 ]]; then
    run_wizard
else
    ENV_FILE="$1"
fi

if [[ -f "$ENV_FILE" ]]; then
    log_info "Loading targeted environment definitions: ${ENV_FILE}"
    source "$ENV_FILE"
else
    log_error "Specified environment file not found: ${ENV_FILE}"
    exit 1
fi

# Export context paths and indicators for all subprocesses
export HOMELAB_ENV_LOADED=true
export ENV_FILE="$(readlink -f "$ENV_FILE")"


main() {
    log_info "Launching FedoraForge bare-metal orchestration lifecycle..."
    start_transaction

    # State Tracking: Ensure state file exists
    touch .deploy_state

    # Wrapper to automatically skip completed phases
    run_phase() {
        local phase_id="$1"
        local phase_name="$2"
        local phase_cmd="$3"

        if grep -q "^${phase_id}$" .deploy_state 2>/dev/null; then
            log_info "========== Phase ${phase_id}: ${phase_name} [SKIPPED - Already Completed] =========="
            return 0
        fi

        log_info "========== Phase ${phase_id}: ${phase_name} =========="
        if eval "${phase_cmd}"; then
            echo "${phase_id}" >> .deploy_state
            return 0
        else
            log_error "Phase ${phase_id} failed."
            return 1
        fi
    }

    run_phase "0" "System Core Upgrades" "source ./modules/00_base.sh"
    run_phase "1" "ZFS Platform Deployment" "./modules/01_zfs/install.sh && ./modules/01_zfs/configure.sh"
    run_phase "2" "Tailscale Node Ingestion" "./modules/02_tailscale/install.sh && ./modules/02_tailscale/configure.sh"

    # CRITICAL: Re-source the env file to pick up the tailnet domain
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi

    # If Phase 2 was skipped but the wizard reset the env file, we must re-detect the tailnet here.
    if [[ "${TAILSCALE_TAILNET}" == "pending-detection" ]] && command -v tailscale &>/dev/null; then
        log_info "Auto-detecting Tailnet domain directly from active Tailscale mesh..."
        TS_FQDN=$(tailscale status --json 2>/dev/null | python3 -c \
            "import json,sys; s=json.load(sys.stdin); print(s.get('Self', {}).get('DNSName', '').rstrip('.'))" 2>/dev/null || true)
        if [[ -n "$TS_FQDN" ]]; then
            export TAILSCALE_TAILNET="${TS_FQDN#*.}"
            export TAILSCALE_HOSTNAME="${TS_FQDN%%.*}"
            sed -i "s|^export TAILSCALE_TAILNET=.*|export TAILSCALE_TAILNET=\"${TAILSCALE_TAILNET}\"|" "${ENV_FILE}" 2>/dev/null || true
            sed -i "s|^export TAILSCALE_HOSTNAME=.*|export TAILSCALE_HOSTNAME=\"${TAILSCALE_HOSTNAME}\"|" "${ENV_FILE}" 2>/dev/null || true
        fi
    fi

    log_info "Tailnet domain resolved: ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET}"

    # Sanity check — abort early if tailnet wasn't detected
    if [[ "${TAILSCALE_TAILNET}" == "pending-detection" ]]; then
        log_error "Tailnet domain was not auto-detected after Tailscale auth!"
        log_error "Ensure MagicDNS is enabled in your Tailscale admin console."
        log_error "You can also manually set TAILSCALE_TAILNET in ${ENV_FILE} and re-run."
        exit 1
    fi

    run_phase "3" "Docker Engine Infrastructure" "./modules/03_docker/install.sh && ./modules/03_docker/configure.sh"
    run_phase "4" "Nginx Proxy Matrix" "./modules/04_nginx/install.sh && ./modules/04_nginx/configure.sh"
    run_phase "5" "Gitea Local Git Service" "./modules/05_gitea/install.sh && ./modules/05_gitea/configure.sh"
    run_phase "6" "AdGuard Home DNS System" "./modules/06_adguard/install.sh && ./modules/06_adguard/configure.sh"

    run_phase "7" "Vaultwarden Secrets Manager" "./modules/07_vaultwarden/install.sh && ./modules/07_vaultwarden/configure.sh"
    run_phase "8" "Immich Photos Cluster" "./modules/08_immich/install.sh && ./modules/08_immich/configure.sh"
    run_phase "9" "Snort3 IDS/IPS Platform" "./modules/09_snort3/install.sh && ./modules/09_snort3/configure.sh"
    run_phase "10" "Syncthing Replication Engine" "./modules/10_syncthing/install.sh && ./modules/10_syncthing/configure.sh"
    run_phase "11" "Monitoring Stack (Node Exporter + cAdvisor + Promtail)" "./modules/11_monitoring/install.sh && ./modules/11_monitoring/configure.sh"
    run_phase "12" "Samba File Sharing Fabric" "./modules/12_samba/install.sh && ./modules/12_samba/configure.sh"
    run_phase "13" "Kavita eBook Server Cluster" "./modules/13_kavita/install.sh && ./modules/13_kavita/configure.sh"
    run_phase "14" "SearXNG Search Core" "./modules/14_searxng/install.sh && ./modules/14_searxng/configure.sh"
    run_phase "15" "FreshRSS Aggregator" "./modules/15_freshrss/install.sh"
    run_phase "16" "Wolf Cloud Gaming" "./modules/16_wolf/install.sh && ./modules/16_wolf/configure.sh"
    run_phase "17" "Disaster Recovery Engine" "./modules/17_disaster_recovery/install.sh && ./modules/17_disaster_recovery/configure.sh"
    run_phase "18" "Homepage Dashboard" "./modules/18_homepage/install.sh && ./modules/18_homepage/configure.sh"

    commit_transaction
    log_succ "Orchestrator finished processing all ${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET} components without errors."
    log_info "Dashboard: https://${TAILSCALE_HOSTNAME}.${TAILSCALE_TAILNET}"
}

main
