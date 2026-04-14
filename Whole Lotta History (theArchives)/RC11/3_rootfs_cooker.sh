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

    if [ "$HOST_IS_ARM64" = "true" ]; then
        # ARM64 host — single-stage debootstrap, no QEMU needed
        echo ">>> ARM64 host: running single-stage debootstrap..."
        sudo debootstrap --arch=arm64 "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
    else
        # x86-64 host — foreign debootstrap + QEMU second stage
        echo ">>> x86-64 host: running foreign debootstrap with QEMU..."
        sudo debootstrap --arch=arm64 --foreign "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
        sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
        sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /debootstrap/debootstrap --second-stage
        if [ $? -ne 0 ]; then
            echo ">>> ERROR: Second stage failed."
            sudo rm -rf "$ROOTFS_DIR"; exit 1
        fi
    fi

    if [ ! -f "$ROOTFS_DIR/usr/bin/apt-get" ]; then
        echo ">>> ERROR: apt-get not found after debootstrap."
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

# Stage firmware archive into chroot for post-apt re-application
SCRIPT_DIR="$(dirname "$0")"
LOCAL_FW_ARCHIVE="${SCRIPT_DIR}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}/firmware.tar.gz"
if [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>> Staging firmware archive for post-apt re-application..."
    sudo cp "$LOCAL_FW_ARCHIVE" "$ROOTFS_DIR/tmp/firmware.tar.gz"
fi

echo ">>> Copying mkbootimg into rootfs..."
sudo cp /usr/local/bin/mkbootimg "$ROOTFS_DIR/usr/local/bin/mkbootimg"
sudo chmod +x "$ROOTFS_DIR/usr/local/bin/mkbootimg"

# -------------------------------------------------------
# Step 3: Firmware staging (pre-chroot, method=git)
# -------------------------------------------------------
SCRIPT_DIR="$(dirname "$0")"
LOCAL_FW_DIR="${SCRIPT_DIR}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}"
LOCAL_FW_ARCHIVE="${LOCAL_FW_DIR}/firmware.tar.gz"

if [ "$FIRMWARE_METHOD" = "git" ] && [ -n "$FIRMWARE_REPO" ]; then
    FW_STAGED=false

    # --- Priority 1: local firmware archive ---
    if [ -f "$LOCAL_FW_ARCHIVE" ]; then
        echo ">>> Found local firmware archive: $LOCAL_FW_ARCHIVE"
        echo ">>> Extracting into rootfs..."
        sudo tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTFS_DIR/"
        echo ">>> Firmware staged from local archive."
        FW_STAGED=true
    fi

    # --- Priority 2: git clone ---
    if [ "$FW_STAGED" = "false" ]; then
        echo ">>> No local archive found. Cloning firmware repo: $FIRMWARE_REPO"
        FW_TMP=$(mktemp -d /tmp/fw_XXXX)
        if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>/dev/null; then
            echo ">>> Copying firmware into rootfs..."
            sudo cp -r "$FW_TMP/fw/lib/." "$ROOTFS_DIR/lib/"
            if [ -d "$FW_TMP/fw/usr" ]; then
                sudo cp -r "$FW_TMP/fw/usr/." "$ROOTFS_DIR/usr/"
            fi
            echo ">>> Firmware staged from $FIRMWARE_REPO"
            FW_STAGED=true
        fi
        rm -rf "$FW_TMP"
    fi

    # --- Priority 3: OnePlus 6 fallback ---
    if [ "$FW_STAGED" = "false" ]; then
        echo ""
        echo ">>> ============================================================"
        echo ">>> WARNING: git clone failed, local archive not found."
        echo ">>> Falling back to OnePlus 6 blobs from linux-firmware apt."
        echo ">>> Source: /usr/lib/firmware/qcom/sdm845/oneplus6/"
        echo ">>> These blobs are NOT officially signed for $DEVICE_CODENAME."
        echo ">>> GPU, WiFi and BT should work. Modem is not guaranteed."
        echo ">>> ============================================================"
        echo ""
        ONEPLUS_FW_SRC="/usr/lib/firmware/qcom/sdm845/oneplus6"
        if [ -d "$ONEPLUS_FW_SRC" ]; then
            BERY_FW_DEST="$ROOTFS_DIR/lib/firmware/qcom/sdm845/beryllium"
            sudo mkdir -p "$BERY_FW_DEST"
            for f in adsp.mbn adspr.jsn adspua.jsn \
                      cdsp.mbn cdspr.jsn \
                      ipa_fws.mbn mba.mbn \
                      modem.mbn modemr.jsn modemuw.jsn \
                      slpi.mbn slpir.jsn slpius.jsn \
                      venus.mbn wlanmdsp.mbn a630_zap.mbn; do
                [ -f "$ONEPLUS_FW_SRC/$f" ] && sudo cp "$ONEPLUS_FW_SRC/$f" "$BERY_FW_DEST/$f"
            done
            echo ">>> Fallback firmware staged from $ONEPLUS_FW_SRC"
            FW_STAGED=true
        else
            echo ">>> WARNING: OnePlus6 fallback not found on host either."
            echo ">>>   sudo apt install linux-firmware"
            echo ">>> Continuing without device firmware — expect limited hardware."
        fi
    fi
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
# Step 4b: Write kernel hook files on host (avoids nested heredoc issues)
# -------------------------------------------------------
echo ">>> Writing kernel hook files..."
sudo tee /tmp/zz-qcom-bootimg > /dev/null << 'HOOKEOF'
#!/bin/bash
set -e
KERNEL_VERSION="$1"
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
mkbootimg     --kernel "$KERNEL_DTB"     --ramdisk "$INITRD"     --pagesize 4096     --base 0x00000000     --kernel_offset 0x00008000     --ramdisk_offset 0x01000000     --tags_offset 0x00000100     --cmdline "$CMDLINE"     -o "$BOOT_IMG"
rm -f "$KERNEL_DTB"
echo ">>> boot.img rebuilt: $BOOT_IMG"
HOOKEOF

sudo tee /tmp/bootimg-initrd-hook > /dev/null << 'INITRDEOF'
#!/bin/sh
/etc/kernel/postinst.d/zz-qcom-bootimg "$1"
INITRDEOF

# Copy hook files into rootfs for chroot to pick up
sudo cp /tmp/zz-qcom-bootimg "$ROOTFS_DIR/tmp/zz-qcom-bootimg"
sudo cp /tmp/bootimg-initrd-hook "$ROOTFS_DIR/tmp/bootimg-initrd-hook"

# -------------------------------------------------------
# Step 5: Chroot build script
# -------------------------------------------------------
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)

# Step 1: Inject host variables into chroot script header
cat > "$CHROOT_SCRIPT" << INJECT_EOF
#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

# --- Variables injected by host build system ---
UBUNTU_RELEASE="${UBUNTU_RELEASE}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_BRAND="${DEVICE_BRAND}"
DEVICE_PACKAGES="${DEVICE_PACKAGES}"
DEVICE_SERVICES="${DEVICE_SERVICES}"
BOOT_METHOD="${BOOT_METHOD}"
FIRMWARE_METHOD="${FIRMWARE_METHOD}"
UI_NAME="${UI_NAME}"
UI_DM="${UI_DM}"
EXTRA_PKG="${EXTRA_PKG}"
INJECT_EOF

# Step 2: Append the build logic with single-quoted heredoc (no outer expansion)
cat >> "$CHROOT_SCRIPT" << 'CHROOT_EOF'
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# ------- 1. Ubuntu APT sources -------
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse\n" >> /etc/apt/sources.list

apt-get update

# ------- 2. Bootstrap minimal tools -------
apt-get install -y curl wget ca-certificates gnupg

# ------- 3. Add Mobian repo -------
curl -fsSL https://repo.mobian.org/mobian.gpg -o /etc/apt/trusted.gpg.d/mobian.gpg
printf "deb http://repo.mobian.org/ staging main non-free-firmware\n" > /etc/apt/sources.list.d/mobian.list
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
case "$BOOT_METHOD" in
mkbootimg)
    ;;
uboot)
    echo ">>> U-Boot method: placeholder."
    ;;
uefi)
    echo ">>> UEFI method: placeholder."
    ;;
esac

# ------- 6. SDM845 kernel -------
echo ">>> Installing kernel..."
dpkg -i /tmp/kernel_payload/*.deb || apt-get install -f -y
update-initramfs -c -k all

# ------- 7. UI + Display Manager -------
echo ">>> Installing UI: $UI_NAME (DM: $UI_DM)"
case "$UI_NAME" in
phosh)
    apt-get install -y -t staging phosh phosh-osk-stub greetd phrog
    useradd -r -m -G video greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"phrog\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
ubuntu-desktop-minimal)
    apt-get install -y -t "$UBUNTU_RELEASE" ubuntu-desktop-minimal
    systemctl enable gdm3
    ;;
unity)
    apt-get install -y -t "$UBUNTU_RELEASE" ubuntu-unity-desktop
    systemctl enable lightdm
    ;;
plasma-desktop)
    apt-get install -y -t "$UBUNTU_RELEASE" kde-plasma-desktop
    systemctl enable sddm
    ;;
plasma-mobile)
    apt-get install -y -t "$UBUNTU_RELEASE" plasma-mobile maliit-keyboard
    systemctl enable sddm
    ;;
lomiri)
    echo ">>> Installing Lomiri..."
    apt-get install -y -t "$UBUNTU_RELEASE" lomiri lomiri-osk-stub greetd
    useradd -r -m -G video greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"lomiri\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
*)
    echo ">>> WARNING: Unknown UI, falling back to phosh."
    apt-get install -y -t staging phosh phosh-osk-stub greetd phrog
    useradd -r -m -G video greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"phrog\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
esac

for dm in gdm3 lightdm sddm greetd; do
    [ "$dm" != "$UI_DM" ] && systemctl disable $dm 2>/dev/null || true
done

# ------- 8. Device packages + alsa-ucm-conf -------
echo ">>> Installing alsa-ucm-conf (pinned to $UBUNTU_RELEASE)..."
apt-get install -y -t "$UBUNTU_RELEASE" alsa-ucm-conf || apt-get install -y alsa-ucm-conf

if [ -n "$DEVICE_PACKAGES" ]; then
    echo ">>> Installing device packages: $DEVICE_PACKAGES"
    apt-get install -y $DEVICE_PACKAGES
fi

# ------- 9. Firmware (apt method note) -------
if [ "$FIRMWARE_METHOD" = "apt" ]; then
    echo ">>> Firmware method: apt (linux-firmware already installed)"
fi

# ------- 10. Re-apply firmware archive post-apt -------
if [ -f "/tmp/firmware.tar.gz" ]; then
    echo ">>> Re-applying firmware archive (post-apt)..."
    tar -xzf /tmp/firmware.tar.gz -C /
fi

# ------- 11. Adreno 630 GPU firmware -------
echo ">>> Fetching Adreno 630 GPU firmware..."
KERNEL_ORG="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
fetch_fw() {
    local DEST="$1" FILE="$2"
    mkdir -p "$DEST"
    if curl -L -f -s -o "$DEST/$(basename $FILE)" "$KERNEL_ORG/$FILE"; then
        echo ">>>   OK: $FILE"
    else
        echo ">>>   WARN: Failed to fetch $FILE (non-fatal)"
    fi
    return 0
}
fetch_fw "/lib/firmware/qcom"        "qcom/a630_sqe.fw"
fetch_fw "/lib/firmware/qcom"        "qcom/a630_gmu.bin"
if [ "$FIRMWARE_METHOD" != "git" ]; then
    fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"
fi

# ------- 12. Device services -------
if [ -n "$DEVICE_SERVICES" ]; then
    echo ">>> Enabling device services: $DEVICE_SERVICES"
    for svc in $DEVICE_SERVICES; do
        systemctl enable $svc 2>/dev/null || true
    done
fi

# ------- 13. User account -------
echo ">>> Creating user: $USERNAME"
useradd -m -s /bin/bash -G sudo,video,audio,netdev,dialout "$USERNAME" || true
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 0440 /etc/sudoers.d/mobuntu-user

# ------- 14. Hostname -------
echo "$DEVICE_HOSTNAME" > /etc/hostname
printf "127.0.0.1   localhost\n127.0.1.1   $DEVICE_HOSTNAME\n::1         localhost ip6-localhost ip6-loopback\n" > /etc/hosts

# ------- 15. Kernel hook -------
echo ">>> Installing kernel hooks..."
mkdir -p /etc/kernel/postinst.d /etc/initramfs/post-update.d
cp /tmp/zz-qcom-bootimg /etc/kernel/postinst.d/zz-qcom-bootimg
cp /tmp/bootimg-initrd-hook /etc/initramfs/post-update.d/bootimg
chmod +x /etc/kernel/postinst.d/zz-qcom-bootimg
chmod +x /etc/initramfs/post-update.d/bootimg

# ------- 16. /boot/efi stub -------
mkdir -p /boot/efi

# ------- 17. Extra packages -------
if [ -n "$EXTRA_PKG" ]; then
    echo ">>> Installing extra packages: $EXTRA_PKG"
    apt-get install -y $EXTRA_PKG
fi

# ------- Cleanup -------
rm -rf /tmp/kernel_payload /tmp/firmware.tar.gz /tmp/zz-qcom-bootimg /tmp/bootimg-initrd-hook
apt-get clean
echo ">>> Chroot build complete."
CHROOT_EOF

sudo cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_setup.sh"
sudo chmod +x "$ROOTFS_DIR/tmp/chroot_setup.sh"
rm "$CHROOT_SCRIPT"

echo ">>> Executing chroot build (this will take a while)..."
if [ "$HOST_IS_ARM64" = "true" ]; then
    # ARM64 host — direct chroot, no QEMU interpreter needed
    sudo chroot "$ROOTFS_DIR" /bin/bash /tmp/chroot_setup.sh
else
    # x86-64 host — use QEMU static binary
    sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot_setup.sh
fi

# -------------------------------------------------------
# Post-chroot: Re-apply firmware archive (wins over apt)
# -------------------------------------------------------
if [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>> Re-applying firmware archive over apt files..."
    sudo tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTFS_DIR/"
    echo ">>> Firmware archive re-applied — UCM maps and blobs take priority."
fi

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