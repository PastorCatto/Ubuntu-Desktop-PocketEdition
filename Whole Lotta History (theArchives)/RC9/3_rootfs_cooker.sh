#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange — [3/5] RootFS Cooker"
echo "======================================================="
echo ">>> Device:  $DEVICE_NAME"
echo ">>> Release: $UBUNTU_RELEASE"
echo ">>> RootFS:  $ROOTFS_DIR"

# -------------------------------------------------------
# Step 1: Debootstrap
# -------------------------------------------------------
if [ ! -d "$ROOTFS_DIR" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."
    sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
    sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
    if [ $? -ne 0 ]; then
        echo ">>> ERROR: Second stage failed."
        sudo rm -rf "$ROOTFS_DIR"; exit 1
    fi
    if [ ! -f "$ROOTFS_DIR/usr/bin/apt-get" ]; then
        echo ">>> ERROR: apt-get not found after second stage."
        sudo rm -rf "$ROOTFS_DIR"; exit 1
    fi
    echo ">>> Debootstrap complete."
else
    echo ">>> $ROOTFS_DIR already exists, skipping debootstrap."
fi

# -------------------------------------------------------
# Step 2: Stage payloads
# -------------------------------------------------------
echo ">>> Staging kernel payload..."
sudo cp -r kernel_payload/ "$ROOTFS_DIR/tmp/"

echo ">>> Copying mkbootimg into rootfs..."
sudo cp /usr/local/bin/mkbootimg "$ROOTFS_DIR/usr/local/bin/mkbootimg"
sudo chmod +x "$ROOTFS_DIR/usr/local/bin/mkbootimg"

# -------------------------------------------------------
# Step 3: Firmware staging (pre-chroot, method=git)
# -------------------------------------------------------
if [ "$FIRMWARE_METHOD" = "git" ] && [ -n "$FIRMWARE_REPO" ]; then
    echo ">>> Cloning firmware repo: $FIRMWARE_REPO"
    FW_TMP=$(mktemp -d /tmp/fw_XXXX)

    if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>/dev/null; then
        echo ">>> Copying firmware into rootfs..."
        sudo cp -r "$FW_TMP/fw/lib/." "$ROOTFS_DIR/lib/"
        if [ -d "$FW_TMP/fw/usr" ]; then
            sudo cp -r "$FW_TMP/fw/usr/." "$ROOTFS_DIR/usr/"
        fi
        echo ">>> Firmware staged from $FIRMWARE_REPO"
    else
        echo ""
        echo ">>> ============================================================"
        echo ">>> WARNING: Failed to clone firmware repo."
        echo ">>> Falling back to OnePlus 6 blobs from linux-firmware apt."
        echo ">>> These blobs are from: /usr/lib/firmware/qcom/sdm845/oneplus6/"
        echo ">>> They are NOT officially signed for $DEVICE_CODENAME."
        echo ">>> Most hardware (GPU, WiFi, BT, DSP) should work, but"
        echo ">>> modem functionality is not guaranteed."
        echo ">>> ============================================================"
        echo ""

        # linux-firmware must be installed on host for this fallback
        ONEPLUS_FW_SRC="/usr/lib/firmware/qcom/sdm845/oneplus6"
        if [ -d "$ONEPLUS_FW_SRC" ]; then
            BERY_FW_DEST="$ROOTFS_DIR/lib/firmware/qcom/sdm845/beryllium"
            sudo mkdir -p "$BERY_FW_DEST"
            # Copy only the core blobs, skip modem carrier configs
            for f in adsp.mbn adspr.jsn adspua.jsn \
                      cdsp.mbn cdspr.jsn \
                      ipa_fws.mbn mba.mbn \
                      modem.mbn modemr.jsn modemuw.jsn \
                      slpi.mbn slpir.jsn slpius.jsn \
                      venus.mbn wlanmdsp.mbn a630_zap.mbn; do
                if [ -f "$ONEPLUS_FW_SRC/$f" ]; then
                    sudo cp "$ONEPLUS_FW_SRC/$f" "$BERY_FW_DEST/$f"
                fi
            done
            echo ">>> Fallback firmware staged from $ONEPLUS_FW_SRC"
        else
            echo ">>> WARNING: OnePlus6 fallback firmware also not found on host."
            echo ">>> You may need to install linux-firmware on the host first:"
            echo ">>>   sudo apt install linux-firmware"
            echo ">>> Continuing without device firmware — expect limited hardware."
        fi
    fi

    rm -rf "$FW_TMP"
fi

# -------------------------------------------------------
# Step 4: Mount virtual filesystems
# -------------------------------------------------------
echo ">>> Mounting virtual filesystems..."
for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo mount --bind "/$d" "$ROOTFS_DIR/$d"
    fi
done

# -------------------------------------------------------
# Step 5: Chroot build script
# -------------------------------------------------------
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)
cat > "$CHROOT_SCRIPT" << CHROOT_EOF
#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# ------- 1. Ubuntu APT sources -------
printf 'deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse\n' > /etc/apt/sources.list
printf 'deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse\n' >> /etc/apt/sources.list
printf 'deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse\n' >> /etc/apt/sources.list

apt-get update

# ------- 2. Bootstrap minimal tools (needed before Mobian repo) -------
apt-get install -y curl wget ca-certificates gnupg

# ------- 3. Add Mobian repo -------
curl -fsSL https://repo.mobian.org/mobian.gpg -o /etc/apt/trusted.gpg.d/mobian.gpg
printf 'deb http://repo.mobian.org/ staging main non-free-firmware\n' \
    > /etc/apt/sources.list.d/mobian.list

apt-get update
apt-get upgrade -y

# ------- 4. Base system -------
apt-get install -y \
    initramfs-tools sudo \
    network-manager modemmanager \
    linux-firmware bluez \
    pipewire pipewire-pulse wireplumber \
    openssh-server locales tzdata

# ------- 5. Boot-method specific packages -------
BOOT_METHOD="${BOOT_METHOD}"
case "\$BOOT_METHOD" in
mkbootimg)
    # Nothing extra needed — mkbootimg is already in /usr/local/bin
    ;;
uboot)
    # Placeholder — install u-boot tools when URL is defined
    echo ">>> U-Boot method: placeholder, no packages installed yet."
    # apt-get install -y u-boot-tools
    ;;
uefi)
    # Placeholder — install UEFI/systemd-boot tools when URL is defined
    echo ">>> UEFI method: placeholder, no packages installed yet."
    # apt-get install -y systemd-boot efibootmgr
    ;;
esac

# ------- 6. SDM845 kernel -------
echo ">>> Installing kernel..."
dpkg -i /tmp/kernel_payload/*.deb || apt-get install -f -y
update-initramfs -c -k all

# ------- 7. Phosh + greetd + phrog -------
echo ">>> Installing Phosh display stack..."
apt-get install -y phosh phosh-osk-stub greetd phrog

useradd -r -m -G video greeter 2>/dev/null || true

mkdir -p /etc/greetd
printf '[terminal]\nvt = 1\n\n[default_session]\ncommand = "phrog"\nuser = "greeter"\n' \
    > /etc/greetd/config.toml

systemctl enable greetd
systemctl disable gdm3    2>/dev/null || true
systemctl disable lightdm 2>/dev/null || true
systemctl disable sddm    2>/dev/null || true

# ------- 8. Device packages -------
if [ -n "${DEVICE_PACKAGES}" ]; then
    echo ">>> Installing device packages: ${DEVICE_PACKAGES}"
    apt-get install -y ${DEVICE_PACKAGES}
fi

# ------- 9. Firmware (apt method) -------
FIRMWARE_METHOD="${FIRMWARE_METHOD}"
if [ "\$FIRMWARE_METHOD" = "apt" ]; then
    echo ">>> Firmware method: apt (linux-firmware already installed)"
fi
# git method firmware was already staged before chroot

# ------- 10. Adreno 630 GPU firmware (not device-signed, safe to curl) -------
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
# Only fetch generic zap if device doesn't have its own (git method provides beryllium-specific one)
if [ "\$FIRMWARE_METHOD" != "git" ]; then
    fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"
fi

# ------- 11. Device services -------
if [ -n "${DEVICE_SERVICES}" ]; then
    echo ">>> Enabling device services: ${DEVICE_SERVICES}"
    for svc in ${DEVICE_SERVICES}; do
        systemctl enable \$svc 2>/dev/null || true
    done
fi

# ------- 12. User account -------
echo ">>> Creating user: ${USERNAME}"
useradd -m -s /bin/bash -G sudo,video,audio,netdev,dialout "${USERNAME}" || true
echo "${USERNAME}:${PASSWORD}" | chpasswd
echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 0440 /etc/sudoers.d/mobuntu-user

# ------- 13. Hostname -------
echo "${DEVICE_HOSTNAME}" > /etc/hostname
printf '127.0.0.1   localhost\n127.0.1.1   ${DEVICE_HOSTNAME}\n::1         localhost ip6-localhost ip6-loopback\n' \
    > /etc/hosts

# ------- 14. Kernel hook -------
echo ">>> Installing zz-qcom-bootimg kernel hook..."
mkdir -p /etc/kernel/postinst.d /etc/initramfs/post-update.d

cat > /etc/kernel/postinst.d/zz-qcom-bootimg << 'HOOK_EOF'
#!/bin/bash
set -e
KERNEL_VERSION="$1"
# Only process sdm845 kernels
case "$KERNEL_VERSION" in
    *sdm845*) ;;
    *) exit 0 ;;
esac

KERNEL="/boot/vmlinuz-${KERNEL_VERSION}"
INITRD="/boot/initrd.img-${KERNEL_VERSION}"
CMDLINE_FILE="/etc/kernel/cmdline"
BOOT_IMG="/boot/boot.img"
BOOT_DTB_FILE="/etc/kernel/boot_dtb"

[ -f "$KERNEL" ]       || exit 0
[ -f "$INITRD" ]       || exit 0
[ -f "$CMDLINE_FILE" ] || exit 0

# Read DTB name from /etc/kernel/boot_dtb if present
if [ -f "$BOOT_DTB_FILE" ]; then
    DTB_NAME=$(cat "$BOOT_DTB_FILE")
else
    DTB_NAME="sdm845-xiaomi-beryllium-tianma.dtb"
fi

DTB_BASE="/usr/lib/linux-image-${KERNEL_VERSION}/qcom"
DTB="${DTB_BASE}/${DTB_NAME}"

if [ ! -f "$DTB" ]; then
    echo "WARNING: DTB not found at $DTB, skipping boot.img rebuild."
    exit 0
fi

CMDLINE=$(cat "$CMDLINE_FILE")
KERNEL_DTB=$(mktemp /tmp/kernel-dtb-XXXX)
cat "$KERNEL" "$DTB" > "$KERNEL_DTB"

mkbootimg \
    --kernel "$KERNEL_DTB" \
    --ramdisk "$INITRD" \
    --pagesize 4096 \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --cmdline "$CMDLINE" \
    -o "$BOOT_IMG"

rm -f "$KERNEL_DTB"
echo ">>> boot.img rebuilt: $BOOT_IMG"
HOOK_EOF
chmod +x /etc/kernel/postinst.d/zz-qcom-bootimg

cat > /etc/initramfs/post-update.d/bootimg << 'INITRD_HOOK_EOF'
#!/bin/sh
/etc/kernel/postinst.d/zz-qcom-bootimg "$1"
INITRD_HOOK_EOF
chmod +x /etc/initramfs/post-update.d/bootimg

# ------- 15. /boot/efi stub -------
mkdir -p /boot/efi

# ------- 16. Extra packages -------
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
# Step 6: Unmount
# -------------------------------------------------------
echo ">>> Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "$ROOTFS_DIR/$d"; then
        sudo umount -l "$ROOTFS_DIR/$d"
    fi
done

echo "======================================================="
echo "   ROOTFS BUILD COMPLETE — $DEVICE_NAME"
echo "   Run script 5 to seal and flash."
echo "======================================================="