#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    echo "Usage: $0 -d <device> [-s <suite>] [-i] [-h]"
    echo ""
    echo "  -d  Device codename (e.g. beryllium, fajita)"
    echo "  -s  Ubuntu suite override (default: from device.conf)"
    echo "  -i  Image only — skip rootfs build, reuse existing tarball"
    echo "  -h  This help text"
    echo ""
    echo "Available devices:"
    for d in "$SCRIPT_DIR/devices"/*/; do
        codename="$(basename "$d")"
        conf="$d/device.conf"
        if [ -f "$conf" ]; then
            # shellcheck disable=SC1090
            source "$conf"
            echo "  $codename — $DEVICE_MODEL ($DEVICE_BRAND)"
        fi
    done
    exit 1
}

DEVICE=""
SUITE_OVERRIDE=""
IMAGE_ONLY=0

while getopts "d:s:ih" opt; do
    case $opt in
        d) DEVICE="$OPTARG" ;;
        s) SUITE_OVERRIDE="$OPTARG" ;;
        i) IMAGE_ONLY=1 ;;
        h) usage ;;
        *) usage ;;
    esac
done

[ -z "$DEVICE" ] && { echo "ERROR: Device required. Use -d <codename>"; usage; }

DEVICE_CONF="$SCRIPT_DIR/devices/$DEVICE/device.conf"
[ -f "$DEVICE_CONF" ] || {
    echo "ERROR: No device config found at $DEVICE_CONF"
    echo "Available devices: $(ls "$SCRIPT_DIR/devices/")"
    exit 1
}

# Load device config
# shellcheck disable=SC1090
source "$DEVICE_CONF"

SUITE="${SUITE_OVERRIDE:-${DEVICE_SUITE:-plucky}}"

# ── Suite warning gate ──────────────────────────────────────────────────────
if [ "$SUITE" = "resolute" ]; then
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│  WARNING: Ubuntu 26.04 'resolute' has known SDM845 regressions │"
    echo "│  WiFi, Bluetooth, and audio are affected on most devices.       │"
    echo "│  Recommended suite: plucky (25.04)                              │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo ""
    read -rp "Type YES to confirm resolute: " confirm1
    [ "$confirm1" = "YES" ] || { echo "Aborted."; exit 1; }
    read -rp "Type RESOLUTE to confirm again: " confirm2
    [ "$confirm2" = "RESOLUTE" ] || { echo "Aborted."; exit 1; }
    echo ""
fi

# ── Validate required device vars ──────────────────────────────────────────
: "${FW_ARCHIVE_URL:?device.conf missing FW_ARCHIVE_URL}"
: "${KERNEL_IMAGE_URL:?device.conf missing KERNEL_IMAGE_URL}"
: "${KERNEL_HEADERS_URL:?device.conf missing KERNEL_HEADERS_URL}"
: "${KERNEL_VERSION:?device.conf missing KERNEL_VERSION}"

# ── Output filenames ────────────────────────────────────────────────────────
IMG_FILE="mobuntu-${DEVICE}-$(date +%Y%m%d).img"
ROOTFS_FILE="mobuntu-rootfs-${DEVICE}.tar.gz"

echo "=== Mobuntu Build ==="
echo "  Device  : $DEVICE_MODEL ($DEVICE_CODENAME)"
echo "  Suite   : $SUITE"
echo "  Kernel  : $KERNEL_VERSION"
echo "  Output  : $IMG_FILE"
echo ""

# ── Debos args ─────────────────────────────────────────────────────────────
export PATH=/sbin:/usr/sbin:$PATH

DEBOS_ARGS="--disable-fakemachine --scratchsize=10G"

DEBOS_VARS=(
    -t "device:${DEVICE}"
    -t "suite:${SUITE}"
    -t "image:${IMG_FILE}"
    -t "rootfs:${ROOTFS_FILE}"
    -t "fw_archive:${FW_ARCHIVE_URL}"
    -t "kernel_image:${KERNEL_IMAGE_URL}"
    -t "kernel_headers:${KERNEL_HEADERS_URL}"
    -t "kernel_version:${KERNEL_VERSION}"
)

cd "$SCRIPT_DIR"

if [ "$IMAGE_ONLY" -eq 0 ]; then
    echo "── Stage 1: rootfs ──"
    # shellcheck disable=SC2086
    debos $DEBOS_ARGS "${DEBOS_VARS[@]}" rootfs.yaml || exit 1
fi

echo "── Stage 2: image ──"
# shellcheck disable=SC2086
debos $DEBOS_ARGS "${DEBOS_VARS[@]}" image.yaml

echo ""
echo "Build complete: $IMG_FILE"
echo "Flashable rootfs: root-$IMG_FILE"
