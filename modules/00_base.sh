#!/bin/env/env bash

# modules/00_base.sh - Target Baseline & Dependency Alignment

set -euo pipefail

# Ensure library constraints are attached locally if run directly
if [[ "$(type -t log_info)" != "function" ]]; then
    source "$(dirname "$0")/../lib_utils.sh"
fi

update_and_align_dependencies() {
    log_info "Initiating system structural upgrade for Fedora 44..."

    # 1. Speed up DNF5 configuration optimization constraints
    local dnf_conf="/etc/dnf/dnf.conf"
    if ! grep -q "max_parallel_downloads" "$dnf_conf"; then
        log_info "Tuning DNF configuration topology..."
        cp "$dnf_conf" "${dnf_conf}.bak"
        BACKUP_FILES+=("${dnf_conf}.bak")
        echo "max_parallel_downloads=10" >> "$dnf_conf"
        echo "fastestmirror=True" >> "$dnf_conf"
    fi

    # 2. Complete OS Alignment Core Updates
    log_info "Synchronizing Fedora package metadata and upgrading runtimes..."
    dnf5 upgrade -y || return 1

    # 3. Consolidate Compilation and Runtime System Dependencies
    # Gathering tools required globally across your storage, routing, and detection stacks
    local core_deps=(
        "curl" "wget" "git" "tar" "sed" "gawk" "util-linux"
        "kernel-devel" "kernel-headers" "dkms" "elfutils-libelf-devel" # Crucial for bare-metal ZFS modules
        "iptables-nft" "systemd-resolved"                              # Core networking foundations
        "gcc" "gcc-c++" "make" "cmake" "libpcap-devel" "luajit-devel"  # Crucial dependencies for Snort3
    )

    log_info "Installing compiled hardware toolchains and baseline applications..."
    dnf5 install -y "${core_deps[@]}" || return 1

    log_succ "Fedora 44 baseline parameters successfully completed."
}

# Execute encapsulation process inside current transaction context
update_and_align_dependencies
