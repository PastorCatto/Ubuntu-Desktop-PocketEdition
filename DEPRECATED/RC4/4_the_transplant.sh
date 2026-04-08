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

# ==============================================================================
#                 START KERNEL, FIRMWARE & ALSA INJECTION
# ==============================================================================
echo ">>> [Merge] Injecting pmOS kernels & proprietary firmware blobs..."
sudo cp -a pmos_harvest/lib/modules/. Ubuntu-Beryllium/lib/modules/

# 1. Flatten the postmarketOS firmware directory into the root firmware path (User Script Logic)
sudo mkdir -p Ubuntu-Beryllium/lib/firmware/postmarketos
if [ -d "pmos_harvest/lib/firmware/postmarketos" ]; then
    sudo cp -a pmos_harvest/lib/firmware/postmarketos/* Ubuntu-Beryllium/lib/firmware/
    sudo cp -a pmos_harvest/lib/firmware/postmarketos/* Ubuntu-Beryllium/lib/firmware/postmarketos/
else
    sudo cp -a pmos_harvest/lib/firmware/qca Ubuntu-Beryllium/lib/firmware/ 2>/dev/null || true
    sudo cp -a pmos_harvest/lib/firmware/qcom Ubuntu-Beryllium/lib/firmware/ 2>/dev/null || true
fi

# 2. Inject ALSA UCM Audio Profiles for Snapdragon DSP (User Script Logic)
echo ">>> [Merge] Harvesting ALSA UCM Audio Routing Profiles..."
sudo mkdir -p Ubuntu-Beryllium/usr/share/alsa/ucm2/
if [ -d "pmos_harvest/usr/share/alsa/ucm2" ]; then
    sudo cp -a pmos_harvest/usr/share/alsa/ucm2/* Ubuntu-Beryllium/usr/share/alsa/ucm2/
else
    echo ">>> WARNING: ALSA UCM directory not found in harvest. Audio mapping might fail."
fi

# 3. Inject Kernels and Device Trees
sudo mkdir -p Ubuntu-Beryllium/boot/
sudo cp -L pmos_harvest/boot/vmlinuz* Ubuntu-Beryllium/boot/ || true
sudo cp -L pmos_harvest/boot/initramfs* Ubuntu-Beryllium/boot/ || true
if [ -d "pmos_harvest/boot/dtbs" ]; then
    sudo cp -Lr pmos_harvest/boot/dtbs Ubuntu-Beryllium/boot/
fi
# ==============================================================================

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

set +e
echo "$DM_PKG shared/default-x-display-manager select $DM_PKG" | debconf-set-selections

# Install UI + Wi-Fi TFTP Dependencies
apt-get install -y $UI_PKG $DM_PKG modemmanager network-manager systemd-resolved tqftpserv curl linux-firmware

# ==============================================================================
#                  START POCO F1 WIFI & DSP HARDWARE FIXES
# ==============================================================================
echo ">>> Applying Poco F1 WCN3990 WiFi & TFTP Server Fixes..."

# 1. Clean out compressed Zstandard files and the broken 60-byte kernel pointer
rm -f /lib/firmware/ath10k/WCN3990/hw1.0/*.zst 2>/dev/null || true
rm -f /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin 2>/dev/null || true

# 2. Download the pristine kernel firmware payload directly from kernel.org
curl -s -o /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/ath10k/WCN3990/hw1.0/firmware-5.bin

# 3. Stage the DSP payload (wlanmdsp.mbn) in the root firmware directory.
find /lib/firmware/ -name "wlanmdsp.mbn" -exec cp {} /lib/firmware/wlanmdsp.mbn \; -quit

# 4. Enable the TFTP server daemon to start automatically on boot
systemctl enable tqftpserv
# ==============================================================================

echo ">>> Purging LibreOffice bloatware..."
apt-get purge -y libreoffice* || true
apt-get autoremove -y

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