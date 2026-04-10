#!/bin/bash
set -e
echo "======================================================="
echo "   [1/7] Pre-Flight & Workspace Setup"
echo "======================================================="

echo ">>> Checking and installing host dependencies..."
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap qemu-user-static qemu-system-aarch64 sudo e2fsprogs curl wget \
    xz-utils gzip zip ca-certificates file fdisk git python3 \
    python3-pip python3-venv sshpass tar kpartx dosfstools binfmt-support \
    uuid-runtime
	
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

# Give it a moment to register
sleep 1

# Verify - the file must exist AND not be empty
if [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
    echo ">>> systemd-binfmt failed, falling back to manual registration..."
    sudo update-binfmts --install qemu-aarch64 /usr/bin/qemu-aarch64-static \
        --magic '\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00' \
        --mask  '\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff' \
        --offset 0 --credentials yes --fix-binary yes
fi

# Hard stop if still not active
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
read -p "Enter desired username [default: ubuntu]: " USERNAME
USERNAME=${USERNAME:-ubuntu}

read -s -p "Enter desired password [default: ubuntu]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-ubuntu}

echo "Select Desktop/Mobile UI:"
echo "--- Mobile Shells (Touch-First) ---"
echo "1) Phosh (Purism GNOME + Squeekboard)"
echo "2) Plasma Mobile (KDE Mobile + Maliit)"
echo "--- Desktop Flavors (Tablet/PC) ---"
echo "3) GNOME Vanilla (ubuntu-desktop-minimal)"
echo "4) KDE Plasma Vanilla (kde-plasma-desktop)"
echo "5) Ubuntu Unity Vanilla (ubuntu-unity-desktop)"
echo "6) XFCE Vanilla (xubuntu-core)"
echo "7) Custom (Provide your own)"
read -p "Choice [1-7, default 1]: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}

case $UI_CHOICE in
    2) UI_PKG="plasma-mobile maliit-keyboard"; DM_PKG="sddm"; UI_NAME="plasma-mobile" ;;
    3) UI_PKG="ubuntu-desktop-minimal onboard"; DM_PKG="gdm3"; UI_NAME="gnome-vanilla" ;;
    4) UI_PKG="kde-plasma-desktop onboard"; DM_PKG="sddm"; UI_NAME="kde-vanilla" ;;
    5) UI_PKG="ubuntu-unity-desktop onboard"; DM_PKG="lightdm"; UI_NAME="unity-vanilla" ;;
    6) UI_PKG="xubuntu-core onboard"; DM_PKG="lightdm"; UI_NAME="xfce-vanilla" ;;
    7) read -p "Enter full core package name(s): " CUSTOM_PKG; read -p "Enter required Display Manager (gdm3, lightdm, sddm): " CUSTOM_DM; UI_PKG="$CUSTOM_PKG"; DM_PKG="$CUSTOM_DM"; UI_NAME="custom" ;;
    *) UI_PKG="phosh phosh-core phosh-mobile-settings squeekboard"; DM_PKG="gdm3"; UI_NAME="phosh" ;;
esac

echo ""
read -p "Enter desired RootFS image size in GB (Minimum 8) [default: 12]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
if [ "$IMG_INPUT" -lt 8 ]; then
    echo ">>> Forcing minimum size of 8GB."
    IMAGE_SIZE=8
else
    IMAGE_SIZE=$IMG_INPUT
fi

echo ""
read -p "Enter any EXTRA packages to install (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

cat << EOF_ENV > build.env
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
UI_PKG="$UI_PKG"
DM_PKG="$DM_PKG"
UI_NAME="$UI_NAME"
EXTRA_PKG="$EXTRA_PKG"
IMAGE_SIZE="$IMAGE_SIZE"
UBUNTU_RELEASE="noble"
EOF_ENV

echo ">>> Configuration locked and saved to build.env."
echo ">>> Pre-flight complete. Proceed to Script 2."
