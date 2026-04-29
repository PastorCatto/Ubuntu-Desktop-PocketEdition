#!/bin/bash
# Mobuntu — extract-ubports-pdk.sh
# Downloads the UBports PDK ARM64 raw image and extracts the rootfs
# to base-ubports-noble.tar.gz for use by base-ubports.yaml.
#
# Called from 1_preflight_ubports.sh.
# Requires: wget, xz-utils, util-linux (losetup/partx), tar
#
# Output: ${OUTPUT_DIR}/base-ubports-noble.tar.gz

set -euo pipefail

PDK_URL="https://ci.ubports.com/job/ubuntu-touch-rootfs/job/main/lastSuccessfulBuild/artifact/ubuntu-touch-pdk-img-arm64.raw.xz"
PDK_XZ="ubuntu-touch-pdk-img-arm64.raw.xz"
PDK_RAW="ubuntu-touch-pdk-img-arm64.raw"
OUTPUT_TARBALL="${OUTPUT_DIR:-$(pwd)}/base-ubports-noble.tar.gz"
WORK_DIR=$(mktemp -d /tmp/mobuntu-pdk-XXXX)
MOUNT_DIR=$(mktemp -d /tmp/mobuntu-pdk-mnt-XXXX)

trap 'cleanup' EXIT

cleanup() {
    mountpoint -q "$MOUNT_DIR" && sudo umount "$MOUNT_DIR" 2>/dev/null || true
    [ -n "${LOOP_DEV:-}" ] && sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    rm -rf "$WORK_DIR" "$MOUNT_DIR"
}

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
die()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

echo "======================================================="
echo "   Mobuntu — UBports PDK Extractor"
echo "======================================================="

# ── Step 1: Download ──────────────────────────────────────
cd "$WORK_DIR"

if [ -f "${OUTPUT_DIR:-$(pwd)}/${PDK_XZ}" ]; then
    info "Cached PDK image found — skipping download."
    cp "${OUTPUT_DIR:-$(pwd)}/${PDK_XZ}" .
else
    info "Downloading UBports PDK ARM64 image..."
    info "Source: $PDK_URL"
    wget --progress=bar:force -O "$PDK_XZ" "$PDK_URL" || \
        die "Download failed. Check network and URL."
    # Cache it next to the output tarball for future runs
    cp "$PDK_XZ" "${OUTPUT_DIR:-$(pwd)}/" 2>/dev/null || true
fi
ok "Download complete: $(du -sh $PDK_XZ | cut -f1)"

# ── Step 2: Decompress ────────────────────────────────────
info "Decompressing .xz image..."
xz -d --keep "$PDK_XZ"
[ -f "$PDK_RAW" ] || die "Decompression failed — raw image not found."
ok "Decompressed: $(du -sh $PDK_RAW | cut -f1)"

# ── Step 3: Inspect partitions ────────────────────────────
info "Inspecting partition table..."
fdisk -l "$PDK_RAW" 2>/dev/null || true

# Find the Linux root partition (largest Linux filesystem partition)
ROOT_PART_LINE=$(fdisk -l "$PDK_RAW" 2>/dev/null | \
    grep "Linux filesystem" | \
    awk '{print NR, $0}' | sort -k5 -rn | head -1 | cut -d' ' -f2-)

if [ -z "$ROOT_PART_LINE" ]; then
    # Fallback: try first partition
    ROOT_PART_LINE=$(fdisk -l "$PDK_RAW" 2>/dev/null | \
        grep "^${PDK_RAW}" | head -1)
fi

[ -z "$ROOT_PART_LINE" ] && die "Could not find root partition in image."

ROOT_START=$(echo "$ROOT_PART_LINE" | awk '{print $2}')
SECTOR_SIZE=512
ROOT_OFFSET=$((ROOT_START * SECTOR_SIZE))
info "Root partition start sector: $ROOT_START (offset: ${ROOT_OFFSET} bytes)"

# ── Step 4: Mount ─────────────────────────────────────────
info "Mounting root partition..."

# Try losetup -P first (cleaner, partx-aware)
LOOP_DEV=$(sudo losetup -f --show -P "$PDK_RAW" 2>/dev/null) && {
    # Find the root partition device
    ROOT_DEV=""
    for part in "${LOOP_DEV}p"*; do
        [ -b "$part" ] || continue
        FSTYPE=$(sudo blkid -o value -s TYPE "$part" 2>/dev/null || true)
        if [ "$FSTYPE" = "ext4" ] || [ "$FSTYPE" = "btrfs" ]; then
            ROOT_DEV="$part"
            break
        fi
    done
    if [ -n "$ROOT_DEV" ]; then
        sudo mount -o ro "$ROOT_DEV" "$MOUNT_DIR"
        ok "Mounted via losetup -P: $ROOT_DEV"
    else
        sudo losetup -d "$LOOP_DEV"
        LOOP_DEV=""
    fi
} || true

# Fallback: offset mount
if ! mountpoint -q "$MOUNT_DIR"; then
    info "losetup -P failed or no ext4 found — trying offset mount..."
    sudo mount -o ro,loop,offset="${ROOT_OFFSET}" "$PDK_RAW" "$MOUNT_DIR" || \
        die "Failed to mount root partition. Offset: ${ROOT_OFFSET}"
    ok "Mounted via offset: ${ROOT_OFFSET}"
fi

ROOTFS_SIZE=$(df -sh "$MOUNT_DIR" 2>/dev/null | tail -1 | awk '{print $2}')
info "Rootfs size: ${ROOTFS_SIZE}"

# ── Step 5: Tar rootfs ────────────────────────────────────
info "Creating rootfs tarball: $OUTPUT_TARBALL"
sudo tar -czf "$OUTPUT_TARBALL" \
    --exclude='./proc/*' \
    --exclude='./sys/*' \
    --exclude='./dev/*' \
    --exclude='./run/*' \
    --exclude='./tmp/*' \
    -C "$MOUNT_DIR" .
ok "Tarball: $OUTPUT_TARBALL ($(du -sh $OUTPUT_TARBALL | cut -f1))"

echo ""
echo "======================================================="
ok "PDK extraction complete."
echo "  Output: $OUTPUT_TARBALL"
echo "======================================================="
