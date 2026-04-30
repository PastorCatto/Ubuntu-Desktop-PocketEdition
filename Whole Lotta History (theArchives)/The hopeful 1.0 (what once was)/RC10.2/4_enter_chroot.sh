#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange — [4/5] Enter Chroot ($DEVICE_NAME)"
echo "======================================================="

if uname -r | grep -qi "microsoft"; then
    echo ">>> WSL2 detected. Applying ARM64 binfmt injection..."
    sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64' 2>/dev/null || true
    sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
fi

if [ ! -f /usr/bin/qemu-aarch64-static ]; then
    echo "ERROR: qemu-user-static not installed."
    exit 1
fi

sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
sudo chmod +x "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
    fi
done

echo ">>> Entering $ROOTFS_DIR..."
sudo chroot "$ROOTFS_DIR" /bin/bash

echo ">>> Exited. Unmounting..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
    fi
done
echo ">>> Done."
