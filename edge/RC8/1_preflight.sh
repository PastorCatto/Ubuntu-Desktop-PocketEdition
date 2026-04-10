#!/bin/bash
set -e
echo "======================================================="
echo "   Mobuntu Orange — [1/5] Pre-Flight & Workspace Setup"
echo "======================================================="

echo ">>> Checking and installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap qemu-user-static sudo e2fsprogs curl wget \
    xz-utils gzip zip ca-certificates file git python3 \
    binfmt-support uuid-runtime android-sdk-libsparse-utils \
    rsync dosfstools

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

echo ">>> Activating QEMU binfmt handlers for arm64..."
sudo systemctl restart systemd-binfmt 2>/dev/null || true
sleep 1

if ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
    echo ">>> Falling back to manual binfmt registration..."
    sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
fi

if ! grep -q "enabled" /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
    echo ">>> ERROR: binfmt handler still not active. Cannot continue."
    exit 1
fi
echo ">>> binfmt handler confirmed active."

if [ ! -f /usr/bin/qemu-aarch64-static ]; then
    echo ">>> qemu-aarch64-static missing, reinstalling..."
    sudo apt-get install --reinstall qemu-user-static
fi

echo "======================================================="
echo "   Configuration"
echo "======================================================="

read -p "Username [default: phone]: " USERNAME
USERNAME=${USERNAME:-phone}

read -s -p "Password [default: 1234]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-1234}

echo ""
echo "Ubuntu release:"
echo "1) noble    (24.04 LTS, recommended)"
echo "2) oracular (24.10)"
echo "3) plucky   (25.04)"
read -p "Choice [1-3, default 1]: " REL_CHOICE
REL_CHOICE=${REL_CHOICE:-1}
case $REL_CHOICE in
    2) UBUNTU_RELEASE="oracular" ;;
    3) UBUNTU_RELEASE="plucky"   ;;
    *) UBUNTU_RELEASE="noble"    ;;
esac
echo ">>> Using Ubuntu release: $UBUNTU_RELEASE"

echo ""
read -p "RootFS image size in GB [default: 12, min 8]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
if [ "$IMG_INPUT" -lt 8 ]; then
    echo ">>> Forcing minimum 8GB."
    IMAGE_SIZE=8
else
    IMAGE_SIZE=$IMG_INPUT
fi

echo ""
read -p "Extra packages (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

ROOTFS_DIR="mobuntu-${UBUNTU_RELEASE}"

cat > build.env << EOF
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
ROOTFS_DIR="${ROOTFS_DIR}"
IMAGE_SIZE="${IMAGE_SIZE}"
EXTRA_PKG="${EXTRA_PKG}"
EOF

echo ""
echo ">>> Configuration saved to build.env."
echo ">>> Pre-flight complete. Proceed to script 2."
