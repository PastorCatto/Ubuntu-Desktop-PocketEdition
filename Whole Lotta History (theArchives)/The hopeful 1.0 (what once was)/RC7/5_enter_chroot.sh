#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange ${UBUNTU_CODENAME} - [5/7] Enter Chroot"
echo "   Device  : ${DEVICE_NAME} (${DEVICE_CODENAME})"
echo "   RootFS  : ${ROOTFS_DIR}"
echo "======================================================="

# --- 1. WSL2 ARM64 Kernel Injection ---
if uname -r | grep -qi "microsoft"; then
    echo ">>> WSL2 Environment Detected. Applying direct ARM64 kernel injection..."
    sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64' 2>/dev/null || true
    sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
fi

# --- 2. Verify emulation layer ---
echo ">>> Verifying ARM64 translation layer..."
if [ ! -f "/usr/bin/qemu-aarch64-static" ]; then
    echo "ERROR: qemu-user-static is not installed on the host."
    echo "Please run: sudo apt-get install qemu-user-static"
    exit 1
fi

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "ERROR: RootFS directory '$ROOTFS_DIR' does not exist."
    echo "Please run script 4 first."
    exit 1
fi

sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
sudo chmod +x "$ROOTFS_DIR/usr/bin/qemu-aarch64-static"
sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

# --- 3. Virtual Filesystem Mounts ---
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
        echo ">>> Mounted /$d"
    fi
done

# --- 4. Enter the Chroot ---
echo ">>> Entering chroot into $ROOTFS_DIR ..."
echo ">>> Type 'exit' or press Ctrl+D to leave."
sudo chroot "$ROOTFS_DIR" /bin/bash

# --- 5. Clean Teardown ---
echo ">>> Exited chroot. Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
        echo ">>> Unmounted /$d"
    fi
done

echo ">>> Chroot environment secured and closed."
