#!/bin/bash
set -e
echo "======================================================="
echo "   [5/7] Enter Chroot Environment (WSL2 Hardened)"
echo "======================================================="

ROOTFS="Ubuntu-Beryllium"

# --- 1. WSL2 ARM64 Kernel Injection ---
# Automatically detect if the host is running Windows Subsystem for Linux
if uname -r | grep -qi "microsoft"; then
    echo ">>> WSL2 Environment Detected. Applying direct ARM64 kernel injection..."
    
    # Ensure the translation filesystem is awake and mounted
    sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null || true
    
    # Flush broken rules and inject the raw hex magic bytes
    sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/qemu-aarch64' 2>/dev/null || true
    sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:F" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
fi

# --- 2. Emulation Dependencies ---
echo ">>> Verifying ARM64 translation layer..."
if [ ! -f "/usr/bin/qemu-aarch64-static" ]; then
    echo "ERROR: qemu-user-static is not installed on the host."
    echo "Please run: sudo apt-get install qemu-user-static"
    exit 1
fi

# Inject the static emulator and DNS resolution into the rootfs
sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/"
sudo chmod +x "$ROOTFS/usr/bin/qemu-aarch64-static"
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# --- 3. Virtual Filesystem Mounts ---
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS/$d"; then
        sudo mount --bind "/$d" "$ROOTFS/$d"
        echo ">>> Mounted /$d"
    fi
done

# --- 4. Enter the Chroot ---
echo ">>> Entering chroot..."
sudo chroot "$ROOTFS" /bin/bash

# --- 5. Clean Teardown ---
echo ">>> Exited. Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS/$d"; then
        sudo umount -l "$ROOTFS/$d"
        echo ">>> Unmounted /$d"
    fi
done

echo ">>> Chroot environment secured and closed."