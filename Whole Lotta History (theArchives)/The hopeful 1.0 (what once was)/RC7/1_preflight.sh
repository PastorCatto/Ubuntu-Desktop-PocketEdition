#!/bin/bash
set -e
echo "======================================================="
echo "   Mobuntu Orange - [1/7] Pre-Flight & Workspace Setup"
echo "======================================================="

echo ">>> Checking and installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap qemu-user-static qemu-system-aarch64 sudo e2fsprogs curl wget \
    xz-utils gzip zip ca-certificates file fdisk git python3 \
    python3-pip python3-venv sshpass tar kpartx dosfstools binfmt-support \
    uuid-runtime rsync

echo ">>> Installing standalone mkbootimg (replacing broken Ubuntu package)..."
sudo apt-get remove -y mkbootimg 2>/dev/null || true
sudo rm -rf /tmp/mkbootimg-tool
git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-tool
sed -i 's/-Werror//g' /tmp/mkbootimg-tool/libmincrypt/Makefile
make -C /tmp/mkbootimg-tool CFLAGS="-ffunction-sections -O3"
sudo cp /tmp/mkbootimg-tool/mkbootimg /usr/local/bin/mkbootimg
sudo chmod +x /usr/local/bin/mkbootimg
rm -rf /tmp/mkbootimg-tool
echo ">>> mkbootimg installed: $(mkbootimg --help 2>&1 | head -1)"

echo ">>> Activating QEMU binfmt handlers for arm64..."
sudo systemctl restart systemd-binfmt
sleep 1

if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
    echo ">>> systemd-binfmt failed, falling back to manual registration..."
    sudo update-binfmts --install qemu-aarch64 /usr/bin/qemu-aarch64-static \
        --magic '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00' \
        --mask  '\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff' \
        --offset 0 --credentials yes --fix-binary yes
fi

if ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
    echo ">>> ERROR: binfmt handler still not active. Cannot continue."
    exit 1
fi
echo ">>> binfmt handler confirmed active."

if [ ! -f /usr/bin/qemu-aarch64-static ]; then
    echo ">>> ERROR: /usr/bin/qemu-aarch64-static not found. Re-installing..."
    sudo apt-get install --reinstall qemu-user-static
fi

echo "======================================================="
echo "   Configuration Prompts"
echo "======================================================="

# --- Ubuntu Release Selection ---
echo ""
echo ">>> Querying available Ubuntu releases..."
RELEASE_DATA=""
if command -v python3 &>/dev/null; then
    RELEASE_DATA=$(curl -s --max-time 15 "https://api.launchpad.net/1.0/ubuntu/series" 2>/dev/null | \
    python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    statuses = ['Active Development', 'Current Stable Release', 'Supported', 'Pre-release Freeze']
    series = [(s['name'], s['version'], s['status']) for s in data['entries'] if s['status'] in statuses]
    series.sort(key=lambda x: x[1])
    for i, (name, ver, status) in enumerate(series, 1):
        dev = ' [DEV]' if 'Development' in status or 'Pre-release' in status else ''
        print(f'{i}:{name}:{ver}{dev}')
except:
    pass
" 2>/dev/null)
fi

if [ -z "$RELEASE_DATA" ]; then
    echo ">>> Could not reach Launchpad, using built-in release list."
    RELEASE_DATA="1:focal:20.04 LTS
2:jammy:22.04 LTS
3:noble:24.04 LTS
4:oracular:24.10
5:plucky:25.04
6:questing:25.10 [DEV]"
fi

echo "Available Ubuntu releases:"
echo "$RELEASE_DATA" | while IFS=: read -r num name version; do
    printf "  %s) %-12s (%s)\n" "$num" "$name" "$version"
done

NOBLE_IDX=$(echo "$RELEASE_DATA" | grep -n ":noble:" | cut -d: -f1)
NOBLE_IDX=${NOBLE_IDX:-3}

read -p "Choice [default: noble (#${NOBLE_IDX})]: " RELEASE_CHOICE
RELEASE_CHOICE=${RELEASE_CHOICE:-$NOBLE_IDX}

UBUNTU_RELEASE=$(echo "$RELEASE_DATA" | awk -F: "NR==${RELEASE_CHOICE} {print \$2}")
if [ -z "$UBUNTU_RELEASE" ]; then
    echo ">>> Invalid choice, defaulting to noble."
    UBUNTU_RELEASE="noble"
fi
UBUNTU_CODENAME="$UBUNTU_RELEASE"
ROOTFS_DIR="Mobuntu-${UBUNTU_CODENAME}"
echo ">>> Selected release : $UBUNTU_RELEASE"
echo ">>> RootFS directory : $ROOTFS_DIR"

# --- Device Selection ---
echo ""
echo "Select target device:"
echo "--- Qualcomm SDM845 Devices (supported by Mobian kernel) ---"
echo "1) Xiaomi Poco F1 (beryllium)       [SDM845] - default"
echo "2) OnePlus 6 (enchilada)            [SDM845]"
echo "3) OnePlus 6T (fajita)              [SDM845]"
echo "4) Xiaomi Mi 8 (dipper)             [SDM845]"
echo "5) Custom (enter your own device)"
read -p "Choice [1-5, default 1]: " DEVICE_CHOICE
DEVICE_CHOICE=${DEVICE_CHOICE:-1}

case $DEVICE_CHOICE in
    2)
        DEVICE_NAME="OnePlus 6"
        DEVICE_CODENAME="enchilada"
        DEVICE_DT_COMPAT="qcom,sdm845-oneplus-enchilada"
        ;;
    3)
        DEVICE_NAME="OnePlus 6T"
        DEVICE_CODENAME="fajita"
        DEVICE_DT_COMPAT="qcom,sdm845-oneplus-fajita"
        ;;
    4)
        DEVICE_NAME="Xiaomi Mi 8"
        DEVICE_CODENAME="dipper"
        DEVICE_DT_COMPAT="qcom,sdm845-xiaomi-dipper"
        ;;
    5)
        read -p "Enter device name (e.g. 'Xiaomi Poco F1'): " DEVICE_NAME
        read -p "Enter device codename (e.g. 'beryllium'): " DEVICE_CODENAME
        read -p "Enter DT compatible string (e.g. 'qcom,sdm845-xiaomi-beryllium'): " DEVICE_DT_COMPAT
        ;;
    *)
        DEVICE_NAME="Xiaomi Poco F1"
        DEVICE_CODENAME="beryllium"
        DEVICE_DT_COMPAT="qcom,sdm845-xiaomi-beryllium"
        ;;
esac
echo ">>> Device: $DEVICE_NAME ($DEVICE_CODENAME)"
echo ">>> DT compatible: $DEVICE_DT_COMPAT"

# --- Credentials ---
echo ""
read -p "Enter desired username [default: mobuntu]: " USERNAME
USERNAME=${USERNAME:-mobuntu}
read -s -p "Enter desired password [default: mobuntu]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-mobuntu}

# --- UI Selection ---
echo ""
echo "Select Desktop/Mobile UI:"
echo "--- Mobile Shells (Touch-First) ---"
echo "1) Phosh (GNOME Mobile + phosh-osk-stub)"
echo "2) Plasma Mobile (KDE Mobile + Maliit)"
echo "--- Desktop Flavors ---"
echo "3) GNOME Vanilla (ubuntu-desktop-minimal)"
echo "4) KDE Plasma (kde-plasma-desktop)"
echo "5) Ubuntu Unity (ubuntu-unity-desktop)"
echo "6) XFCE (xubuntu-core)"
echo "7) Custom (provide your own packages)"
read -p "Choice [1-7, default 1]: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}

case $UI_CHOICE in
    # phosh-mobile-settings and phosh-core are NOT in Ubuntu repos
    # phosh-osk-stub is the reliable Ubuntu-available OSK
    1) UI_PKG="phosh phosh-osk-stub"; DM_PKG="gdm3"; UI_NAME="phosh" ;;
    2) UI_PKG="plasma-mobile maliit-keyboard"; DM_PKG="sddm"; UI_NAME="plasma-mobile" ;;
    3) UI_PKG="ubuntu-desktop-minimal onboard"; DM_PKG="gdm3"; UI_NAME="gnome-vanilla" ;;
    4) UI_PKG="kde-plasma-desktop onboard"; DM_PKG="sddm"; UI_NAME="kde-vanilla" ;;
    5) UI_PKG="ubuntu-unity-desktop onboard"; DM_PKG="lightdm"; UI_NAME="unity-vanilla" ;;
    6) UI_PKG="xubuntu-core onboard"; DM_PKG="lightdm"; UI_NAME="xfce-vanilla" ;;
    7)
        read -p "Enter package name(s): " CUSTOM_PKG
        read -p "Enter display manager (gdm3/lightdm/sddm): " CUSTOM_DM
        UI_PKG="$CUSTOM_PKG"; DM_PKG="$CUSTOM_DM"; UI_NAME="custom"
        ;;
esac

# --- Image Size ---
echo ""
read -p "Enter desired RootFS image size in GB (minimum 8) [default: 12]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
if [ "$IMG_INPUT" -lt 8 ] 2>/dev/null; then
    echo ">>> Forcing minimum size of 8GB."
    IMAGE_SIZE=8
else
    IMAGE_SIZE=$IMG_INPUT
fi

# --- Extra Packages ---
echo ""
read -p "Enter any EXTRA packages to install (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

# --- Save build.env ---
cat > build.env << EOF_ENV
# Mobuntu Orange build configuration
# Generated by 1_preflight.sh on $(date)

USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"

UBUNTU_RELEASE="${UBUNTU_RELEASE}"
UBUNTU_CODENAME="${UBUNTU_CODENAME}"
ROOTFS_DIR="${ROOTFS_DIR}"

DEVICE_NAME="${DEVICE_NAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_DT_COMPAT="${DEVICE_DT_COMPAT}"

UI_PKG="${UI_PKG}"
DM_PKG="${DM_PKG}"
UI_NAME="${UI_NAME}"
EXTRA_PKG="${EXTRA_PKG}"

IMAGE_SIZE="${IMAGE_SIZE}"
EOF_ENV

echo ">>> Configuration saved to build.env."

# --- Generate droid-juicer configs ---
echo ""
echo ">>> Generating droid-juicer firmware extraction configs..."
mkdir -p droid-juicer-configs

# Generate config for the selected device
# For beryllium we generate both panel variants since DT compat differs per panel
generate_dj_config() {
    local COMPAT="$1"
    cat > "droid-juicer-configs/${COMPAT}.toml" << DJ_EOF
# Mobuntu Orange droid-juicer config
# Device: ${DEVICE_NAME} (${DEVICE_CODENAME})
# DT compatible: ${COMPAT}
# Auto-generated by 1_preflight.sh on $(date)
#
# This service runs on first boot and extracts signed firmware from
# the Android vendor partition into /lib/firmware.
# NOTE: Verify firmware paths match your device's vendor partition layout.

[juicer]
firmware = [
    # Adreno 630 GPU firmware (signed blobs from vendor partition)
    { partition = "vendor", origin = "firmware", destination = "qcom/sdm845", files = [
        { name = "a630_zap.mbn" },
        { name = "adsp.mbn" },
        { name = "cdsp.mbn" },
        { name = "mba.mbn" },
        { name = "modem.mbn" },
        { name = "wlanmdsp.mbn" },
    ]},
    # WiFi ath10k WCN3990 firmware
    { partition = "vendor", origin = "firmware", destination = "ath10k/WCN3990/hw1.0", files = [
        { name = "firmware-5.bin" },
        { name = "board-2.bin" },
    ]},
    # Adreno GPU microcode (non-signed, universal)
    { partition = "vendor", origin = "firmware", destination = "qcom", files = [
        { name = "a630_sqe.fw" },
        { name = "a630_gmu.bin" },
    ]},
    # Venus video codec firmware
    { partition = "vendor", origin = "firmware", destination = "qcom/venus-5.2", files = [
        { name = "venus.mbn" },
    ]},
]
DJ_EOF
    echo ">>>   Written: droid-juicer-configs/${COMPAT}.toml"
}

if [ "$DEVICE_CODENAME" = "beryllium" ]; then
    # Poco F1 has two panel variants with different DT compatibles
    generate_dj_config "qcom,sdm845-xiaomi-beryllium"
    generate_dj_config "qcom,sdm845-xiaomi-beryllium-ebbg"
else
    generate_dj_config "$DEVICE_DT_COMPAT"
fi

echo ">>> droid-juicer configs written to ./droid-juicer-configs/"
echo ">>> NOTE: Verify firmware filenames match your device's vendor partition."
echo ""
echo "======================================================="
echo "   Mobuntu Orange Pre-Flight Complete"
echo "   Release  : $UBUNTU_RELEASE  |  RootFS: $ROOTFS_DIR"
echo "   Device   : $DEVICE_NAME ($DEVICE_CODENAME)"
echo "   UI       : $UI_NAME"
echo "======================================================="
echo ">>> Proceed to Script 2 (Kernel Payload Staging)."
