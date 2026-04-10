#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [4/7] The Transplant (Beryllium Hardware Final)"
echo "======================================================="
echo ">>> Target: Beryllium | Preserving Path Integrity"
echo ">>> ---------------------------------------------------"

SKIP_SETUP="no"

if [ ! -d "Ubuntu-Beryllium" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" Ubuntu-Beryllium http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static Ubuntu-Beryllium/usr/bin/
    sudo chroot Ubuntu-Beryllium /debootstrap/debootstrap --second-stage
else
    echo ">>> [Debootstrap] Ubuntu-Beryllium already exists."
    read -p ">>> Re-run repo/UI setup phase? (y/n) [default: y]: " RUN_SETUP
    RUN_SETUP=${RUN_SETUP:-y}
    if [ "$RUN_SETUP" != "y" ]; then
        SKIP_SETUP="yes"
    fi
fi

# ==============================================================================
#                 1. MODULES & FIRMWARE (PRESERVING NESTING)
# ==============================================================================
echo ">>> [Merge] Injecting pmOS modules and firmware..."
sudo cp -a pmos_harvest/lib/modules/. Ubuntu-Beryllium/lib/modules/

# CRITICAL: Preserve the 'qcom/sdm845/' hierarchy from the pmos harvest.
# This prevents Error 90 by keeping payloads where tqftpserv expects them.
sudo mkdir -p Ubuntu-Beryllium/lib/firmware/
sudo cp -a pmos_harvest/lib/firmware/. Ubuntu-Beryllium/lib/firmware/

# ==============================================================================
#                 2. GOLDEN WI-FI PAYLOAD INJECTION
# ==============================================================================
FW_DIR="Ubuntu-Beryllium/lib/firmware/ath10k/WCN3990/hw1.0"
sudo mkdir -p "$FW_DIR"

GITLAB_BASE="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/ath10k/WCN3990/hw1.0"

echo ">>> [Inject] Pulling firmware-5.bin..."
sudo curl -L -f -o "$FW_DIR/firmware-5.bin" \
    "$GITLAB_BASE/firmware-5.bin"

echo ">>> [Inject] Pulling board-2.bin (includes xiaomi_beryllium entry)..."
sudo curl -L -f -o "$FW_DIR/board-2.bin" \
    "$GITLAB_BASE/board-2.bin"

# ==============================================================================
#                 3. AUDIO & BOOT ASSETS
# ==============================================================================
echo ">>> [Merge] Harvesting ALSA UCM & Boot assets..."
sudo mkdir -p Ubuntu-Beryllium/usr/share/alsa/ucm2/
if [ -d "pmos_harvest/usr/share/alsa/ucm2" ]; then
    sudo cp -a pmos_harvest/usr/share/alsa/ucm2/* Ubuntu-Beryllium/usr/share/alsa/ucm2/
fi

sudo mkdir -p Ubuntu-Beryllium/boot/
sudo cp -L pmos_harvest/boot/vmlinuz* Ubuntu-Beryllium/boot/ || true
sudo cp -L pmos_harvest/boot/initramfs* Ubuntu-Beryllium/boot/ || true
if [ -d "pmos_harvest/boot/dtbs" ]; then
    sudo cp -Lr pmos_harvest/boot/dtbs Ubuntu-Beryllium/boot/
fi

# ==============================================================================
#                 4. CHROOT CONFIGURATION PHASE
# ==============================================================================
if [ "$SKIP_SETUP" == "no" ]; then
    echo ">>> Safely mounting virtual filesystems..."
    for d in dev dev/pts proc sys run; do
        if ! mountpoint -q "Ubuntu-Beryllium/$d"; then
            sudo mount --bind "/$d" "Ubuntu-Beryllium/$d"
        fi
    done

    echo ">>> [Config] Finalizing System Settings & Protection..."
    sudo chroot Ubuntu-Beryllium /bin/bash << CHROOT_EOF
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Configure APT
cat << APT_EOF > /etc/apt/sources.list
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ $UBUNTU_RELEASE-security main restricted universe multiverse
APT_EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Install hardware stack daemons
apt-get install -y qrtr-tools rmtfs tqftpserv protection-domain-mapper \
    modemmanager network-manager curl linux-firmware

# PROTECT THE FIRMWARE: This is the permanent fix for the 60-byte symlink trap.
chattr +i /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin

# FORCE AUTO-START: Ensures the modem IPC stack boots with the phone.
mkdir -p /etc/systemd/system/multi-user.target.wants/
for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
    ln -sf /lib/systemd/system/\$svc.service /etc/systemd/system/multi-user.target.wants/\$svc.service
done

apt-get autoremove -y
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