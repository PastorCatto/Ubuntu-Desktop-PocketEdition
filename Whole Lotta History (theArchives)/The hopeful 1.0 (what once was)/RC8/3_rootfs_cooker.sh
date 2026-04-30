#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange — [3/5] RootFS Cooker"
echo "======================================================="

# -------------------------------------------------------
# Step 1: Debootstrap
# -------------------------------------------------------
if [ ! -d "$ROOTFS_DIR" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"

    echo ">>> Running second stage..."
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
    if [ $? -ne 0 ]; then
        echo ">>> ERROR: Second stage failed. Removing broken rootfs."
        sudo rm -rf "$ROOTFS_DIR"
        exit 1
    fi

    if [ ! -f "$ROOTFS_DIR/usr/bin/apt-get" ]; then
        echo ">>> ERROR: apt-get not found after second stage."
        sudo rm -rf "$ROOTFS_DIR"
        exit 1
    fi
    echo ">>> Debootstrap complete."
else
    echo ">>> Rootfs directory $ROOTFS_DIR already exists, skipping debootstrap."
fi

# -------------------------------------------------------
# Step 2: Stage payloads
# -------------------------------------------------------
echo ">>> Staging kernel payload..."
sudo cp -r kernel_payload/ "$ROOTFS_DIR/tmp/"

echo ">>> Copying mkbootimg into rootfs (needed by kernel hook)..."
sudo cp /usr/local/bin/mkbootimg "$ROOTFS_DIR/usr/local/bin/mkbootimg"
sudo chmod +x "$ROOTFS_DIR/usr/local/bin/mkbootimg"

# -------------------------------------------------------
# Step 3: Mount virtual filesystems
# -------------------------------------------------------
echo ">>> Mounting virtual filesystems..."
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
    fi
done

# -------------------------------------------------------
# Step 4: Write and run chroot script
# -------------------------------------------------------
echo ">>> Writing chroot build script..."
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)

cat > "$CHROOT_SCRIPT" << CHROOT_EOF
#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# ------- 1. APT Sources -------
cat > /etc/apt/sources.list << APT_EOF
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-backports main restricted universe multiverse
APT_EOF

# Update base repos and install curl + ca-certificates first
apt-get update
apt-get install -y curl ca-certificates

# Now you can safely use curl to add the Mobian repo
curl -fsSL https://repo.mobian.org/mobian.gpg -o /etc/apt/trusted.gpg.d/mobian.gpg
echo "deb http://repo.mobian.org/ staging main non-free-firmware" \
    > /etc/apt/sources.list.d/mobian.list

# Update again to fetch the new Mobian package lists
apt-get update
apt-get upgrade -y

# ------- 2. Base system -------
# (curl and ca-certificates removed from here since they are already installed)
apt-get install -y \
    initramfs-tools sudo wget \
    network-manager modemmanager \
    linux-firmware bluez \
    qrtr-tools rmtfs tqftpserv protection-domain-mapper \
    pipewire pipewire-pulse wireplumber \
    openssh-server \
    locales tzdata

# ------- 3. Install SDM845 kernel -------
echo ">>> Installing SDM845 kernel..."
dpkg -i /tmp/kernel_payload/*.deb || apt-get install -f -y
update-initramfs -c -k all

# ------- 4. Ubuntu Desktop Minimal -------
echo ">>> Installing Ubuntu Desktop Minimal display stack...(Manual OVERRIDE!)"
apt-get install -y ubuntu-desktop-minimal

systemctl enable gdm3
# Disable any conflicting display managers
systemctl disable lightdm 2>/dev/null || true
systemctl disable sddm    2>/dev/null || true
systemctl disable greetd  2>/dev/null || true

# ------- 5. droid-juicer + qbootctl -------
echo ">>> Installing droid-juicer and qbootctl..."
apt-get install -y droid-juicer qbootctl

# ------- 6. Adreno 630 GPU firmware -------
# adsp/cdsp/modem/venus/wlan for beryllium come from droid-juicer on first boot.
# GPU firmware is not device-signed so we fetch it directly.
echo ">>> Fetching Adreno 630 GPU firmware..."
KERNEL_ORG="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"

fetch_fw() {
    local DEST="\$1" FILE="\$2"
    mkdir -p "\$DEST"
    if curl -L -f -s -o "\$DEST/\$(basename \$FILE)" "\$KERNEL_ORG/\$FILE"; then
        echo ">>>   OK: \$FILE"
    else
        echo ">>>   WARN: Failed to fetch \$FILE (non-fatal)"
    fi
    return 0
}

fetch_fw "/lib/firmware/qcom"        "qcom/a630_sqe.fw"
fetch_fw "/lib/firmware/qcom"        "qcom/a630_gmu.bin"
fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"

# ------- 7. Qualcomm modem IPC services -------
echo ">>> Enabling Qualcomm modem stack services..."
for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
    systemctl enable \$svc 2>/dev/null || true
done

# ------- 8. User account -------
echo ">>> Creating user: ${USERNAME}"
useradd -m -s /bin/bash -G sudo,video,audio,netdev,dialout "${USERNAME}" || true
echo "${USERNAME}:${PASSWORD}" | chpasswd
# Allow passwordless sudo
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 0440 /etc/sudoers.d/mobuntu-user

# ------- 9. Hostname -------
echo "mobuntu-beryllium" > /etc/hostname
cat > /etc/hosts << HOSTS_EOF
127.0.0.1   localhost
127.0.1.1   mobuntu-beryllium
::1         localhost ip6-localhost ip6-loopback
HOSTS_EOF

# ------- 10. Kernel hook for auto boot.img rebuild -------
echo ">>> Installing zz-qcom-bootimg kernel hook..."
mkdir -p /etc/kernel/postinst.d /etc/initramfs/post-update.d

cat > /etc/kernel/postinst.d/zz-qcom-bootimg << 'HOOK_EOF'
#!/bin/bash
# Rebuild boot.img after every kernel update
set -e
KERNEL_VERSION="\$1"
KERNEL="/boot/vmlinuz-\${KERNEL_VERSION}"
INITRD="/boot/initrd.img-\${KERNEL_VERSION}"
CMDLINE_FILE="/etc/kernel/cmdline"
BOOT_IMG="/boot/boot.img"

[ -f "\$KERNEL" ]       || exit 0
[ -f "\$INITRD" ]       || exit 0
[ -f "\$CMDLINE_FILE" ] || exit 0

# Find beryllium DTB
DTB_BASE="/usr/lib/linux-image-\${KERNEL_VERSION}/qcom"
if [ -f "\${DTB_BASE}/sdm845-xiaomi-beryllium-tianma.dtb" ]; then
    DTB="\${DTB_BASE}/sdm845-xiaomi-beryllium-tianma.dtb"
elif [ -f "\${DTB_BASE}/sdm845-xiaomi-beryllium-ebbg.dtb" ]; then
    DTB="\${DTB_BASE}/sdm845-xiaomi-beryllium-ebbg.dtb"
else
    echo "WARNING: No beryllium DTB found, skipping boot.img rebuild."
    exit 0
fi

CMDLINE=\$(cat "\$CMDLINE_FILE")
KERNEL_DTB=\$(mktemp /tmp/kernel-dtb-XXXX)
cat "\$KERNEL" "\$DTB" > "\$KERNEL_DTB"

mkbootimg \
    --kernel "\$KERNEL_DTB" \
    --ramdisk "\$INITRD" \
    --pagesize 4096 \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --cmdline "\$CMDLINE" \
    -o "\$BOOT_IMG"

rm -f "\$KERNEL_DTB"
echo ">>> boot.img rebuilt at \$BOOT_IMG"
HOOK_EOF

chmod +x /etc/kernel/postinst.d/zz-qcom-bootimg

cat > /etc/initramfs/post-update.d/bootimg << 'INITRD_HOOK_EOF'
#!/bin/sh
# Trigger boot.img rebuild when initramfs is updated
/etc/kernel/postinst.d/zz-qcom-bootimg "\$1"
INITRD_HOOK_EOF

chmod +x /etc/initramfs/post-update.d/bootimg

# ------- 11. /boot/efi stub (Ubuntu expects it) -------
mkdir -p /boot/efi

# ------- 12. Extra packages -------
if [ -n "${EXTRA_PKG}" ]; then
    echo ">>> Installing extra packages: ${EXTRA_PKG}"
    apt-get install -y ${EXTRA_PKG}
fi

# ------- Cleanup -------
rm -rf /tmp/kernel_payload
apt-get clean
echo ">>> Chroot build complete."
CHROOT_EOF

sudo cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_setup.sh"
sudo chmod +x "$ROOTFS_DIR/tmp/chroot_setup.sh"
rm "$CHROOT_SCRIPT"

echo ">>> Executing chroot build (this will take a while)..."
sudo chroot "$ROOTFS_DIR" /bin/bash /tmp/chroot_setup.sh

# -------------------------------------------------------
# Step 5: Unmount
# -------------------------------------------------------
echo ">>> Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
    fi
done

echo "======================================================="
echo "   ROOTFS BUILD COMPLETE"
echo "   Proceed to script 5 to seal and flash."
echo "   (Use script 4 to enter chroot for debugging)"
echo "======================================================="
