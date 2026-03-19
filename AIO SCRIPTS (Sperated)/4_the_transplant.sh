#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [4/8] The Transplant (Base OS Build)"
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

apt-get update && apt-get upgrade -y
export DEBIAN_FRONTEND=noninteractive

# Temporarily disable set -e for the UI install so dbus errors don't crash our script
set +e
apt-get install -y $UI_PKG $EXTRA_PKG modemmanager network-manager systemd-resolved
set -e

echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager 2>/dev/null || true
dpkg-reconfigure lightdm 2>/dev/null || true
CHROOT_EOF

    echo "======================================================="
    echo "   LOMIRI / UI INSTALLATION CHECK"
    echo "======================================================="
    echo ">>> If you selected Lomiri, check the terminal output above."
    echo ">>> Did you see any errors like: 'Failed to connect to bus' or 'dpkg: error processing package'?"
    echo ">>> (This happens because systemd cannot start services inside a chroot)."
    echo ">>> If you saw these errors, DO NOT seal the image yet. Run Script 8 next!"
    echo "======================================================="
fi

echo ""
echo "Do you want to seal the RootFS/BootFS into images right now,"
echo "or continue making manual edits/configurations inside the chroot later?"
echo "1) Seal it now (I am not using Lomiri / had no errors)"
echo "2) Leave it unsealed (I need to run the Script 8 Lomiri Hotfix or make edits)"
read -p "Choice [1-2, default 2]: " CHROOT_CHOICE
CHROOT_CHOICE=${CHROOT_CHOICE:-2}

if [ "$CHROOT_CHOICE" == "1" ]; then
    bash 6_seal_rootfs.sh
else
    echo ">>> Chroot left open at ./Ubuntu-Beryllium"
    echo ">>> If you chose Lomiri, run: bash 8_lomiri_hotfix.sh"
    echo ">>> When you are finished, run: bash 6_seal_rootfs.sh"
fi
