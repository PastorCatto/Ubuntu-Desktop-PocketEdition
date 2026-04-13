#!/bin/bash
set -e
echo "======================================================="
echo "   Mobuntu Orange — [1/5] Pre-Flight & Workspace Setup"
echo "======================================================="

# -------------------------------------------------------
# Step 1: Host architecture detection
# -------------------------------------------------------
HOST_ARCH=$(uname -m)
echo ">>> Host architecture: $HOST_ARCH"

if [ "$HOST_ARCH" = "aarch64" ]; then
    echo ">>> ARM64 host detected — QEMU not required."
    HOST_IS_ARM64=true
else
    echo ">>> x86-64 host detected — QEMU required for arm64 chroot."
    HOST_IS_ARM64=false
fi

# -------------------------------------------------------
# Step 2: Host dependencies
# -------------------------------------------------------
echo ">>> Installing host dependencies..."
sudo apt-get update

if [ "$HOST_IS_ARM64" = "true" ]; then
    # ARM64 host — no QEMU needed
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y         debootstrap sudo e2fsprogs curl wget make gcc        xz-utils gzip zip ca-certificates file git python3         uuid-runtime android-sdk-libsparse-utils rsync dosfstools
else
    # x86-64 host — QEMU required
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y         debootstrap qemu-user-binfmt-hwe sudo e2fsprogs curl wget make gcc         xz-utils gzip zip ca-certificates file git python3         uuid-runtime android-sdk-libsparse-utils         rsync dosfstools
fi

# Ensure debootstrap knows about resolute (26.04)
if [ ! -f /usr/share/debootstrap/scripts/resolute ]; then
    echo ">>> Adding resolute suite to debootstrap..."
    sudo ln -sf /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/resolute
fi

echo ">>> Building mkbootimg from source (osm0sis fork)..."
sudo apt-get remove -y mkbootimg 2>/dev/null || true
sudo rm -rf /tmp/mkbootimg-tool
git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-tool
sed -i 's/-Werror//g' /tmp/mkbootimg-tool/libmincrypt/Makefile
make -C /tmp/mkbootimg-tool CFLAGS="-ffunction-sections -O3"
sudo cp /tmp/mkbootimg-tool/mkbootimg /usr/local/bin/mkbootimg
sudo chmod +x /usr/local/bin/mkbootimg
rm -rf /tmp/mkbootimg-tool
echo ">>> mkbootimg ready."

# -------------------------------------------------------
# Step 3: QEMU binfmt setup (x86-64 hosts only)
# -------------------------------------------------------
if [ "$HOST_IS_ARM64" = "false" ]; then
    echo ">>> Activating QEMU binfmt for arm64..."
    sudo systemctl restart systemd-binfmt 2>/dev/null || true
    sleep 1

    if ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
        sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
        printf ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F' | sudo tee /proc/sys/fs/binfmt_misc/register 2>/dev/null || true
    fi
    if ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
        echo ">>> ERROR: binfmt handler still not active."
        exit 1
    fi
    echo ">>> binfmt confirmed active."

    if [ ! -f /usr/bin/qemu-aarch64-static ]; then
        sudo apt-get install --reinstall qemu-user-binfmt-hwe
    fi
else
    echo ">>> Skipping QEMU setup (not needed on arm64 host)."
fi

# -------------------------------------------------------
# Step 2: Device selection
# -------------------------------------------------------
echo "======================================================="
echo "   Device Selection"
echo "======================================================="

DEVICES_DIR="$(dirname "$0")/devices"
if [ ! -d "$DEVICES_DIR" ]; then
    echo ">>> ERROR: devices/ directory not found next to this script."
    exit 1
fi

mapfile -t DEVICE_CONFIGS < <(ls "$DEVICES_DIR"/*.conf 2>/dev/null | sort)
if [ ${#DEVICE_CONFIGS[@]} -eq 0 ]; then
    echo ">>> ERROR: No device configs found in $DEVICES_DIR"
    exit 1
fi

echo "Available devices:"
for i in "${!DEVICE_CONFIGS[@]}"; do
    source "${DEVICE_CONFIGS[$i]}"
    echo "  $((i+1))) $DEVICE_NAME  [$(basename ${DEVICE_CONFIGS[$i]})]"
done

echo ""
read -p "Select device [1-${#DEVICE_CONFIGS[@]}]: " DEV_CHOICE
DEV_CHOICE=${DEV_CHOICE:-1}
DEV_IDX=$((DEV_CHOICE - 1))

if [ $DEV_IDX -lt 0 ] || [ $DEV_IDX -ge ${#DEVICE_CONFIGS[@]} ]; then
    echo ">>> ERROR: Invalid device selection."
    exit 1
fi

DEVICE_CONF="${DEVICE_CONFIGS[$DEV_IDX]}"
source "$DEVICE_CONF"
echo ">>> Selected: $DEVICE_NAME"

# -------------------------------------------------------
# Step 3: Build configuration
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
echo "1) noble    (24.04 LTS Not Supported: hexagonrpcd missing)"
echo "2) oracular (24.10 Not Supported: hexagonrpcd missing)"
echo "3) resolute (26.04 beta, recommended — 25.04 is EOL)"
echo "4) quill    (26.04 stable — NOT YET RELEASED, disabled)"
read -p "Choice [1-4, default 3]: " REL_CHOICE
REL_CHOICE=${REL_CHOICE:-3}
case $REL_CHOICE in
    1) UBUNTU_RELEASE="noble"    ;;
    2) UBUNTU_RELEASE="oracular" ;;
    3)
        UBUNTU_RELEASE="resolute"
        echo ""
        echo "======================================================="
        echo "  NOTE: Ubuntu 26.04 (resolute/beta) is the recommended"
        echo "  choice. Packages may occasionally change without"
        echo "  notice as the release approaches."
        echo "======================================================="
        ;;
    4)
        echo ">>> Ubuntu 26.04 stable (resolute) is not yet released."
        echo ">>> Falling back to resolute beta."
        UBUNTU_RELEASE="resolute"
        ;;
    *) UBUNTU_RELEASE="resolute" ;;
esac

echo ""
read -p "RootFS size in GB [default: 12, min 8]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
if [ "$IMG_INPUT" -lt 8 ]; then IMAGE_SIZE=8; else IMAGE_SIZE=$IMG_INPUT; fi

echo ""
read -p "Extra packages (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

echo ""
echo "UI / Desktop environment:"
echo "1) Phosh              (mobile-first, recommended for phones)"
echo "2) Ubuntu Desktop     (ubuntu-desktop-minimal, touch-friendly GNOME)"
echo "3) Unity              (ubuntu-unity-desktop)"
echo "4) Plasma Desktop     (kde-plasma-desktop, tablet/desktop)"
echo "5) Plasma Mobile      (plasma-mobile, touch-first KDE)"
echo "6) Lomiri             (Ubuntu Touch shell — experimental)"
read -p "Choice [1-6, default 1]: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}

case $UI_CHOICE in
    2)
        UI_NAME="ubuntu-desktop-minimal"
        UI_PACKAGES="ubuntu-desktop-minimal"
        UI_DM="gdm3"
        UI_EXTRA_REPOS=""
        ;;
    3)
        UI_NAME="unity"
        UI_PACKAGES="ubuntu-unity-desktop"
        UI_DM="lightdm"
        UI_EXTRA_REPOS=""
        ;;
    4)
        UI_NAME="plasma-desktop"
        UI_PACKAGES="kde-plasma-desktop"
        UI_DM="sddm"
        UI_EXTRA_REPOS=""
        ;;
    5)
        UI_NAME="plasma-mobile"
        UI_PACKAGES="plasma-mobile maliit-keyboard"
        UI_DM="sddm"
        UI_EXTRA_REPOS=""
        ;;
    6)
        echo ""
        echo "======================================================="
        echo "  WARNING: Lomiri (Ubuntu Touch shell) is experimental."
        echo "  It may not fully function on this device or Ubuntu"
        echo "  release. Proceed only if you know what you are doing."
        echo "======================================================="
        read -p "Continue with Lomiri? [y/N]: " LOMIRI_CONFIRM
        if [[ ! "$LOMIRI_CONFIRM" =~ ^[Yy]$ ]]; then
            echo ">>> Falling back to Phosh."
            UI_CHOICE=1
            UI_NAME="phosh"
            UI_PACKAGES="phosh phosh-osk-stub"
            UI_DM="greetd"
            UI_EXTRA_REPOS="mobian"
        else
            UI_NAME="lomiri"
            UI_PACKAGES="lomiri lomiri-osk-stub"
            UI_DM="greetd"
            UI_EXTRA_REPOS="mobian"
        fi
        ;;
    *)
        UI_NAME="phosh"
        UI_PACKAGES="phosh phosh-osk-stub"
        UI_DM="greetd"
        UI_EXTRA_REPOS="mobian"
        ;;
esac
echo ">>> UI: $UI_NAME  DM: $UI_DM"

ROOTFS_DIR="mobuntu-${DEVICE_CODENAME}-${UBUNTU_RELEASE}"

# -------------------------------------------------------
# Step 4: Save build.env
# -------------------------------------------------------
cat > build.env << EOF
# Mobuntu Orange — build configuration
# Generated by 1_preflight.sh

HOST_ARCH="${HOST_ARCH}"
HOST_IS_ARM64="${HOST_IS_ARM64}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
ROOTFS_DIR="${ROOTFS_DIR}"
IMAGE_SIZE="${IMAGE_SIZE}"
EXTRA_PKG="${EXTRA_PKG}"
DEVICE_CONF="${DEVICE_CONF}"

# Device info (sourced from ${DEVICE_CONF})
DEVICE_NAME="${DEVICE_NAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_BRAND="${DEVICE_BRAND}"
DEVICE_ARCH="${DEVICE_ARCH}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME}"
DEVICE_IMAGE_LABEL="${DEVICE_IMAGE_LABEL}"
DEVICE_PACKAGES="${DEVICE_PACKAGES}"

UI_NAME="${UI_NAME}"
UI_PACKAGES="${UI_PACKAGES}"
UI_DM="${UI_DM}"
UI_EXTRA_REPOS="${UI_EXTRA_REPOS}"
DEVICE_SERVICES="${DEVICE_SERVICES}"
DEVICE_QUIRKS="${DEVICE_QUIRKS}"

KERNEL_METHOD="${KERNEL_METHOD}"
KERNEL_REPO="${KERNEL_REPO}"
KERNEL_SERIES="${KERNEL_SERIES}"

BOOT_METHOD="${BOOT_METHOD}"
MKBOOTIMG_PAGESIZE="${MKBOOTIMG_PAGESIZE}"
MKBOOTIMG_BASE="${MKBOOTIMG_BASE}"
MKBOOTIMG_KERNEL_OFFSET="${MKBOOTIMG_KERNEL_OFFSET}"
MKBOOTIMG_RAMDISK_OFFSET="${MKBOOTIMG_RAMDISK_OFFSET}"
MKBOOTIMG_TAGS_OFFSET="${MKBOOTIMG_TAGS_OFFSET}"
BOOT_DTB_APPEND="${BOOT_DTB_APPEND}"
BOOT_DTB="${BOOT_DTB}"
BOOT_PANEL_PICKER="${BOOT_PANEL_PICKER}"
UBOOT_URL="${UBOOT_URL}"
UEFI_URL="${UEFI_URL}"
UEFI_ESP_SIZE_MB="${UEFI_ESP_SIZE_MB}"

FIRMWARE_METHOD="${FIRMWARE_METHOD}"
FIRMWARE_REPO="${FIRMWARE_REPO}"
FIRMWARE_INSTALL_PATH="${FIRMWARE_INSTALL_PATH}"
EOF

echo ""
echo ">>> Configuration saved to build.env."
echo ""

# -------------------------------------------------------
# Step 5: Optional auto-run
# -------------------------------------------------------
echo "======================================================="
echo "   Auto-Run"
echo "======================================================="
echo "Run scripts 2 and 3 automatically now?"
echo "1) Yes — fetch kernel then build rootfs"
echo "2) No  — stop here, run manually"
read -p "Choice [1-2, default 2]: " AUTO_RUN
AUTO_RUN=${AUTO_RUN:-2}

SCRIPT_DIR="$(dirname "$0")"

if [ "$AUTO_RUN" = "1" ]; then
    echo ">>> Starting auto-run: script 2..."
    bash "$SCRIPT_DIR/2_kernel_prep.sh"
    echo ">>> Script 2 complete. Starting script 3..."
    bash "$SCRIPT_DIR/3_rootfs_cooker.sh"
    echo ">>> Auto-run complete. Run script 5 to seal and flash."
else
    echo ">>> Stopped. Run scripts manually in order: 2 → 3 → 5"
fi