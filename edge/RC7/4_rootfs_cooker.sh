#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange ${UBUNTU_CODENAME} - [4/7] The Transplant"
echo "   Device  : ${DEVICE_NAME} (${DEVICE_CODENAME})"
echo "   RootFS  : ${ROOTFS_DIR}"
echo "======================================================="

if [ ! -d "$ROOTFS_DIR" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"

    echo ">>> Running second stage..."
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
    if [ $? -ne 0 ]; then
        echo ">>> ERROR: Debootstrap second stage failed. Removing broken rootfs."
        sudo rm -rf "$ROOTFS_DIR"
        exit 1
    fi
    echo ">>> Debootstrap complete. Verifying apt-get..."
    if [ ! -f "$ROOTFS_DIR/usr/bin/apt-get" ]; then
        echo ">>> ERROR: apt-get not present after second stage. Rootfs is broken."
        sudo rm -rf "$ROOTFS_DIR"
        exit 1
    fi
fi

echo ">>> Staging kernel payload..."
sudo cp -r kernel_payload/ "$ROOTFS_DIR/tmp/"

# Stage droid-juicer configs if they exist
if [ -d "droid-juicer-configs" ]; then
    echo ">>> Staging droid-juicer configs..."
    sudo cp -r droid-juicer-configs/ "$ROOTFS_DIR/tmp/"
fi

echo ">>> Safely mounting virtual filesystems..."
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
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

# 4. Generate Initramfs
update-initramfs -c -k all

# 5. Install UI Packages
apt-get install -y ${UI_PKG} ${DM_PKG}
if [ -n "${EXTRA_PKG}" ]; then
    apt-get install -y ${EXTRA_PKG}
fi

# 6. Adreno 630 GPU Firmware
# WiFi, DSP, modem, and Venus are already provided by the linux-firmware apt package.
# Only the Adreno 630 GPU blobs are missing from Ubuntu repos.
echo ">>> Fetching Adreno 630 GPU firmware..."
KERNEL_ORG_FW="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"

fetch_fw() {
    local DEST_DIR="\$1"
    local FILE="\$2"
    mkdir -p "\$DEST_DIR"
    if curl -L -f -s -o "\$DEST_DIR/\$(basename \$FILE)" "\$KERNEL_ORG_FW/\$FILE"; then
        echo ">>>   OK: \$FILE"
    else
        echo ">>>   WARN: Failed to fetch \$FILE (non-fatal)"
    fi
    return 0
}

fetch_fw "/lib/firmware/qcom"        "qcom/a630_sqe.fw"
fetch_fw "/lib/firmware/qcom"        "qcom/a630_gmu.bin"
fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"
echo ">>> GPU firmware complete."

# 7. Install droid-juicer for first-boot firmware extraction from Android vendor partition
echo ">>> Installing droid-juicer..."
# Add Mobian repo temporarily - droid-juicer is a Mobian project not in Ubuntu repos
curl -fsSL https://repo.mobian-project.org/mobian.gpg \
    -o /etc/apt/trusted.gpg.d/mobian-dj.gpg 2>/dev/null || true
echo "deb https://repo.mobian-project.org/ trixie main" \
    > /etc/apt/sources.list.d/mobian-dj.list
apt-get update -qq
if apt-get install -y droid-juicer 2>/dev/null; then
    echo ">>> droid-juicer installed successfully."
else
    echo ">>> WARN: droid-juicer install failed — firmware will rely on curl fetches only."
fi
# Remove Mobian repo — only needed for droid-juicer
rm -f /etc/apt/sources.list.d/mobian-dj.list
rm -f /etc/apt/trusted.gpg.d/mobian-dj.gpg
apt-get update -qq

# Install droid-juicer device configs
if [ -d /tmp/droid-juicer-configs ] && command -v droid-juicer &>/dev/null; then
    mkdir -p /etc/droid-juicer
    cp /tmp/droid-juicer-configs/*.toml /etc/droid-juicer/
    echo ">>> droid-juicer device configs installed to /etc/droid-juicer/"
    # Enable first-boot firmware extraction service
    systemctl enable droid-juicer.service 2>/dev/null && \
        echo ">>> droid-juicer service enabled for first-boot firmware extraction." || \
        echo ">>> WARN: Could not enable droid-juicer service."
fi

# 8. Create user account
echo ">>> Creating user: ${USERNAME}..."
useradd -m -s /bin/bash -G sudo,audio,video,render,netdev,plugdev "${USERNAME}" 2>/dev/null || true
echo "${USERNAME}:${PASSWORD}" | chpasswd
# Allow sudo without password for convenience on mobile
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 440 /etc/sudoers.d/mobuntu-user

# 9. Set hostname
echo "mobuntu-${DEVICE_CODENAME}" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
127.0.1.1   mobuntu-${DEVICE_CODENAME}
HOSTS_EOF

# 10. Force Auto-Start for Modem IPC stack
mkdir -p /etc/systemd/system/multi-user.target.wants/
for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
    if [ -f /lib/systemd/system/\${svc}.service ]; then
        ln -sf /lib/systemd/system/\${svc}.service \
            /etc/systemd/system/multi-user.target.wants/\${svc}.service
    fi
done

# Cleanup
rm -rf /tmp/kernel_payload /tmp/droid-juicer-configs /tmp/chroot_setup.sh
apt-get clean
CHROOT_EOF

echo ">>> [Config] Executing Chroot Architecture Build..."
sudo cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_setup.sh"
sudo chmod +x "$ROOTFS_DIR/tmp/chroot_setup.sh"
rm "$CHROOT_SCRIPT"
sudo chroot "$ROOTFS_DIR" /bin/bash /tmp/chroot_setup.sh

echo ">>> Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
    fi
done

echo "======================================================="
echo "   CHROOT BUILD COMPLETE"
echo "   Mobuntu Orange ${UBUNTU_CODENAME} / ${DEVICE_NAME}"
echo "======================================================="
