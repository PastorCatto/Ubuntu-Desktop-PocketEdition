#!/bin/bash
set -e

# --- Configuration ---
CHROOT_DIR="/home/catto/Ubuntu-Beryllium"

cleanup() {
    echo "--- [CLEANUP] Tearing Down Chroot Environment ---"
    rm -f "$CHROOT_DIR/tmp/apply_fixes.sh" || true
    sudo umount -l "$CHROOT_DIR/sys" 2>/dev/null || true
    sudo umount -l "$CHROOT_DIR/proc" 2>/dev/null || true
    sudo umount -l "$CHROOT_DIR/dev/pts" 2>/dev/null || true
    sudo umount -l "$CHROOT_DIR/dev" 2>/dev/null || true
    echo "--- Cleanup Finished ---"
}
trap cleanup EXIT

if [ ! -d "$CHROOT_DIR/etc" ]; then
    echo "Error: Could not find a rootfs at $CHROOT_DIR"
    exit 1
fi

echo "--- Preparing Chroot Environment at $CHROOT_DIR ---"
sudo mount --bind /dev "$CHROOT_DIR/dev"
sudo mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
sudo mount --bind /proc "$CHROOT_DIR/proc"
sudo mount --bind /sys "$CHROOT_DIR/sys"
sudo cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

cat << 'EOF' > "$CHROOT_DIR/tmp/apply_fixes.sh"
#!/bin/bash
set -ex
export DEBIAN_FRONTEND=noninteractive

echo "--- 1. Installing Toolchain & Dependencies ---"
apt-get update
apt-get install -y alsa-ucm-conf bluez git wget rsync

echo "--- 2. Fetching Pre-Squashed Mainline Firmware ---"
rm -rf /tmp/beryllium-fw
# We use the sdm845-mainline repo, which already contains the squashed .mbn files!
git clone --depth 1 https://gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium.git /tmp/beryllium-fw

mkdir -p /lib/firmware/qcom/sdm845/beryllium
mkdir -p /lib/firmware/ath10k/WCN3990/hw1.0

echo "--- 3. Installing DSP Firmware & GPU Zap ---"
# Find and copy all monolithic .mbn files directly into the beryllium subfolder
find /tmp/beryllium-fw -name "*.mbn" -exec cp -v {} /lib/firmware/qcom/sdm845/beryllium/ \;

echo "--- 4. Fetching missing GPU SQE Microcode ---"
# The 12KB microcode required by msm_dpu to turn on the screen
wget https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/qcom/a630_sqe.fw -O /lib/firmware/qcom/a630_sqe.fw
cp /lib/firmware/qcom/a630_sqe.fw /lib/firmware/qcom/a630sqe.fw

echo "--- 5. WiFi Board Data ---"
find /tmp/beryllium-fw -name "bdwlan.bin" -exec cp -v {} /lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin \;

echo "--- 6. ALSA Audio Setup ---"
rm -rf /tmp/sdm845-ucm
git clone --depth 1 https://gitlab.com/sdm845-mainline/alsa-ucm-conf.git /tmp/sdm845-ucm
cp -rv /tmp/sdm845-ucm/ucm2/* /usr/share/alsa/ucm2/

echo "--- 7. Enabling Qualcomm Services ---"
systemctl enable bluetooth.service
systemctl enable qrtr-ns.service || true
systemctl enable rmtfs.service || true
systemctl enable pd-mapper.service || true
systemctl enable tqftpserv.service || true

echo "--- 8. Cleaning Up ---"
rm -rf /tmp/sdm845-ucm /tmp/beryllium-fw
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "--- Payload Complete ---"
EOF

chmod +x "$CHROOT_DIR/tmp/apply_fixes.sh"

echo "--- Entering Chroot ---"
sudo chroot "$CHROOT_DIR" /bin/bash -c "/tmp/apply_fixes.sh"

echo "--- Patching Success! ---"