#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   [4/7] The Transplant (Pure Ubuntu Edition)"
echo "======================================================="
if [ ! -d "Ubuntu-Beryllium" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" Ubuntu-Beryllium http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static Ubuntu-Beryllium/usr/bin/
    sudo chroot Ubuntu-Beryllium /debootstrap/debootstrap --second-stage
fi

echo ">>> Staging kernel payload..."
sudo cp -r kernel_payload/ Ubuntu-Beryllium/tmp/

echo ">>> Safely mounting virtual filesystems..."
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo mount --bind "/$d" "Ubuntu-Beryllium/$d"
    fi
done

echo ">>> Writing chroot build script..."
# Variables expand here in the OUTER shell, safe from any stdin conflict
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)
cat > "$CHROOT_SCRIPT" << CHROOT_EOF
#!/bin/bash
set -e
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 1. Configure APT (printf avoids nested heredoc stdin conflict)
printf '%s\n' \
    "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse" \
    "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse" \
    "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse" \
    > /etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# 2. Install Hardware Stack, Network, and Audio
apt-get install -y initramfs-tools qrtr-tools rmtfs tqftpserv protection-domain-mapper \
    modemmanager network-manager curl linux-firmware bluez pulseaudio

# 3. Install the Mobian SDM845 Kernel
dpkg -i /tmp/kernel_payload/*.deb || apt-get install -f -y

# 4. Generate the Pure Ubuntu Initramfs
update-initramfs -c -k all

# 5. Install UI Packages
apt-get install -y ${UI_PKG} ${DM_PKG} ${EXTRA_PKG}

# 6. Apply the Golden Wi-Fi Payload Fix
FW_DIR="/lib/firmware/ath10k/WCN3990/hw1.0"
mkdir -p "\$FW_DIR"
GITLAB_BASE="https://gitlab.com/kernel-firmware/linux-firmware/-/raw/main/ath10k/WCN3990/hw1.0"
curl -L -f -o "\$FW_DIR/firmware-5.bin" "\$GITLAB_BASE/firmware-5.bin"
curl -L -f -o "\$FW_DIR/board-2.bin" "\$GITLAB_BASE/board-2.bin"
chattr +i "\$FW_DIR/firmware-5.bin"

# 7. Force Auto-Start for Modem IPC stack
mkdir -p /etc/systemd/system/multi-user.target.wants/
for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
    ln -sf /lib/systemd/system/\$svc.service /etc/systemd/system/multi-user.target.wants/\$svc.service
done

# Cleanup
rm -rf /tmp/kernel_payload /tmp/chroot_setup.sh
apt-get clean
CHROOT_EOF

echo ">>> [Config] Executing Chroot Architecture Build..."
sudo cp "$CHROOT_SCRIPT" Ubuntu-Beryllium/tmp/chroot_setup.sh
sudo chmod +x Ubuntu-Beryllium/tmp/chroot_setup.sh
rm "$CHROOT_SCRIPT"
sudo chroot Ubuntu-Beryllium /bin/bash /tmp/chroot_setup.sh

echo ">>> Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo umount -l "Ubuntu-Beryllium/$d"
    fi
done

echo "======================================================="
echo "   CHROOT BUILD COMPLETE"
echo "======================================================="