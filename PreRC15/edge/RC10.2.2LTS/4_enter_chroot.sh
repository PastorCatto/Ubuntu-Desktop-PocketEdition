#!/bin/bash
# Mobuntu — RC13
set -e
source build.env
echo "======================================================="
echo "   Mobuntu — [4/5] Enter Chroot ($DEVICE_NAME)"
echo "======================================================="

HOST_ARCH=$(uname -m)

if [ "$HOST_ARCH" = "aarch64" ]; then
    # -------------------------------------------------------
    # ARM64 host — direct chroot, no QEMU needed
    # -------------------------------------------------------
    echo ">>> ARM64 host — skipping QEMU setup."
    sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
else
    # -------------------------------------------------------
    # x86-64 host — WSL2 binfmt injection if needed
    # -------------------------------------------------------
    if uname -r | grep -qi "microsoft"; then
        echo ">>> WSL2 + x86-64 detected. Applying ARM64 binfmt injection..."
        sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
        sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64' 2>/dev/null || true
        sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64:F" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
    fi

    if [ ! -f /usr/bin/qemu-aarch64 ]; then
        echo "ERROR: qemu-user-static not installed."
        exit 1
    fi

    sudo cp /usr/bin/qemu-aarch64 "$ROOTFS_DIR/usr/bin/"
    sudo chmod +x "$ROOTFS_DIR/usr/bin/qemu-aarch64"
    sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
fi

# -------------------------------------------------------
# Mount virtual filesystems
# -------------------------------------------------------
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
    fi
done

# -------------------------------------------------------
# Enter chroot
# -------------------------------------------------------
echo ">>> Entering $ROOTFS_DIR..."
if [ "$HOST_ARCH" = "aarch64" ]; then
    sudo chroot "$ROOTFS_DIR" /bin/bash
else
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64 /bin/bash
fi

# -------------------------------------------------------
# Teardown
# -------------------------------------------------------
echo ">>> Exited. Unmounting..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
    fi
done
echo ">>> Done."