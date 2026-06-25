#!/usr/bin/env bash
# modules/09_snort3/install.sh
#
# Builds Snort3 from source on Fedora Server.
# Two-stage build:
#   Stage 1 — libdaq : Snort's packet-capture abstraction layer
#   Stage 2 — Snort3 : the IDS engine itself
#
# Idempotent: both stages check for existing binaries before doing any work.
# A full build takes 10-20 min on a VM — subsequent runs skip everything.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/../../lib_utils.sh"

# Only source staging.env if not already loaded by the parent orchestrator
if [[ "${HOMELAB_ENV_LOADED:-false}" != "true" ]]; then
    source "${SCRIPT_DIR}/../../environment/staging.env"
fi

# ─── Defaults (override via staging.env or export before calling) ─────────────
LIBDAQ_VERSION="${LIBDAQ_VERSION:-3.0.27}"
SNORT3_VERSION="${SNORT3_VERSION:-3.12.2.0}"
SNORT_BUILD_DIR="${SNORT_BUILD_DIR:-/tmp/snort-build}"

LIBDAQ_URL="https://github.com/snort3/libdaq/archive/refs/tags/v${LIBDAQ_VERSION}.tar.gz"
SNORT3_URL="https://github.com/snort3/snort3/archive/refs/tags/${SNORT3_VERSION}.tar.gz"

# ─── 1. Build dependencies ────────────────────────────────────────────────────
install_build_deps() {
    log_info "Installing Snort3 build dependencies..."
    dnf install -y \
        gcc-c++ cmake make automake autoconf libtool pkg-config \
        libpcap-devel \
        libdnet-devel hwloc-devel \
        libnfnetlink-devel libmnl-devel libnetfilter_queue-devel \
        openssl-devel zlib-devel xz-devel \
        luajit-devel \
        vectorscan-devel \
        flatbuffers-devel \
        pcre2-devel \
        libpcap
    log_succ "Build dependencies installed."
}

# ─── 2. libdaq ────────────────────────────────────────────────────────────────
# Snort3 requires libdaq 3.x — the Fedora-packaged version is too old.
build_libdaq() {
    if [[ -f /usr/local/lib/libdaq.so ]]; then
        log_info "libdaq already installed — skipping Stage 1."
        return 0
    fi

    log_info "Stage 1: building libdaq ${LIBDAQ_VERSION} from source..."
    mkdir -p "${SNORT_BUILD_DIR}"

    local archive="${SNORT_BUILD_DIR}/libdaq-${LIBDAQ_VERSION}.tar.gz"
    local srcdir="${SNORT_BUILD_DIR}/libdaq-${LIBDAQ_VERSION}"

    [[ -f "${archive}" ]] || {
        log_info "Downloading libdaq..."
        curl -fSL "${LIBDAQ_URL}" -o "${archive}"
    }

    [[ -d "${srcdir}" ]] || {
        log_info "Extracting libdaq..."
        tar -xzf "${archive}" -C "${SNORT_BUILD_DIR}"
    }

    log_info "Compiling libdaq (this takes ~1-2 min)..."
    pushd "${srcdir}" > /dev/null
        autoreconf -fi
        ./configure --prefix=/usr/local
        make -j"$(nproc)"
        make install
        ldconfig
    popd > /dev/null

    log_succ "libdaq ${LIBDAQ_VERSION} installed."
}

# ─── 3. Snort3 ────────────────────────────────────────────────────────────────
build_snort3() {
    if [[ -f /usr/local/bin/snort ]]; then
        log_info "Snort3 binary already exists — skipping Stage 2."
        return 0
    fi

    log_info "Stage 2: building Snort3 ${SNORT3_VERSION} from source..."
    log_warn "This takes 10-20 min on a VM. It will look frozen. It isn't."
    mkdir -p "${SNORT_BUILD_DIR}"

    local archive="${SNORT_BUILD_DIR}/snort3-${SNORT3_VERSION}.tar.gz"
    local srcdir="${SNORT_BUILD_DIR}/snort3-${SNORT3_VERSION}"

    [[ -f "${archive}" ]] || {
        log_info "Downloading Snort3..."
        curl -fSL "${SNORT3_URL}" -o "${archive}"
    }

    [[ -d "${srcdir}" ]] || {
        log_info "Extracting Snort3..."
        tar -xzf "${archive}" -C "${SNORT_BUILD_DIR}"
    }

    log_info "Compiling Snort3..."
    pushd "${srcdir}" > /dev/null
        mkdir -p build && cd build
        cmake .. \
            -DCMAKE_INSTALL_PREFIX=/usr/local \
            -DENABLE_TCMALLOC=OFF
        make -j"$(nproc)"
        make install
        ldconfig
    popd > /dev/null

    log_succ "Snort3 ${SNORT3_VERSION} installed."
}

# ─── 4. Linker configuration ──────────────────────────────────────────────────
# Ensures the dynamic linker can find libdaq.so.3 in /usr/local/lib
configure_ldconfig() {
    local conf=/etc/ld.so.conf.d/usr-local-lib.conf
    if [[ ! -f "${conf}" ]]; then
        log_info "Adding /usr/local/lib to dynamic linker config..."
        echo "/usr/local/lib" > "${conf}"
        ldconfig
    else
        log_info "Linker config already present — skipping."
    fi
}

# ─── 5. Verify install ────────────────────────────────────────────────────────
verify_snort() {
    log_info "Verifying Snort3 install..."
    local ver
    ver=$(/usr/local/bin/snort --version 2>&1 | head -1)
    log_succ "Snort3 version: ${ver}"
}

# ─── 6. Promiscuous mode ──────────────────────────────────────────────────────
# Snort needs to see ALL packets on the segment, not just those addressed to it.
configure_promisc() {
    log_info "Enabling promiscuous mode on ${SNORT_INTERFACE} (immediate)..."
    ip link set "${SNORT_INTERFACE}" promisc on

    local svc_file="/etc/systemd/system/promisc-${SNORT_INTERFACE}.service"
    if [[ ! -f "${svc_file}" ]]; then
        log_info "Deploying promisc persistence service for ${SNORT_INTERFACE}..."
        local tmpl="${SCRIPT_DIR}/templates/promisc.service.tmpl"
        SNORT_INTERFACE="${SNORT_INTERFACE}" envsubst < "${tmpl}" > "${svc_file}"
        chmod 0644 "${svc_file}"
    else
        log_info "Promisc persistence service already deployed — skipping."
    fi

    systemctl daemon-reload
    systemctl enable --now "promisc-${SNORT_INTERFACE}.service"
    log_succ "Promiscuous mode configured and persistent."
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    start_transaction
    log_info "=== Snort3 Install ==="

    install_build_deps
    build_libdaq
    build_snort3
    configure_ldconfig
    verify_snort
    configure_promisc

    commit_transaction
    log_succ "=== Snort3 Install Complete ==="
}

main "$@"
