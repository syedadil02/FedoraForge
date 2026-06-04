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
sudo dnf5 install -y "https://zfsonlinux.org/fedora/zfs-release-3-1${DIST_TAG}.noarch.rpm" || exit 1

log_info "Configuring DNF5 repository targets for ZFS..."
# DNF5 native syntax to disable the testing/raw repositories and enable legacy (stable kmod)
sudo dnf5 config-manager set_property zfs.enabled=0 || exit 1
sudo dnf5 config-manager set_property zfs-legacy.enabled=1 || exit 1

log_info "Aligning current kernel tracking with compilation dependencies..."
# Instead of guessing the string via awk, force dnf to match your exact running kernel version natively
sudo dnf5 install -y "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)" dkms || exit 1

log_info "Triggering OpenZFS dkms source compilation..."
sudo dnf5 install -y zfs || exit 1

log_succ "ZFS package compilation stack successfully staged."
