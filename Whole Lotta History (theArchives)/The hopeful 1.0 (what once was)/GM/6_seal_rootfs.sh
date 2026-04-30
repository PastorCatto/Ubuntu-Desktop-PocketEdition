#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [6/7] Finalizing and Sealing Dual-Partition Images"
echo "======================================================="
ROOT_IMG="ubuntu_beryllium_root.img"
BOOT_IMG="ubuntu_beryllium_boot.img"

for d in run sys proc dev/pts dev; do
    if mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo umount -l "Ubuntu-Beryllium/$d"
    fi
done

echo ">>> [Packing] Allocating 256MB BootFS..."
dd if=/dev/zero of="$BOOT_IMG" bs=1M count=256 status=progress
mkfs.ext4 -L pmOS_boot -U "${PMOS_BOOT_UUID:-$(uuidgen)}" "$BOOT_IMG"

IMG_MB=$((IMAGE_SIZE * 1024))
echo ">>> [Packing] Allocating ${IMAGE_SIZE}GB RootFS..."
dd if=/dev/zero of="$ROOT_IMG" bs=1M count=$IMG_MB status=progress
mkfs.ext4 -L pmOS_root -U "${PMOS_ROOT_UUID:-$(uuidgen)}" "$ROOT_IMG"

mkdir -p mnt_root mnt_boot
sudo mount -o loop "$ROOT_IMG" mnt_root/
sudo mount -o loop "$BOOT_IMG" mnt_boot/

sudo cp -a Ubuntu-Beryllium/. mnt_root/
sudo mv mnt_root/boot/* mnt_boot/ 2>/dev/null || true

sudo umount mnt_root mnt_boot
rm -rf mnt_root mnt_boot

sudo e2fsck -f -y "$ROOT_IMG"
sudo e2fsck -f -y "$BOOT_IMG"

if ! command -v img2simg &> /dev/null; then
    sudo apt-get install -y android-sdk-libsparse-utils || sudo apt-get install -y android-tools-fsutils
fi

ROOT_SPARSE="${ROOT_IMG%.img}_sparse.img"
BOOT_SPARSE="${BOOT_IMG%.img}_sparse.img"

img2simg "$ROOT_IMG" "$ROOT_SPARSE"
img2simg "$BOOT_IMG" "$BOOT_SPARSE"

echo ">>> FLASHING INSTRUCTIONS:"
echo ">>> 1. fastboot flash boot $(pwd)/pmos_boot.img"
echo ">>> 2. fastboot flash system $(pwd)/$BOOT_SPARSE"
echo ">>> 3. fastboot flash userdata $(pwd)/$ROOT_SPARSE"
