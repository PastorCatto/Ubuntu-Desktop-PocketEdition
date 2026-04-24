#!/bin/bash
# Mobuntu Orange — RC1-mkosi
# [1/2] Pre-Flight & Configuration
# Generates mkosi.conf and stages device files.
# Debug mode: skips mkosi.finalize (boot.img/rootfs sealing).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================="
echo "   Mobuntu Orange — [1/2] Pre-Flight (mkosi)"
echo "======================================================="

# -------------------------------------------------------
# Step 1: Host dependencies
# -------------------------------------------------------
echo ">>> Installing host dependencies..."
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    mkosi debootstrap qemu-user-binfmt-hwe \
    sudo e2fsprogs curl wget git python3 \
    uuid-runtime android-sdk-libsparse-utils \
    rsync dosfstools make gcc libc-dev xz-utils

MKOSI_VER=$(mkosi --version 2>/dev/null | grep -oE "[0-9]+" | head -1 || echo "0")
if [ "$MKOSI_VER" -lt 16 ] 2>/dev/null; then
    echo ">>> mkosi too old, installing from pip..."
    sudo pip3 install --break-system-packages mkosi || sudo pip3 install mkosi
fi

echo ">>> Building mkbootimg from source (osm0sis fork)..."
sudo apt-get remove -y mkbootimg 2>/dev/null || true
if [ ! -f /usr/local/bin/mkbootimg ]; then
    git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-tool
    sed -i 's/-Werror//g' /tmp/mkbootimg-tool/Makefile
    sed -i 's/-Werror//g' /tmp/mkbootimg-tool/libmincrypt/Makefile
    make -C /tmp/mkbootimg-tool
    sudo cp /tmp/mkbootimg-tool/mkbootimg /usr/local/bin/mkbootimg
    sudo chmod +x /usr/local/bin/mkbootimg
    rm -rf /tmp/mkbootimg-tool
fi

for suite in resolute plucky; do
    [ ! -f /usr/share/debootstrap/scripts/$suite ] && \
        sudo ln -sf /usr/share/debootstrap/scripts/gutsy \
            /usr/share/debootstrap/scripts/$suite
done

# -------------------------------------------------------
# Step 2: Debug mode
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   Build Mode"
echo "======================================================="
echo "  1) Full build — rootfs + boot.img + root.img (default)"
echo "  2) Debug mode — rootfs only, skip sealing"
echo "     Use debug to iterate quickly without flashing."
read -p "Choice [1-2, default 1]: " DEBUG_CHOICE
case ${DEBUG_CHOICE:-1} in
    2) DEBUG_MODE=true  ; echo ">>> Debug mode: ON  (sealing disabled)" ;;
    *) DEBUG_MODE=false ; echo ">>> Debug mode: OFF (full build)"       ;;
esac

# -------------------------------------------------------
# Step 3: Device selection
# -------------------------------------------------------
echo "======================================================="
echo "   Device Selection"
echo "======================================================="

DEVICES_DIR="${SCRIPT_DIR}/devices"
mapfile -t DEVICE_CONFIGS < <(ls "$DEVICES_DIR"/*.conf 2>/dev/null | sort)
[ ${#DEVICE_CONFIGS[@]} -eq 0 ] && { echo "ERROR: No device configs found."; exit 1; }

echo "Available devices:"
for i in "${!DEVICE_CONFIGS[@]}"; do
    source "${DEVICE_CONFIGS[$i]}"
    echo "  $((i+1))) $DEVICE_NAME  [$(basename ${DEVICE_CONFIGS[$i]})]"
done
echo ""
read -p "Select device [1-${#DEVICE_CONFIGS[@]}]: " DEV_CHOICE
DEVICE_CONF="${DEVICE_CONFIGS[$((${DEV_CHOICE:-1} - 1))]}"
source "$DEVICE_CONF"
echo ">>> Selected: $DEVICE_NAME"

# -------------------------------------------------------
# Step 4: Build configuration
# -------------------------------------------------------
echo "======================================================="
echo "   Build Configuration"
echo "======================================================="

read -p "Username [default: phone]: " USERNAME
USERNAME=${USERNAME:-phone}
read -s -p "Password [default: 1234]: " PASSWORD
echo ""; PASSWORD=${PASSWORD:-1234}

echo ""
echo "Ubuntu release:"
echo "1) noble    (24.04 LTS)"
echo "2) plucky   (25.04 — recommended)"
echo "3) resolute (26.04 beta — experimental)"
read -p "Choice [1-3, default 2]: " REL_CHOICE
case ${REL_CHOICE:-2} in
    1) UBUNTU_RELEASE="noble"    ;;
    3) UBUNTU_RELEASE="resolute" ;;
    *) UBUNTU_RELEASE="plucky"   ;;
esac
echo ">>> Release: $UBUNTU_RELEASE"

echo ""
echo "Build color (hostname: mobuntu-{color}):"
echo "  1) orange   2) pink    3) yellow  4) red"
echo "  5) blue     6) green   7) purple  8) cyan"
echo "  9) white   10) black  11) custom"
read -p "Choice [1-11, default 1]: " COLOR_CHOICE
case ${COLOR_CHOICE:-1} in
    1)  BUILD_COLOR="orange"  ;; 2)  BUILD_COLOR="pink"    ;;
    3)  BUILD_COLOR="yellow"  ;; 4)  BUILD_COLOR="red"     ;;
    5)  BUILD_COLOR="blue"    ;; 6)  BUILD_COLOR="green"   ;;
    7)  BUILD_COLOR="purple"  ;; 8)  BUILD_COLOR="cyan"    ;;
    9)  BUILD_COLOR="white"   ;; 10) BUILD_COLOR="black"   ;;
    11) read -p "Custom color: " CUSTOM_COLOR; BUILD_COLOR="${CUSTOM_COLOR:-custom}" ;;
    *)  BUILD_COLOR="orange"  ;;
esac
DEVICE_HOSTNAME="mobuntu-${BUILD_COLOR}"
echo ">>> Color: $BUILD_COLOR  Hostname: $DEVICE_HOSTNAME"

echo ""
echo "Display panel:"
echo "  1) Tianma (default)  2) EBBG"
read -p "Choice [1-2, default 1]: " PANEL_CHOICE
case ${PANEL_CHOICE:-1} in
    2) BOOT_DTB="sdm845-xiaomi-beryllium-ebbg.dtb"   ; BOOT_PANEL="ebbg"   ;;
    *) BOOT_DTB="sdm845-xiaomi-beryllium-tianma.dtb" ; BOOT_PANEL="tianma" ;;
esac
echo ">>> Panel: $BOOT_PANEL"

echo ""
read -p "RootFS size in GB [default: 12, min 8]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
[ "$IMG_INPUT" -lt 8 ] && IMAGE_SIZE=8 || IMAGE_SIZE=$IMG_INPUT

echo ""
read -p "Extra packages (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

BOOT_VERBOSE=false
AUTORESIZE=true
if [ "$DEBUG_MODE" = "false" ]; then
    echo ""
    echo "Boot verbosity:"
    echo "  1) Quiet / splash (default)  2) Verbose"
    read -p "Choice [1-2, default 1]: " BOOT_V
    [ "${BOOT_V:-1}" = "2" ] && BOOT_VERBOSE=true

    echo ""
    echo "Auto-resize rootfs on first boot?"
    echo "  1) Yes (recommended)  2) No"
    read -p "Choice [1-2, default 1]: " RESIZE_CHOICE
    [ "${RESIZE_CHOICE:-1}" = "2" ] && AUTORESIZE=false
fi

# -------------------------------------------------------
# Step 5: Stage firmware into mkosi.extra/
# -------------------------------------------------------
echo ">>> Staging firmware into mkosi.extra/..."
LOCAL_FW_DIR="${SCRIPT_DIR}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}"
LOCAL_FW_ARCHIVE="${LOCAL_FW_DIR}/firmware.tar.gz"
EXTRA_DIR="${SCRIPT_DIR}/mkosi.extra"

mkdir -p "${EXTRA_DIR}/etc/apt/sources.list.d" \
         "${EXTRA_DIR}/etc/apt/trusted.gpg.d" \
         "${EXTRA_DIR}/etc/systemd/system/hexagonrpcd.service.d" \
         "${EXTRA_DIR}/etc/modprobe.d" \
         "${EXTRA_DIR}/usr/lib/mobuntu" \
         "${EXTRA_DIR}/usr/share/initramfs-tools/hooks"

# mkosi.skeleton/ is copied before package install — used for Mobian GPG key + repo
SKELETON_DIR="${SCRIPT_DIR}/mkosi.skeleton"
mkdir -p "${SKELETON_DIR}/etc/apt/trusted.gpg.d"
mkdir -p "${SKELETON_DIR}/etc/apt/sources.list.d"
chmod 755 "${SKELETON_DIR}" \
          "${SKELETON_DIR}/etc" \
          "${SKELETON_DIR}/etc/apt" \
          "${SKELETON_DIR}/etc/apt/trusted.gpg.d" \
          "${SKELETON_DIR}/etc/apt/sources.list.d"

echo ">>> Fetching Mobian GPG key into mkosi.skeleton/..."
curl -fsSL https://repo.mobian.org/mobian.gpg \
    -o "${SKELETON_DIR}/etc/apt/trusted.gpg.d/mobian.gpg" 2>/dev/null || \
    echo ">>> WARNING: Could not fetch Mobian GPG key."

printf "deb [signed-by=/etc/apt/trusted.gpg.d/mobian.gpg] http://repo.mobian.org/ staging main non-free-firmware\n" \
    > "${SKELETON_DIR}/etc/apt/sources.list.d/mobian.list"

if [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>>   Extracting local firmware archive..."
    sudo tar -xzf "$LOCAL_FW_ARCHIVE" -C "$EXTRA_DIR/"
elif [ -n "$FIRMWARE_REPO" ]; then
    echo ">>>   Cloning firmware from $FIRMWARE_REPO..."
    FW_TMP=$(mktemp -d /tmp/fw_XXXX)
    if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>/dev/null; then
        [ -d "$FW_TMP/fw/lib" ] && sudo cp -r "$FW_TMP/fw/lib/." "$EXTRA_DIR/lib/"
        [ -d "$FW_TMP/fw/usr" ] && sudo cp -r "$FW_TMP/fw/usr/." "$EXTRA_DIR/usr/"
    else
        echo ">>>   WARNING: git clone failed."
    fi
    rm -rf "$FW_TMP"
fi

for f in 51-qcom.conf qcom-firmware q6voiced.conf 81-libssc.rules; do
    [ -f "$LOCAL_FW_DIR/$f" ] && \
        cp "$LOCAL_FW_DIR/$f" "${EXTRA_DIR}/usr/lib/mobuntu/$f" && \
        echo ">>>   Staged: $f"
done

printf '[Unit]\nAfter=multi-user.target\n' \
    > "${EXTRA_DIR}/etc/systemd/system/hexagonrpcd.service.d/ordering.conf"

echo ">>> Firmware and repo keys staged."

# -------------------------------------------------------
# Step 6: Download kernel payload
# -------------------------------------------------------
echo ">>> Downloading kernel payload..."
mkdir -p "${SCRIPT_DIR}/kernel_payload"
cd "${SCRIPT_DIR}/kernel_payload"

IMG_EXISTING=$(ls linux-image*.deb 2>/dev/null | head -n 1)
HDR_EXISTING=$(ls linux-headers*.deb 2>/dev/null | head -n 1)

if [ -n "$IMG_EXISTING" ] && [ -n "$HDR_EXISTING" ]; then
    echo ">>>   Found existing kernel payload, skipping download."
else
    POOL_URL="${KERNEL_REPO}"
    KERNEL_MAJOR_MINOR=$(echo "$KERNEL_VERSION_PIN" | grep -oE "^[0-9]+\.[0-9]+")
    SUBDIR_URL="${POOL_URL}linux-${KERNEL_MAJOR_MINOR}-${KERNEL_SERIES}/"
    wget -q --timeout=30 -U "Mozilla/5.0" -O pkg_index.html "$SUBDIR_URL" || true
    IMG_FILE=$(grep -oE "linux-image-[^_]+_${KERNEL_VERSION_PIN}-[^_]+_arm64\.deb" pkg_index.html | head -n 1)
    HDR_FILE=$(grep -oE "linux-headers-[^_]+_${KERNEL_VERSION_PIN}-[^_]+_arm64\.deb" pkg_index.html | head -n 1)
    [ -z "$IMG_FILE" ] && { echo "ERROR: Kernel not found."; rm -f pkg_index.html; exit 1; }
    wget --show-progress -U "Mozilla/5.0" -O linux-image.deb "${SUBDIR_URL}${IMG_FILE}"
    wget --show-progress -U "Mozilla/5.0" -O linux-headers.deb "${SUBDIR_URL}${HDR_FILE}"
    rm -f pkg_index.html
fi

mkdir -p "${SCRIPT_DIR}/mkosi.extra/tmp/kernel_payload"
cp linux-image*.deb linux-headers*.deb \
    "${SCRIPT_DIR}/mkosi.extra/tmp/kernel_payload/" 2>/dev/null || true
cd "${SCRIPT_DIR}"

# -------------------------------------------------------
# Step 7: Generate mkosi.conf
# -------------------------------------------------------
echo ">>> Generating mkosi.conf..."

FINALIZE_LINE=""
[ "$DEBUG_MODE" = "false" ] && FINALIZE_LINE="FinalizeScripts=mkosi.finalize"

cat > "${SCRIPT_DIR}/mkosi.conf" << EOF
# Mobuntu Orange — RC1-mkosi
# Generated by 1_preflight.sh — do not edit manually
# Debug mode: $DEBUG_MODE

[Distribution]
Distribution=ubuntu
Release=${UBUNTU_RELEASE}
Architecture=arm64
Mirror=http://ports.ubuntu.com/ubuntu-ports/

[Output]
Format=directory
OutputDirectory=output/
ImageId=mobuntu-${DEVICE_CODENAME}-${UBUNTU_RELEASE}
Bootable=no

[Content]
Packages=
    initramfs-tools
    sudo
    network-manager
    modemmanager
    linux-firmware
    bluez
    pipewire
    pipewire-pulse
    wireplumber
    hexagonrpcd
    qcom-phone-utils
    qrtr-tools
    rmtfs
    pd-mapper
    tqftpserv
    protection-domain-mapper
    openssh-server
    locales
    tzdata
    alsa-ucm-conf
    git
    build-essential
    curl
    ${EXTRA_PKG}

PrepareScripts=mkosi.prepare
PostInstallationScripts=mkosi.build
${FINALIZE_LINE}

[Build]
Environment=
    MOBUNTU_UBUNTU_RELEASE=${UBUNTU_RELEASE}
    MOBUNTU_USERNAME=${USERNAME}
    MOBUNTU_PASSWORD=${PASSWORD}
    MOBUNTU_DEVICE_HOSTNAME=${DEVICE_HOSTNAME}
    MOBUNTU_DEVICE_CODENAME=${DEVICE_CODENAME}
    MOBUNTU_DEVICE_BRAND=${DEVICE_BRAND}
    MOBUNTU_DEVICE_NAME=${DEVICE_NAME}
    MOBUNTU_DEVICE_PACKAGES=${DEVICE_PACKAGES}
    MOBUNTU_DEVICE_SERVICES=${DEVICE_SERVICES}
    MOBUNTU_DEVICE_IMAGE_LABEL=${DEVICE_IMAGE_LABEL}
    MOBUNTU_BUILD_COLOR=${BUILD_COLOR}
    MOBUNTU_BOOT_METHOD=${BOOT_METHOD}
    MOBUNTU_BOOT_DTB=${BOOT_DTB}
    MOBUNTU_BOOT_DTB_APPEND=${BOOT_DTB_APPEND}
    MOBUNTU_BOOT_VERBOSE=${BOOT_VERBOSE}
    MOBUNTU_AUTORESIZE=${AUTORESIZE}
    MOBUNTU_FIRMWARE_METHOD=${FIRMWARE_METHOD}
    MOBUNTU_FIRMWARE_REPO=${FIRMWARE_REPO}
    MOBUNTU_MKBOOTIMG_PAGESIZE=${MKBOOTIMG_PAGESIZE}
    MOBUNTU_MKBOOTIMG_BASE=${MKBOOTIMG_BASE}
    MOBUNTU_MKBOOTIMG_KERNEL_OFFSET=${MKBOOTIMG_KERNEL_OFFSET}
    MOBUNTU_MKBOOTIMG_RAMDISK_OFFSET=${MKBOOTIMG_RAMDISK_OFFSET}
    MOBUNTU_MKBOOTIMG_TAGS_OFFSET=${MKBOOTIMG_TAGS_OFFSET}
    MOBUNTU_IMAGE_SIZE=${IMAGE_SIZE}
    MOBUNTU_DEBUG=${DEBUG_MODE}
EOF

# -------------------------------------------------------
# Step 8: Save build.env
# -------------------------------------------------------
cat > "${SCRIPT_DIR}/build.env" << EOF
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
USERNAME="${USERNAME}"
DEVICE_NAME="${DEVICE_NAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_BRAND="${DEVICE_BRAND}"
DEVICE_IMAGE_LABEL="${DEVICE_IMAGE_LABEL}"
BUILD_COLOR="${BUILD_COLOR}"
BOOT_PANEL="${BOOT_PANEL}"
DEBUG_MODE="${DEBUG_MODE}"
DEVICE_CONF="${DEVICE_CONF}"
IMAGE_SIZE="${IMAGE_SIZE}"
EOF

echo ""
echo "======================================================="
echo "   Pre-Flight Complete — $DEVICE_NAME"
echo "   Release: $UBUNTU_RELEASE  Color: $BUILD_COLOR"
[ "$DEBUG_MODE" = "true" ] && \
    echo "   Mode: DEBUG (rootfs only)" || \
    echo "   Mode: FULL (rootfs + boot.img + root.img)"
echo ""
echo "   Next: bash 2_build.sh [phosh|plasma-mobile|both]"
echo "======================================================="
