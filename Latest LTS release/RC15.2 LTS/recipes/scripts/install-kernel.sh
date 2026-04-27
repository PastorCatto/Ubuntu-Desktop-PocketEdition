#!/bin/bash
# Mobuntu RC15 — install-kernel.sh
# Runs inside chroot.
# Env: KERNEL_METHOD, KERNEL_REPO, KERNEL_SERIES, KERNEL_VERSION_PIN, BOOT_METHOD
set -e
export DEBIAN_FRONTEND=noninteractive

echo ">>> Installing kernel (method: $KERNEL_METHOD, series: $KERNEL_SERIES)"

case "$KERNEL_METHOD" in
mobian)
    PKG="linux-image-${KERNEL_SERIES}"
    if [ -n "$KERNEL_VERSION_PIN" ]; then
        echo ">>> Pinning kernel to $KERNEL_VERSION_PIN"
        # Try pinned version, fall back to latest if unavailable
        apt-get install -y "${PKG}=${KERNEL_VERSION_PIN}-1" 2>/dev/null || \
            apt-get install -y "${PKG}=${KERNEL_VERSION_PIN}" 2>/dev/null || \
            apt-get install -y "$PKG"
    else
        apt-get install -y "$PKG"
    fi
    ;;
custom_url)
    if [ -z "$KERNEL_REPO" ]; then
        echo ">>> ERROR: KERNEL_METHOD=custom_url but KERNEL_REPO is empty."
        echo ">>>        Set KERNEL_REPO in the device config and rebuild."
        exit 1
    fi
    echo ">>> Downloading kernel from: $KERNEL_REPO"
    TMP_DEB=$(mktemp /tmp/kernel-XXXX.deb)
    curl -fsSL -o "$TMP_DEB" "$KERNEL_REPO"
    dpkg -i "$TMP_DEB" || apt-get install -f -y
    rm -f "$TMP_DEB"
    ;;
*)
    echo ">>> ERROR: Unknown KERNEL_METHOD '$KERNEL_METHOD'"
    exit 1
    ;;
esac

echo ">>> Updating initramfs..."
update-initramfs -c -k all

# Build mkbootimg natively (ARM64) — only needed for mkbootimg boot method
if [ "$BOOT_METHOD" = "mkbootimg" ]; then
    echo ">>> Building mkbootimg natively for ARM64..."
    apt-get install -y git build-essential
    rm -rf /tmp/mkbootimg-build
    git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-build
    sed -i 's/-Werror//g' /tmp/mkbootimg-build/Makefile
    sed -i 's/-Werror//g' /tmp/mkbootimg-build/libmincrypt/Makefile
    make -C /tmp/mkbootimg-build
    cp /tmp/mkbootimg-build/mkbootimg /usr/local/bin/mkbootimg
    cp /tmp/mkbootimg-build/unpackbootimg /usr/local/bin/unpackbootimg
    chmod +x /usr/local/bin/mkbootimg /usr/local/bin/unpackbootimg
    rm -rf /tmp/mkbootimg-build
    echo ">>> mkbootimg (ARM64 native) installed."
fi
