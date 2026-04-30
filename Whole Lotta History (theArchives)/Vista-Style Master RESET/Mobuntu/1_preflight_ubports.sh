#!/bin/bash
# Mobuntu — 1_preflight_ubports.sh
# UBports / Ubuntu Touch build preflight.
# Produces run_build_ubports.sh and base-ubports-noble.tar.gz.
#
# Differences from 1_preflight.sh:
#   - Base rootfs comes from UBports PDK (ARM64 raw image), not debootstrap.
#   - No UI selection — Lomiri is already in the PDK.
#   - Ubuntu release is fixed to noble (24.04) — the only supported PDK target.
#   - Generates run_build_ubports.sh (not run_build.sh) to avoid conflicts.
set -e

UBUNTU_RELEASE="ubports-noble"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================="
echo "   Mobuntu — UBports Pre-Flight & Build Setup"
echo "   Base: Ubuntu Touch 24.04 (PDK)"
echo "======================================================="

# -------------------------------------------------------
# Step 1: Host architecture detection
# -------------------------------------------------------
HOST_ARCH=$(uname -m)
HOST_IS_ARM64=false
[ "$HOST_ARCH" = "aarch64" ] && HOST_IS_ARM64=true
echo ">>> Host architecture: $HOST_ARCH"

# -------------------------------------------------------
# Step 2: Fakemachine backend detection
# -------------------------------------------------------
echo ">>> Detecting fakemachine backend..."
FAKEMACHINE_BACKEND=""

if [ -e /dev/kvm ]; then
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        FAKEMACHINE_BACKEND="kvm"
        echo ">>> Backend: kvm (~9 min build)"
    else
        echo ">>> /dev/kvm exists but not accessible."
        echo ">>> Fix: sudo adduser $USER kvm && newgrp kvm"
    fi
fi

if [ -z "$FAKEMACHINE_BACKEND" ]; then
    command -v linux &>/dev/null && FAKEMACHINE_BACKEND="uml" && \
        echo ">>> Backend: uml (~18 min build)"
fi

if [ -z "$FAKEMACHINE_BACKEND" ]; then
    FAKEMACHINE_BACKEND="qemu"
    echo ""
    echo "======================================================="
    echo "  WARNING: Using QEMU fakemachine backend (~2.5 hours)."
    echo "  Install user-mode-linux for 5x speedup, or add"
    echo "  yourself to the kvm group for 15x speedup."
    echo "======================================================="
    echo ""
fi

echo ""
read -p "Override backend? [kvm/uml/qemu/none, Enter to keep '$FAKEMACHINE_BACKEND']: " BACKEND_OVERRIDE
if [ -n "$BACKEND_OVERRIDE" ]; then
    FAKEMACHINE_BACKEND="$BACKEND_OVERRIDE"
    echo ">>> Backend overridden to: $FAKEMACHINE_BACKEND"
fi

if [ "$FAKEMACHINE_BACKEND" = "none" ]; then
    DEBOS_BACKEND_FLAG="--disable-fakemachine"
else
    DEBOS_BACKEND_FLAG="--fakemachine-backend=${FAKEMACHINE_BACKEND}"
fi

# -------------------------------------------------------
# Step 3: Host dependencies
# -------------------------------------------------------
echo ">>> Installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget xz-utils e2fsprogs curl git \
    zip ca-certificates rsync \
    dosfstools uuid-runtime \
    android-sdk-libsparse-utils \
    lz4 qemu-system-aarch64 \
    qemu-user-static binfmt-support \
    systemd-container util-linux \
    golang libglib2.0-dev libostree-dev \
    equivs

if ! command -v debos &>/dev/null; then
    echo ">>> debos not found — building from source..."
    export GOPATH=/opt/mobuntu-gopath
    sudo mkdir -p "$GOPATH"
    sudo chown "$USER:$USER" "$GOPATH"
    go install -v github.com/go-debos/debos/cmd/debos@latest
    sudo cp "$GOPATH/bin/debos" /usr/local/bin/debos
fi

if [ "$FAKEMACHINE_BACKEND" = "uml" ]; then
    sudo apt-get install -y user-mode-linux
fi

if ! command -v mkbootimg &>/dev/null; then
    echo ">>> Building mkbootimg (host)..."
    sudo apt-get install -y gcc make
    sudo apt-get remove -y mkbootimg 2>/dev/null || true
    git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-tool
    sed -i 's/-Werror//g' /tmp/mkbootimg-tool/libmincrypt/Makefile
    make -C /tmp/mkbootimg-tool CFLAGS="-ffunction-sections -O3"
    sudo cp /tmp/mkbootimg-tool/mkbootimg /usr/local/bin/mkbootimg
    sudo chmod +x /usr/local/bin/mkbootimg
    rm -rf /tmp/mkbootimg-tool
fi

# -------------------------------------------------------
# Step 3b: Dummy package check
# -------------------------------------------------------
DUMMY_DIR="${SCRIPT_DIR}/packages/dummy"
DUMMY_MISSING=false

for pkg in hexagonrpcd qcom-support-common; do
    if ! ls "${DUMMY_DIR}/${pkg}_"*.deb > /dev/null 2>&1; then
        echo ">>> [WARN] Missing dummy .deb: ${pkg}"
        DUMMY_MISSING=true
    fi
done

if [ "$DUMMY_MISSING" = "true" ]; then
    echo ""
    echo "======================================================="
    echo "  Dummy packages not found in packages/dummy/"
    echo "======================================================="
    read -p "Build dummy packages now? [Y/n]: " BUILD_DUMMIES
    if [[ ! "$BUILD_DUMMIES" =~ ^[Nn]$ ]]; then
        [ -f "${DUMMY_DIR}/build-dummies.sh" ] || \
            { echo "ERROR: build-dummies.sh not found."; exit 1; }
        bash "${DUMMY_DIR}/build-dummies.sh"
    else
        echo "WARNING: Skipping dummy build. The debos run WILL FAIL"
        echo "         if dummy packages are absent when qcom.yaml runs."
    fi
else
    echo ">>> Dummy packages present: OK"
fi

# -------------------------------------------------------
# Step 4: Device selection
# -------------------------------------------------------
echo "======================================================="
echo "   Device Selection"
echo "======================================================="

DEVICES_DIR="${SCRIPT_DIR}/devices"
[ -d "$DEVICES_DIR" ] || { echo "ERROR: devices/ not found"; exit 1; }

# UBports only supports SDM845 devices for now
mapfile -t DEVICE_CONFIGS < <(ls "$DEVICES_DIR"/{xiaomi,oneplus}-*.conf 2>/dev/null | sort)
[ ${#DEVICE_CONFIGS[@]} -eq 0 ] && \
    { echo "ERROR: No SDM845 device configs found in devices/"; exit 1; }

echo "Available devices (SDM845 / UBports supported):"
for i in "${!DEVICE_CONFIGS[@]}"; do
    source "${DEVICE_CONFIGS[$i]}"
    echo "  $((i+1))) $DEVICE_NAME  [$(basename ${DEVICE_CONFIGS[$i]})]"
done

echo ""
read -p "Select device [1-${#DEVICE_CONFIGS[@]}]: " DEV_CHOICE
DEV_CHOICE=${DEV_CHOICE:-1}
DEV_IDX=$((DEV_CHOICE - 1))
[ $DEV_IDX -lt 0 ] || [ $DEV_IDX -ge ${#DEVICE_CONFIGS[@]} ] && \
    { echo "ERROR: Invalid selection"; exit 1; }

DEVICE_CONF="${DEVICE_CONFIGS[$DEV_IDX]}"
source "$DEVICE_CONF"
echo ">>> Selected: $DEVICE_NAME"

# -------------------------------------------------------
# Step 5: Build configuration
# -------------------------------------------------------
echo "======================================================="
echo "   Build Configuration"
echo "======================================================="

read -p "Username [default: phablet]: " USERNAME
USERNAME=${USERNAME:-phablet}
read -s -p "Password [default: 1234]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-1234}

echo ""
echo "Build color:"
for n in "1:orange" "2:pink" "3:yellow" "4:red" "5:blue" \
         "6:green"  "7:purple" "8:cyan" "9:white" "10:black"; do
    echo "  ${n%%:*}) ${n##*:}"
done
echo "  11) custom"
read -p "Choice [1-11, default 3]: " COLOR_CHOICE
case ${COLOR_CHOICE:-3} in
    1) BUILD_COLOR="orange"  ;;  2) BUILD_COLOR="pink"   ;;
    3) BUILD_COLOR="yellow"  ;;  4) BUILD_COLOR="red"    ;;
    5) BUILD_COLOR="blue"    ;;  6) BUILD_COLOR="green"  ;;
    7) BUILD_COLOR="purple"  ;;  8) BUILD_COLOR="cyan"   ;;
    9) BUILD_COLOR="white"   ;; 10) BUILD_COLOR="black"  ;;
    11) read -p "Custom color: " BUILD_COLOR; BUILD_COLOR=${BUILD_COLOR:-custom} ;;
    *)  BUILD_COLOR="yellow" ;;
esac
DEVICE_HOSTNAME="mobuntu-${BUILD_COLOR}"

if [ "$BOOT_PANEL_PICKER" = "true" ]; then
    echo ""
    echo "Display panel:"
    echo "1) Tianma (default)"
    echo "2) EBBG"
    read -p "Choice [1-2, default 1]: " PANEL_CHOICE
    case ${PANEL_CHOICE:-1} in
        2) BOOT_PANEL="ebbg"   ; BOOT_DTB_SELECTED="sdm845-xiaomi-beryllium-ebbg.dtb"  ;;
        *) BOOT_PANEL="tianma" ; BOOT_DTB_SELECTED="sdm845-xiaomi-beryllium-tianma.dtb" ;;
    esac
else
    BOOT_PANEL="default"
    BOOT_DTB_SELECTED="$BOOT_DTB"
fi

read -p "RootFS size in GB [default: 12, min 8]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
[ "$IMG_INPUT" -lt 8 ] && IMAGE_SIZE=8 || IMAGE_SIZE=$IMG_INPUT

ROOTFS_DIR="mobuntu-${DEVICE_CODENAME}-${UBUNTU_RELEASE}"

# -------------------------------------------------------
# Step 6: Extract UBports PDK rootfs
# -------------------------------------------------------
echo "======================================================="
echo "   UBports PDK Rootfs"
echo "======================================================="

BASE_TARBALL="${SCRIPT_DIR}/base-${UBUNTU_RELEASE}.tar.gz"

if [ -f "$BASE_TARBALL" ]; then
    echo ">>> Cached base tarball found: $BASE_TARBALL ($(du -sh $BASE_TARBALL | cut -f1))"
    read -p "Re-extract from PDK? [y/N]: " REEXTRACT
    if [[ "$REEXTRACT" =~ ^[Yy]$ ]]; then
        rm -f "$BASE_TARBALL"
    fi
fi

if [ ! -f "$BASE_TARBALL" ]; then
    echo ">>> Extracting UBports PDK rootfs..."
    OUTPUT_DIR="$SCRIPT_DIR" \
        bash "${SCRIPT_DIR}/recipes/scripts/extract-ubports-pdk.sh"
    [ -f "$BASE_TARBALL" ] || \
        { echo "ERROR: PDK extraction failed — $BASE_TARBALL not found."; exit 1; }
    echo ">>> Base tarball ready: $BASE_TARBALL ($(du -sh $BASE_TARBALL | cut -f1))"
else
    echo ">>> Using cached base tarball."
fi

# -------------------------------------------------------
# Step 7: Save build.env
# -------------------------------------------------------
cat > "${SCRIPT_DIR}/build.env" << EOF
# Mobuntu UBports — build configuration
# Generated by 1_preflight_ubports.sh

HOST_ARCH="${HOST_ARCH}"
HOST_IS_ARM64="${HOST_IS_ARM64}"
FAKEMACHINE_BACKEND="${FAKEMACHINE_BACKEND}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
ROOTFS_DIR="${ROOTFS_DIR}"
IMAGE_SIZE="${IMAGE_SIZE}"
EXTRA_PKG=""
DEVICE_CONF="${DEVICE_CONF}"

DEVICE_NAME="${DEVICE_NAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_BRAND="${DEVICE_BRAND}"
DEVICE_ARCH="${DEVICE_ARCH}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME}"
BUILD_COLOR="${BUILD_COLOR}"
BOOT_PANEL="${BOOT_PANEL}"
BOOT_DTB_SELECTED="${BOOT_DTB_SELECTED}"
DEVICE_IMAGE_LABEL="${DEVICE_IMAGE_LABEL}"
DEVICE_PACKAGES="${DEVICE_PACKAGES}"
DEVICE_SERVICES="${DEVICE_SERVICES}"

UI_NAME="ubports"
UI_DM="lomiri"

KERNEL_METHOD="${KERNEL_METHOD}"
KERNEL_REPO="${KERNEL_REPO}"
KERNEL_SERIES="${KERNEL_SERIES}"
KERNEL_VERSION_PIN="${KERNEL_VERSION_PIN:-}"

BOOT_METHOD="${BOOT_METHOD}"
MKBOOTIMG_PAGESIZE="${MKBOOTIMG_PAGESIZE}"
MKBOOTIMG_BASE="${MKBOOTIMG_BASE}"
MKBOOTIMG_KERNEL_OFFSET="${MKBOOTIMG_KERNEL_OFFSET}"
MKBOOTIMG_RAMDISK_OFFSET="${MKBOOTIMG_RAMDISK_OFFSET}"
MKBOOTIMG_TAGS_OFFSET="${MKBOOTIMG_TAGS_OFFSET}"
BOOT_DTB_APPEND="${BOOT_DTB_APPEND}"
BOOT_DTB="${BOOT_DTB}"
BOOT_PANEL_PICKER="${BOOT_PANEL_PICKER}"
EOF
echo ">>> build.env saved."

# -------------------------------------------------------
# Step 8: Generate run_build_ubports.sh
# -------------------------------------------------------
RECIPE_DEVICE="${SCRIPT_DIR}/recipes/devices/${DEVICE_CODENAME}.yaml"
[ -f "$RECIPE_DEVICE" ] || \
    echo ">>> WARNING: No recipe at $RECIPE_DEVICE"

DEVICE_TARBALL="${DEVICE_IMAGE_LABEL}-${UBUNTU_RELEASE}.tar.gz"

cat > "${SCRIPT_DIR}/run_build_ubports.sh" << RUNEOF
#!/bin/bash
# Mobuntu UBports — run_build_ubports.sh
# Generated by 1_preflight_ubports.sh — do not edit manually.
set -e

SCRIPT_DIR="${SCRIPT_DIR}"
BASE_TARBALL="base-${UBUNTU_RELEASE}.tar.gz"
DEVICE_TARBALL="${DEVICE_TARBALL}"

cd "\${SCRIPT_DIR}"

echo "======================================================="
echo "   Mobuntu UBports — Build: ${DEVICE_NAME}"
echo "   Base: Ubuntu Touch 24.04 (PDK)"
echo "   Backend: ${FAKEMACHINE_BACKEND}"
echo "======================================================="

# ------- Step 1: Base tarball (already extracted by preflight) -------
if [ ! -f "\${BASE_TARBALL}" ]; then
    echo "ERROR: Base tarball not found: \${BASE_TARBALL}"
    echo "       Re-run 1_preflight_ubports.sh to extract the PDK."
    exit 1
fi
echo ">>> Base tarball: \${BASE_TARBALL} ($(du -sh ${SCRIPT_DIR}/base-${UBUNTU_RELEASE}.tar.gz 2>/dev/null | cut -f1 || echo "?"))"

# ------- Step 2: Device tarball -------
echo ">>> Building device tarball: ${DEVICE_NAME}..."
debos ${DEBOS_BACKEND_FLAG} \\
  --artifactdir="\$(pwd)" \\
  -t "UBUNTU_RELEASE:${UBUNTU_RELEASE}" \\
  -t "USERNAME:${USERNAME}" \\
  -t "PASSWORD:${PASSWORD}" \\
  -t "DEVICE_CODENAME:${DEVICE_CODENAME}" \\
  -t "DEVICE_BRAND:${DEVICE_BRAND}" \\
  -t "DEVICE_HOSTNAME:${DEVICE_HOSTNAME}" \\
  -t "DEVICE_IMAGE_LABEL:${DEVICE_IMAGE_LABEL}" \\
  -t "DEVICE_PACKAGES:${DEVICE_PACKAGES}" \\
  -t "DEVICE_SERVICES:${DEVICE_SERVICES}" \\
  -t "UI_NAME:ubports" \\
  -t "UI_DM:lomiri" \\
  -t "BUILD_COLOR:${BUILD_COLOR}" \\
  -t "EXTRA_PKG:" \\
  -t "KERNEL_METHOD:${KERNEL_METHOD}" \\
  -t "KERNEL_REPO:${KERNEL_REPO}" \\
  -t "KERNEL_SERIES:${KERNEL_SERIES}" \\
  -t "KERNEL_VERSION_PIN:${KERNEL_VERSION_PIN:-}" \\
  -t "BOOT_METHOD:${BOOT_METHOD}" \\
  -t "BOOT_DTB:${BOOT_DTB_SELECTED}" \\
  -t "BOOT_DTB_APPEND:${BOOT_DTB_APPEND}" \\
  -t "DEVICE_UBUNTU_OVERRIDE:${UBUNTU_RELEASE}" \\
  "${RECIPE_DEVICE}"

echo ""
echo ">>> Device tarball ready: \${DEVICE_TARBALL}"
echo ">>> Run 5_seal_rootfs.sh to package and flash."
RUNEOF

chmod +x "${SCRIPT_DIR}/run_build_ubports.sh"
echo ">>> run_build_ubports.sh generated."

# -------------------------------------------------------
# Step 9: Summary
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   Ready"
echo "======================================================="
echo ""
echo "  build.env             → saved"
echo "  run_build_ubports.sh  → generated"
echo "  Base tarball          → base-${UBUNTU_RELEASE}.tar.gz"
echo ""
echo "  To build:   bash run_build_ubports.sh"
echo "  To seal:    bash 5_seal_rootfs.sh"
echo ""
read -p "Run build now? [y/N]: " RUN_NOW
[[ "$RUN_NOW" =~ ^[Yy]$ ]] && bash "${SCRIPT_DIR}/run_build_ubports.sh" || true
