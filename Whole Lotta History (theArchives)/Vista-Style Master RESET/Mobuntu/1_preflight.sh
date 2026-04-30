#!/bin/bash
# Mobuntu — RC17
set -e
echo "======================================================="
echo "   Mobuntu — RC17 Pre-Flight & Build Setup"
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
    if command -v linux &>/dev/null; then
        FAKEMACHINE_BACKEND="uml"
        echo ">>> Backend: uml (~18 min build)"
    fi
fi

if [ -z "$FAKEMACHINE_BACKEND" ]; then
    FAKEMACHINE_BACKEND="qemu"
    echo ""
    echo "======================================================="
    echo "  WARNING: Using QEMU fakemachine backend."
    echo "  This is the slowest option (~2.5 hours for base build)."
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
    echo ">>> WARNING: --disable-fakemachine requires root and is not sandboxed."
else
    DEBOS_BACKEND_FLAG="--fakemachine-backend=${FAKEMACHINE_BACKEND}"
fi

# -------------------------------------------------------
# Step 3: Host dependencies
# -------------------------------------------------------
echo ">>> Installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap e2fsprogs curl wget git \
    xz-utils gzip zip ca-certificates rsync \
    dosfstools uuid-runtime \
    android-sdk-libsparse-utils \
    lz4 qemu-system-aarch64 \
    qemu-user-static binfmt-support \
    systemd-container \
    golang libglib2.0-dev libostree-dev \
    equivs

# Install debos if not present
if ! command -v debos &>/dev/null; then
    echo ">>> debos not found — building from source..."
    export GOPATH=/opt/mobuntu-gopath
    sudo mkdir -p "$GOPATH"
    sudo chown "$USER:$USER" "$GOPATH"
    go install -v github.com/go-debos/debos/cmd/debos@latest
    sudo cp "$GOPATH/bin/debos" /usr/local/bin/debos
    echo ">>> debos installed."
else
    echo ">>> debos found: $(which debos)"
fi

if [ "$FAKEMACHINE_BACKEND" = "uml" ]; then
    sudo apt-get install -y user-mode-linux
fi

# Host-side abootimg (for 5_seal_rootfs.sh — replaces mkbootimg in RC17)
if ! command -v abootimg &>/dev/null; then
    echo ">>> Installing abootimg (host)..."
    sudo apt-get install -y abootimg
fi

# Ensure resolute suite known to debootstrap
if [ ! -f /usr/share/debootstrap/scripts/resolute ]; then
    sudo ln -sf /usr/share/debootstrap/scripts/gutsy \
        /usr/share/debootstrap/scripts/resolute
fi

# -------------------------------------------------------
# Step 3b: Dummy package check
# -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DUMMY_DIR="${SCRIPT_DIR}/packages/dummy"
DUMMY_MISSING=false

# RC17: hexagonrpcd is now installed for real — only qcom-support-common needs a dummy
for pkg in qcom-support-common; do
    if ! ls "${DUMMY_DIR}/${pkg}_"*.deb > /dev/null 2>&1; then
        echo ">>> [WARN] Missing dummy .deb: ${pkg}"
        DUMMY_MISSING=true
    fi
done

if [ "$DUMMY_MISSING" = "true" ]; then
    echo ""
    echo "======================================================="
    echo "  Dummy package not found in packages/dummy/"
    echo "  qcom-support-common must be blocked to prevent"
    echo "  it from conflicting with the manual QCOM setup."
    echo "======================================================="
    read -p "Build dummy packages now? [Y/n]: " BUILD_DUMMIES
    if [[ ! "$BUILD_DUMMIES" =~ ^[Nn]$ ]]; then
        if [ -f "${DUMMY_DIR}/build-dummies.sh" ]; then
            bash "${DUMMY_DIR}/build-dummies.sh"
        else
            echo "ERROR: ${DUMMY_DIR}/build-dummies.sh not found."
            echo "       Cannot proceed without dummy packages."
            exit 1
        fi
    else
        echo ""
        echo "WARNING: Skipping dummy build. The debos run WILL FAIL"
        echo "         if dummy packages are absent when qcom.yaml runs."
        echo ""
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

mapfile -t DEVICE_CONFIGS < <(ls "$DEVICES_DIR"/*.conf 2>/dev/null | sort)
[ ${#DEVICE_CONFIGS[@]} -eq 0 ] && { echo "ERROR: No device configs found"; exit 1; }

echo "Available devices:"
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

read -p "Username [default: phone]: " USERNAME
USERNAME=${USERNAME:-phone}
read -s -p "Password [default: 1234]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-1234}

echo ""
echo "Ubuntu release:"
echo "1) noble    (24.04 LTS)"
echo "2) oracular (24.10)"
echo "3) resolute (26.04 LTS — recommended)"
read -p "Choice [1-3, default 3]: " REL_CHOICE
case ${REL_CHOICE:-3} in
    1) UBUNTU_RELEASE="noble"    ;;
    2) UBUNTU_RELEASE="oracular" ;;
    *) UBUNTU_RELEASE="resolute" ;;
esac

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

read -p "Extra packages (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

echo ""
echo "UI / Desktop environment:"
echo "1) Phosh              (recommended for phones)"
echo "2) Ubuntu Desktop     (ubuntu-desktop-minimal)"
echo "3) Unity"
echo "4) Plasma Desktop"
echo "5) Plasma Mobile"
echo "6) Lomiri             (experimental)"
read -p "Choice [1-6, default 1]: " UI_CHOICE
case ${UI_CHOICE:-1} in
    2) UI_NAME="ubuntu-desktop-minimal"; UI_DM="gdm3"    ;;
    3) UI_NAME="unity";                  UI_DM="lightdm" ;;
    4) UI_NAME="plasma-desktop";         UI_DM="sddm"    ;;
    5) UI_NAME="plasma-mobile";          UI_DM="sddm"    ;;
    6)
        echo "WARNING: Lomiri is experimental."
        read -p "Continue? [y/N]: " LOMIRI_OK
        if [[ "$LOMIRI_OK" =~ ^[Yy]$ ]]; then
            UI_NAME="lomiri"; UI_DM="greetd"
        else
            UI_NAME="phosh"; UI_DM="greetd"
        fi ;;
    *) UI_NAME="phosh"; UI_DM="greetd" ;;
esac
echo ">>> UI: $UI_NAME  DM: $UI_DM"

ROOTFS_DIR="mobuntu-${DEVICE_CODENAME}-${UBUNTU_RELEASE}"

# -------------------------------------------------------
# Step 5b: Kernel source selection
# -------------------------------------------------------
echo ""
echo "Kernel source:"
echo "1) Local deb files in files/  (RC17 — arkadin91 7.1.0-rc1-sdm845, recommended)"
echo "2) Mobian APT                 (RC10.2-LTS / RC13-LTS — stable baseline)"
read -p "Choice [1-2, default 1]: " KERN_CHOICE
case ${KERN_CHOICE:-1} in
    2)
        KERNEL_METHOD="mobian"
        # KERNEL_SERIES/KERNEL_REPO come from the device config sourced above
        echo ">>> Kernel: Mobian APT (${KERNEL_SERIES})"
        ;;
    *)
        KERNEL_METHOD="local-deb"
        KERNEL_REPO=""
        # Detect version from deb filename in files/
        FILES_DIR="${SCRIPT_DIR}/files"
        KERN_DEB=$(ls "${FILES_DIR}"/linux-image-*.deb 2>/dev/null | head -1)
        FW_DEB=$(ls "${FILES_DIR}"/linux-firmware-*.deb 2>/dev/null | head -1)
        if [ -z "$KERN_DEB" ]; then
            echo ""
            echo "ERROR: No linux-image-*.deb found in files/"
            echo "       Place linux-image-*.deb, linux-headers-*.deb, and"
            echo "       linux-firmware-*.deb in ${FILES_DIR}/ and re-run."
            exit 1
        fi
        if [ -z "$FW_DEB" ]; then
            echo ""
            echo "ERROR: No linux-firmware-*.deb found in files/"
            echo "       Place linux-firmware-xiaomi-beryllium-sdm845_*.deb"
            echo "       in ${FILES_DIR}/ and re-run."
            exit 1
        fi
        # Extract version from deb filename (linux-image-7.1.0-rc1-sdm845_1.0_arm64.deb)
        KERNEL_SERIES=$(basename "$KERN_DEB" | sed 's/linux-image-\([^_]*\)_.*/\1/')
        echo ">>> Kernel: local-deb (${KERNEL_SERIES})"
        echo "    Image   : $(basename $KERN_DEB)"
        echo "    Firmware: $(basename $FW_DEB)"
        ;;
esac

# DEVICE_MASKED_SERVICES — read from device conf or set default for QCOM devices
DEVICE_MASKED_SERVICES="${DEVICE_MASKED_SERVICES:-alsa-state alsa-restore}"

# -------------------------------------------------------
# Step 6: Save build.env
# -------------------------------------------------------
cat > build.env << EOF
# Mobuntu RC17 — build configuration
# Generated by 1_preflight.sh

HOST_ARCH="${HOST_ARCH}"
HOST_IS_ARM64="${HOST_IS_ARM64}"
FAKEMACHINE_BACKEND="${FAKEMACHINE_BACKEND}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
ROOTFS_DIR="${ROOTFS_DIR}"
IMAGE_SIZE="${IMAGE_SIZE}"
EXTRA_PKG="${EXTRA_PKG}"
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
DEVICE_MASKED_SERVICES="${DEVICE_MASKED_SERVICES}"

UI_NAME="${UI_NAME}"
UI_DM="${UI_DM}"

KERNEL_METHOD="${KERNEL_METHOD}"
KERNEL_REPO="${KERNEL_REPO}"
KERNEL_SERIES="${KERNEL_SERIES}"
KERNEL_VERSION_PIN="${KERNEL_VERSION_PIN}"

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
# Step 7: Resolve recipe path
# -------------------------------------------------------
RECIPE_DEVICE="${SCRIPT_DIR}/recipes/devices/${DEVICE_CODENAME}.yaml"
if [ ! -f "$RECIPE_DEVICE" ]; then
    echo ">>> WARNING: No recipe at $RECIPE_DEVICE"
    echo ">>>          Check recipes/devices/ for available recipes."
fi

# If device config declares a Ubuntu override (e.g. Switch locks to noble),
# use it for the base tarball and device tarball names.
EFFECTIVE_RELEASE="${DEVICE_UBUNTU_OVERRIDE:-${UBUNTU_RELEASE}}"
BASE_TARBALL="base-${EFFECTIVE_RELEASE}.tar.gz"
DEVICE_TARBALL="${DEVICE_IMAGE_LABEL}-${EFFECTIVE_RELEASE}.tar.gz"

# -------------------------------------------------------
# Step 8: Generate run_build.sh
# -------------------------------------------------------

# Build -t flag block. Values with spaces are quoted.
build_t_flags() {
cat << TEOF
  -t "UBUNTU_RELEASE:${UBUNTU_RELEASE}" \\
  -t "USERNAME:${USERNAME}" \\
  -t "PASSWORD:${PASSWORD}" \\
  -t "DEVICE_CODENAME:${DEVICE_CODENAME}" \\
  -t "DEVICE_BRAND:${DEVICE_BRAND}" \\
  -t "DEVICE_HOSTNAME:${DEVICE_HOSTNAME}" \\
  -t "DEVICE_IMAGE_LABEL:${DEVICE_IMAGE_LABEL}" \\
  -t "DEVICE_PACKAGES:${DEVICE_PACKAGES}" \\
  -t "DEVICE_SERVICES:${DEVICE_SERVICES}" \\
  -t "DEVICE_MASKED_SERVICES:${DEVICE_MASKED_SERVICES}" \\
  -t "UI_NAME:${UI_NAME}" \\
  -t "UI_DM:${UI_DM}" \\
  -t "BUILD_COLOR:${BUILD_COLOR}" \\
  -t "EXTRA_PKG:${EXTRA_PKG}" \\
  -t "KERNEL_METHOD:${KERNEL_METHOD}" \\
  -t "KERNEL_REPO:${KERNEL_REPO}" \\
  -t "KERNEL_SERIES:${KERNEL_SERIES}" \\
  -t "KERNEL_VERSION_PIN:${KERNEL_VERSION_PIN}" \\
  -t "BOOT_METHOD:${BOOT_METHOD}" \\
  -t "BOOT_DTB:${BOOT_DTB_SELECTED}" \\
  -t "BOOT_DTB_APPEND:${BOOT_DTB_APPEND}" \\
  -t "DEVICE_UBUNTU_OVERRIDE:${EFFECTIVE_RELEASE}"
TEOF
}

T_FLAGS="$(build_t_flags)"

cat > run_build.sh << RUNEOF
#!/bin/bash
# Mobuntu RC17 — run_build.sh
# Generated by 1_preflight.sh — do not edit manually.
# Re-run 1_preflight.sh to regenerate.
set -e

SCRIPT_DIR="${SCRIPT_DIR}"
BASE_TARBALL="${BASE_TARBALL}"
DEVICE_TARBALL="${DEVICE_TARBALL}"
EFFECTIVE_RELEASE="${EFFECTIVE_RELEASE}"  # noble for Switch, UBUNTU_RELEASE for others

# debos resolves recipe-relative paths against $(pwd) when using the none
# backend. Always cd into the repo root so overlays/scripts/etc resolve correctly
# regardless of where the user invoked this script from.
cd "\${SCRIPT_DIR}"

echo "======================================================="
echo "   Mobuntu RC17 — Build: ${DEVICE_NAME}"
echo "   Release: ${UBUNTU_RELEASE}  Backend: ${FAKEMACHINE_BACKEND}"
echo "======================================================="

# ------- Step 1: Base tarball -------
if [ ! -f "\${BASE_TARBALL}" ] || \
   [ "\${SCRIPT_DIR}/recipes/base.yaml" -nt "\${BASE_TARBALL}" ]; then
    echo ">>> Building base tarball..."
    debos ${DEBOS_BACKEND_FLAG} \\
      --artifactdir="\$(pwd)" \\
${T_FLAGS} \\
      "\${SCRIPT_DIR}/recipes/base.yaml"
    echo ">>> Base tarball ready: \${BASE_TARBALL}"
else
    echo ">>> Base tarball up to date — skipping base build."
fi

# ------- Step 2: Device tarball -------
echo ">>> Building device tarball: ${DEVICE_NAME}..."
debos ${DEBOS_BACKEND_FLAG} \\
  --artifactdir="\$(pwd)" \\
${T_FLAGS} \\
  "${RECIPE_DEVICE}"

echo ""
echo ">>> Device tarball ready: \${DEVICE_TARBALL}"
echo ">>> Run 5_seal_rootfs.sh to package and flash."
RUNEOF

chmod +x run_build.sh
echo ">>> run_build.sh generated."
echo ""

# -------------------------------------------------------
# Step 9: Watchdog option
# -------------------------------------------------------
echo "======================================================="
echo "   Watchdog / Auto Build"
echo "======================================================="
echo "Enable watchdog? (auto-runs run_build.sh unattended)"
echo "1) Yes"
echo "2) No (default)"
read -p "Choice [1-2, default 2]: " WD_CHOICE
WATCHDOG_ENABLED="false"
[ "${WD_CHOICE:-2}" = "1" ] && WATCHDOG_ENABLED="true"

AUTO_SUDO="false"
if [ "$WATCHDOG_ENABLED" = "true" ]; then
    echo ""
    echo "======================================================="
    echo "  WARNING: Auto-sudo is not sandboxed."
    echo "  Only use inside WSL2, VM, or container."
    echo "======================================================="
    read -p "Enable auto-sudo? [y/N]: " SUDO_CONFIRM
    [[ "$SUDO_CONFIRM" =~ ^[Yy]$ ]] && AUTO_SUDO="true"
fi

echo "WATCHDOG_ENABLED=\"${WATCHDOG_ENABLED}\"" >> build.env
echo "AUTO_SUDO=\"${AUTO_SUDO}\""               >> build.env

# -------------------------------------------------------
# Step 10: Summary + optional auto-run
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   Ready"
echo "======================================================="
echo ""
echo "  build.env    → saved"
echo "  run_build.sh → generated"
echo ""
echo "  To build:    bash run_build.sh"
echo "  To seal:     bash 5_seal_rootfs.sh"
echo "  To verify:   bash verify_build.sh"
echo ""
read -p "Run build now? [y/N]: " RUN_NOW
[[ "$RUN_NOW" =~ ^[Yy]$ ]] && bash run_build.sh || true
