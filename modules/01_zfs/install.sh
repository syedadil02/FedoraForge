#!/usr/bin/env bash
# modules/01_zfs/install.sh
set -euo pipefail

# Pull down global error logging and validation engines
source "$(dirname "$0")/../../lib_utils.sh"

if modinfo zfs &>/dev/null; then
    log_info "ZFS module definition already available in kernel tree. Skipping installation."
    exit 0
fi

log_info "Fetching system distribution parameters..."
DIST_TAG=$(rpm --eval "%{dist}")

log_info "Deploying OpenZFS release repository for Fedora 44..."
# Installs the official OpenZFS tracking configuration
dnf5 install -y "https://zfsonlinux.org/fedora/zfs-release-3-1${DIST_TAG}.noarch.rpm" || exit 1

log_info "Configuring DNF5 repository targets for ZFS..."
# DNF5 uses 'setopt' to toggle repo enabled state (writes to 99-config_manager.repo)
dnf5 config-manager setopt zfs.enabled=0 || exit 1
dnf5 config-manager setopt zfs-legacy.enabled=1 || exit 1

log_info "Aligning current kernel tracking with compilation dependencies..."
# kernel-devel MUST match running kernel for DKMS module builds
dnf5 install -y "kernel-devel-$(uname -r)" dkms || exit 1
# kernel-headers is best-effort — not always available for the exact running kernel
dnf5 install -y kernel-headers --skip-unavailable || true

log_info "Triggering OpenZFS dkms source compilation..."
dnf5 install -y zfs || exit 1

log_succ "ZFS package compilation stack successfully staged."
