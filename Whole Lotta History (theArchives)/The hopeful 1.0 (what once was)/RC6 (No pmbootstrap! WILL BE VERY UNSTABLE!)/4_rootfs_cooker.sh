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

    echo ">>> Running second stage..."
    sudo chroot Ubuntu-Beryllium /usr/bin/qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
    if [ $? -ne 0 ]; then
        echo ">>> ERROR: Debootstrap second stage failed. Removing broken rootfs."
        sudo rm -rf Ubuntu-Beryllium
        exit 1
    fi
    echo ">>> Debootstrap complete. Verifying apt-get..."
    if [ ! -f Ubuntu-Beryllium/usr/bin/apt-get ]; then
        echo ">>> ERROR: apt-get not present after second stage. Rootfs is broken."
        sudo rm -rf Ubuntu-Beryllium
        exit 1
    fi
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
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)
cat > "$CHROOT_SCRIPT" << CHROOT_EOF
#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 1. Configure APT
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

# 6. Qualcomm Firmware Bundle (WiFi + GPU + DSP/Modem)
echo ">>> Detecting installed kernel version..."
KVER=\$(dpkg -l 'linux-image-*-sdm845' 2>/dev/null | grep '^ii' | awk '{print \$2}' | sed 's/linux-image-//')
if [ -z "\$KVER" ]; then
    KVER=\$(uname -r)
fi
echo ">>> Kernel detected: \$KVER"

KERNEL_ORG_FW="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"

fetch_fw() {
    local DEST_DIR="\$1"
    local FILE="\$2"
    local FILENAME="\$(basename \$FILE)"
    mkdir -p "\$DEST_DIR"
    if curl -L -f -s -o "\$DEST_DIR/\$FILENAME" "\$KERNEL_ORG_FW/\$FILE"; then
        echo ">>>   OK: \$FILE"
    else
        echo ">>>   WARN: Failed to fetch \$FILE (non-fatal)"
    fi
    return 0
}

# --- WiFi: ath10k WCN3990 ---
echo ">>> Fetching WiFi firmware (ath10k WCN3990)..."
fetch_fw "/lib/firmware/ath10k/WCN3990/hw1.0" "ath10k/WCN3990/hw1.0/firmware-5.bin"
fetch_fw "/lib/firmware/ath10k/WCN3990/hw1.0" "ath10k/WCN3990/hw1.0/board-2.bin"
chattr +i "/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin" 2>/dev/null || true

# --- GPU: Adreno 630 ---
echo ">>> Fetching GPU firmware (Adreno 630)..."
fetch_fw "/lib/firmware/qcom" "qcom/a630_sqe.fw"
fetch_fw "/lib/firmware/qcom" "qcom/a630_gmu.bin"
fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"

# --- DSP/Modem blobs ---
echo ">>> Fetching DSP and modem firmware..."
for fw in adsp.mbn cdsp.mbn mba.mbn modem.mbn wlanmdsp.mbn; do
    fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/\$fw"
done

# --- Venus video firmware ---
echo ">>> Fetching Venus video firmware..."
fetch_fw "/lib/firmware/qcom/venus-5.2" "qcom/venus-5.2/venus.mbn"

echo ">>> Firmware bundle complete for kernel \$KVER"

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