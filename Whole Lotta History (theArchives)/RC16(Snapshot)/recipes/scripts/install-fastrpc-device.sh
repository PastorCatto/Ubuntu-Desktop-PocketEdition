#!/bin/bash
# Mobuntu RC15 — install-fastrpc-device.sh
# Runs INSIDE the arm64 chroot during debos device build.
# Installs fastrpc-support + DSP binaries into the rootfs.
#
# Called from qcom.yaml as a debos 'run' action:
#
#   - action: run
#     description: Install fastrpc and DSP firmware
#     chroot: false
#     script: recipes/scripts/install-fastrpc-device.sh
#
# Env vars set by debos (via -t flags from run_build.sh):
#   ROOTDIR     — rootfs mount point
#   DEVICE_BRAND, DEVICE_CODENAME

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."

# Debos template substitution doesn't always survive the environment: block.
# Fall back to sourcing build.env from the repo root if vars are empty.
if [ -z "${DEVICE_BRAND}" ] || [ -z "${DEVICE_CODENAME}" ]; then
    BUILDENV="${REPO_ROOT}/build.env"
    [ -f "${BUILDENV}" ] && source "${BUILDENV}" || true
fi

FW_DIR="${REPO_ROOT}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}"
PKG_DIR="${REPO_ROOT}/packages/fastrpc"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ── Stage DSP binaries ─────────────────────────────────────────────────────────

if [ -f "${FW_DIR}/dsp.tar.gz" ]; then
    info "Staging DSP binaries into rootfs..."
    tar -xzf "${FW_DIR}/dsp.tar.gz" -C "${ROOTDIR}/"
    ok "DSP binaries staged at usr/share/qcom/sdm845/Xiaomi/beryllium/{adsp,cdsp,sdsp}"
else
    warn "No dsp.tar.gz found at ${FW_DIR}/dsp.tar.gz — SLPI sensors will not work"
fi

# ── Stage rfsa skel libs ───────────────────────────────────────────────────────

if [ -f "${FW_DIR}/rfsa.tar.gz" ]; then
    info "Staging rfsa/adsp skel libs..."
    tar -xzf "${FW_DIR}/rfsa.tar.gz" -C "${ROOTDIR}/"
    ok "rfsa skel libs staged"
fi

# ── Install fastrpc .deb packages ─────────────────────────────────────────────

if [ -d "${PKG_DIR}" ] && ls "${PKG_DIR}"/*.deb > /dev/null 2>&1; then
    info "Installing fastrpc packages..."

    # Copy debs into rootfs tmp
    mkdir -p "${ROOTDIR}/tmp/fastrpc-debs"
    cp "${PKG_DIR}"/*.deb "${ROOTDIR}/tmp/fastrpc-debs/"

    # Install inside chroot
    chroot "${ROOTDIR}" /bin/bash -c "
        dpkg -i /tmp/fastrpc-debs/libfastrpc1_*.deb 2>/dev/null || true
        dpkg -i /tmp/fastrpc-debs/fastrpc-support_*.deb 2>/dev/null || true
        rm -rf /tmp/fastrpc-debs
    "

    ok "fastrpc-support installed"
else
    warn "No fastrpc .deb files found at ${PKG_DIR}"
    warn "Run build-fastrpc-arm64.sh and stage-dsp-firmware.sh first"
fi

# ── Install adsprpcd udev rules if not already from deb ───────────────────────

UDEV_RULES="${ROOTDIR}/usr/lib/udev/rules.d/60-fastrpc-support.rules"
if [ ! -f "${UDEV_RULES}" ]; then
    warn "fastrpc udev rules not found — writing fallback rules"
    mkdir -p "$(dirname ${UDEV_RULES})"
    cat > "${UDEV_RULES}" << 'UDEV'
# Qualcomm FastRPC DSP device nodes
SUBSYSTEM=="fastrpc-adsp", MODE="0666", GROUP="fastrpc"
SUBSYSTEM=="fastrpc-cdsp", MODE="0666", GROUP="fastrpc"
SUBSYSTEM=="fastrpc-sdsp", MODE="0666", GROUP="fastrpc"
KERNEL=="adsprpc-smd",     MODE="0666", GROUP="fastrpc"
KERNEL=="adsprpc-smd-secure", MODE="0660", GROUP="fastrpc"
UDEV
fi

# ── Enable adsprpcd and cdsprpcd services ──────────────────────────────────────

for svc in adsprpcd cdsprpcd; do
    SVC_FILE="${ROOTDIR}/usr/lib/systemd/system/${svc}.service"
    if [ -f "${SVC_FILE}" ]; then
        mkdir -p "${ROOTDIR}/etc/systemd/system/multi-user.target.wants"
        ln -sf "/usr/lib/systemd/system/${svc}.service" \
            "${ROOTDIR}/etc/systemd/system/multi-user.target.wants/${svc}.service" \
            2>/dev/null || true
        ok "Enabled: ${svc}.service"
    fi
done

info "fastrpc device setup complete"
