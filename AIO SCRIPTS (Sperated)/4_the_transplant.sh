#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [4/7] The Transplant (Base OS Build)"
echo "======================================================="
echo ">>> Target: Beryllium | User: $USERNAME | UI: $UI_NAME"
echo ">>> Boot Method: Dual-Partition (System Hijack) via ABL"
echo ">>> Expected Root UUID: ${PMOS_ROOT_UUID:-None Found}"
echo ">>> Expected Boot UUID: ${PMOS_BOOT_UUID:-None Found}"
echo ">>> ---------------------------------------------------"

SKIP_SETUP="no"

if [ ! -d "Ubuntu-Beryllium" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" Ubuntu-Beryllium http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static Ubuntu-Beryllium/usr/bin/
    sudo chroot Ubuntu-Beryllium /debootstrap/debootstrap --second-stage
else
    echo ">>> [Debootstrap] Ubuntu-Beryllium already exists, skipping base generation."
    read -p ">>> Re-run repository and UI setup phase? (y/n) [default: n]: " RUN_SETUP
    RUN_SETUP=${RUN_SETUP:-n}
    if [ "$RUN_SETUP" != "y" ]; then
        SKIP_SETUP="yes"
    fi
fi

echo ">>> [Merge] Injecting pmOS kernels & firmware..."
sudo cp -a pmos_harvest/lib/modules/. Ubuntu-Beryllium/lib/modules/
sudo cp -a pmos_harvest/lib/firmware/. Ubuntu-Beryllium/lib/firmware/

sudo mkdir -p Ubuntu-Beryllium/boot/
sudo cp -L pmos_harvest/boot/vmlinuz* Ubuntu-Beryllium/boot/ || true
sudo cp -L pmos_harvest/boot/initramfs* Ubuntu-Beryllium/boot/ || true
if [ -d "pmos_harvest/boot/dtbs" ]; then
    sudo cp -Lr pmos_harvest/boot/dtbs Ubuntu-Beryllium/boot/
fi

echo ">>> [Merge] Injecting stashed Mobian hardware profiles..."
if [ -d "$FIRMWARE_STASH/usr/share/alsa/ucm2" ]; then
    sudo mkdir -p Ubuntu-Beryllium/usr/share/alsa/ucm2/
    sudo cp -a "$FIRMWARE_STASH/usr/share/alsa/ucm2/." Ubuntu-Beryllium/usr/share/alsa/ucm2/ || true
fi

if [ "$SKIP_SETUP" == "no" ]; then
    
    echo ">>> Safely mounting virtual filesystems for chroot..."
    for d in dev dev/pts proc sys run; do
        if ! mountpoint -q "Ubuntu-Beryllium/$d"; then
            sudo mount --bind "/$d" "Ubuntu-Beryllium/$d"
        fi
    done

    echo ">>> [Config] Expanding repositories and installing UI..."
    sudo chroot Ubuntu-Beryllium /bin/bash << CHROOT_EOF
echo "nameserver 8.8.8.8" > /etc/resolv.conf

cat << APT_EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-security main restricted universe multiverse
APT_EOF

if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash $USERNAME
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo,video,audio,plugdev $USERNAME
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Temporarily disable set -e for the UI install so minor warnings don't kill the script
set +e

# Pre-seed the debconf database so the display manager installs silently
echo "$DM_PKG shared/default-x-display-manager select $DM_PKG" | debconf-set-selections

# Install the UI and Display Manager with --no-install-recommends to kill bloat
apt-get install -y --no-install-recommends $UI_PKG $DM_PKG modemmanager network-manager systemd-resolved

# Hardcode the default display manager to ensure no black screens on boot
echo "/usr/sbin/$DM_PKG" > /etc/X11/default-display-manager
dpkg-reconfigure -f noninteractive $DM_PKG 2>/dev/null || true

set -e
CHROOT_EOF

    echo ">>> Unmounting virtual filesystems..."
    for d in run sys proc dev/pts dev; do
        if mountpoint -q "Ubuntu-Beryllium/$d"; then
            sudo umount -l "Ubuntu-Beryllium/$d"
        fi
    done
fi

echo "======================================================="
echo "   CHROOT BUILD COMPLETE"
echo "======================================================="
echo ">>> Run bash 6_seal_rootfs.sh to pack your images,"
echo ">>> or run bash 5_enter_chroot.sh to make manual tweaks."
