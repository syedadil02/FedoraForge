#!/usr/bin/env bash
# modules/05_gitea/install.sh
set -euo pipefail
source "$(dirname "$0")/../../lib_utils.sh"

provision_gitea_storage() {
    log_info "Creating optimized NVMe ZFS datasets for Gitea applications..."

    # 1. Create the base service dataset if missing
    if ! zfs list -H -o name | grep -q "^fastpool/gitea$"; then
        zfs create fastpool/gitea || exit 1
        # Optimize block sizes natively for relational DB transactional layers
        zfs set recordsize=16k fastpool/gitea || exit 1
    fi

    # 2. Build internal data layout boundaries
    mkdir -p /fastpool/gitea/{app,db}

    # 3. Apply rootless container UID mappings (Gitea rootless image uses UID 1000)
    log_info "Applying localized security permissions and ownership parameters..."
    chown -R 1000:1000 /fastpool/gitea/app
    chown -R 70:70 /fastpool/gitea/db # Default Postgres Alpine UID/GID

    # 4. Enforce Fedora 44 SELinux compliance contexts
    chcon -Rt container_file_t /fastpool/gitea || exit 1

    log_succ "Gitea ZFS storage infrastructure securely provisioned."
}

provision_gitea_storage
