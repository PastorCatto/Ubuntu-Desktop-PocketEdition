#!/bin/bash
# Mobuntu — RC14
set -e
source build.env
echo "======================================================="
echo "   Mobuntu — [3/5] RootFS Cooker -- RC14"
echo "======================================================="
echo ">>> Device:  $DEVICE_NAME"
echo ">>> Release: $UBUNTU_RELEASE"
echo ">>> RootFS:  $ROOTFS_DIR"

# Quirk helper — used on host side for staging decisions
has_quirk() { echo " ${DEVICE_QUIRKS} " | grep -qw "$1"; }

# -------------------------------------------------------
# Step 1: Debootstrap
# -------------------------------------------------------
if [ ! -d "$ROOTFS_DIR" ]; then
    echo ">>> [Debootstrap] Building Ubuntu $UBUNTU_RELEASE (arm64)..."

    if [ "$HOST_IS_ARM64" = "true" ]; then
        echo ">>> ARM64 host: running single-stage debootstrap..."
        sudo debootstrap --arch=arm64 "$UBUNTU_RELEASE" "$ROOTFS_DIR" http://ports.ubuntu.com/
    else
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_FW_DIR="${SCRIPT_DIR}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}"
LOCAL_FW_ARCHIVE="${LOCAL_FW_DIR}/firmware.tar.gz"

if has_quirk "qcom_services"; then
    echo ">>> Staging qcom-firmware initramfs hook..."
    QCOM_FW_HOOK_DEVICE="${LOCAL_FW_DIR}/qcom-firmware"
    QCOM_FW_HOOK_ROOT="${SCRIPT_DIR}/qcom-firmware"
    if [ -f "$QCOM_FW_HOOK_DEVICE" ]; then
        sudo cp "$QCOM_FW_HOOK_DEVICE" "$ROOTFS_DIR/tmp/qcom-firmware"
        sudo chmod +x "$ROOTFS_DIR/tmp/qcom-firmware"
        echo ">>>   Staged from: $QCOM_FW_HOOK_DEVICE"
    elif [ -f "$QCOM_FW_HOOK_ROOT" ]; then
        sudo cp "$QCOM_FW_HOOK_ROOT" "$ROOTFS_DIR/tmp/qcom-firmware"
        sudo chmod +x "$ROOTFS_DIR/tmp/qcom-firmware"
        echo ">>>   Staged from project root: $QCOM_FW_HOOK_ROOT"
    else
        echo ">>> WARNING: qcom-firmware hook not found."
        echo ">>>   Checked: $QCOM_FW_HOOK_DEVICE"
        echo ">>>   Checked: $QCOM_FW_HOOK_ROOT"
    fi

    echo ">>> Staging 51-qcom.conf (WirePlumber ALSA tuning)..."
    WP_CONF_STAGE="${LOCAL_FW_DIR}/51-qcom.conf"
    if [ -f "$WP_CONF_STAGE" ]; then
        sudo cp "$WP_CONF_STAGE" "$ROOTFS_DIR/tmp/51-qcom.conf"
        echo ">>>   51-qcom.conf staged."
    else
        echo ">>>   WARNING: 51-qcom.conf not found at $WP_CONF_STAGE"
    fi

    echo ">>> Staging remoteproc sequencing rule..."
    RPROC_RULE="${LOCAL_FW_DIR}/82-beryllium-remoteproc.rules"
    RPROC_RULE_ROOT="${SCRIPT_DIR}/82-beryllium-remoteproc.rules"
    RPROC_TRIGGER="${LOCAL_FW_DIR}/remoteproc-adsp-trigger.sh"
    RPROC_TRIGGER_ROOT="${SCRIPT_DIR}/remoteproc-adsp-trigger.sh"

    if [ -f "$RPROC_RULE" ]; then
        sudo cp "$RPROC_RULE" "$ROOTFS_DIR/tmp/82-beryllium-remoteproc.rules"
    elif [ -f "$RPROC_RULE_ROOT" ]; then
        sudo cp "$RPROC_RULE_ROOT" "$ROOTFS_DIR/tmp/82-beryllium-remoteproc.rules"
    else
        echo ">>> WARNING: remoteproc udev rule not found — DSP sequencing will not be gated."
    fi

    if [ -f "$RPROC_TRIGGER" ]; then
        sudo cp "$RPROC_TRIGGER" "$ROOTFS_DIR/tmp/remoteproc-adsp-trigger.sh"
    elif [ -f "$RPROC_TRIGGER_ROOT" ]; then
        sudo cp "$RPROC_TRIGGER_ROOT" "$ROOTFS_DIR/tmp/remoteproc-adsp-trigger.sh"
    else
        echo ">>> WARNING: remoteproc trigger script not found."
    fi
fi

if has_quirk "firmware_source_local" && [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>> Staging firmware archive for post-apt re-application..."
    sudo cp "$LOCAL_FW_ARCHIVE" "$ROOTFS_DIR/tmp/firmware.tar.gz"
fi

# -------------------------------------------------------
# Step 3: Firmware staging (pre-chroot, method=git)
# -------------------------------------------------------
if [ "$FIRMWARE_METHOD" = "git" ] && [ -n "$FIRMWARE_REPO" ]; then
    FW_STAGED=false
    USE_LOCAL_FIRST=false

    if has_quirk "firmware_source_local" && [ -f "$LOCAL_FW_ARCHIVE" ]; then
        echo ""
        echo ">>> Local firmware bundle detected: $(basename "$LOCAL_FW_ARCHIVE")"
        read -p ">>> Apply local bundle before git clone? [Y/n]: " BUNDLE_CHOICE
        case "${BUNDLE_CHOICE:-Y}" in
            [Nn]*) USE_LOCAL_FIRST=false ;;
            *)     USE_LOCAL_FIRST=true  ;;
        esac
    fi

    if [ "$USE_LOCAL_FIRST" = "true" ]; then
        echo ">>> Applying local firmware bundle (base layer)..."
        sudo tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTFS_DIR/"
        echo ">>> Local firmware bundle applied."
        FW_STAGED=true
    fi

    echo ">>> Cloning firmware repo: $FIRMWARE_REPO"
    FW_TMP=$(mktemp -d /tmp/fw_XXXX)
    if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>/dev/null; then
        echo ">>> Copying git firmware tree into rootfs..."
        sudo cp -r "$FW_TMP/fw/lib/." "$ROOTFS_DIR/lib/"
        if [ -d "$FW_TMP/fw/usr" ]; then
            sudo cp -r "$FW_TMP/fw/usr/." "$ROOTFS_DIR/usr/"
        fi
        echo ">>> Git firmware staged."
        FW_STAGED=true
    else
        echo ">>> WARNING: git clone failed."
        if [ "$USE_LOCAL_FIRST" = "false" ] && has_quirk "firmware_source_local" && [ -f "$LOCAL_FW_ARCHIVE" ]; then
            echo ">>> Falling back to local firmware archive..."
            sudo tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTFS_DIR/"
            echo ">>> Local firmware archive applied."
            FW_STAGED=true
        fi
    fi
    rm -rf "$FW_TMP"

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
            echo ">>> WARNING: OnePlus6 fallback not found on host."
            echo ">>>   Run: sudo apt install linux-firmware"
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
# Step 4b: Write kernel hook files on host (mkbootimg devices only)
# -------------------------------------------------------
if [ "$BOOT_METHOD" = "mkbootimg" ]; then
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
HOOKEOF

    sudo tee /tmp/bootimg-initrd-hook > /dev/null << 'INITRDEOF'
#!/bin/sh
/etc/kernel/postinst.d/zz-qcom-bootimg "$1"
INITRDEOF

    sudo cp /tmp/zz-qcom-bootimg "$ROOTFS_DIR/tmp/zz-qcom-bootimg"
    sudo cp /tmp/bootimg-initrd-hook "$ROOTFS_DIR/tmp/bootimg-initrd-hook"
fi

# -------------------------------------------------------
# Step 5: Chroot build script
# -------------------------------------------------------
CHROOT_SCRIPT=$(mktemp /tmp/chroot_setup_XXXX.sh)

# Part 1: inject host variables (expanded)
cat > "$CHROOT_SCRIPT" << INJECT_EOF
#!/bin/bash
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive

UBUNTU_RELEASE="${UBUNTU_RELEASE}"
USERNAME="${USERNAME}"
PASSWORD="${PASSWORD}"
DEVICE_HOSTNAME="${DEVICE_HOSTNAME}"
DEVICE_CODENAME="${DEVICE_CODENAME}"
DEVICE_BRAND="${DEVICE_BRAND}"
DEVICE_PACKAGES="${DEVICE_PACKAGES}"
DEVICE_SERVICES="${DEVICE_SERVICES}"
DEVICE_QUIRKS="${DEVICE_QUIRKS}"
BOOT_METHOD="${BOOT_METHOD}"
FIRMWARE_METHOD="${FIRMWARE_METHOD}"
UI_NAME="${UI_NAME}"
UI_DM="${UI_DM}"
EXTRA_PKG="${EXTRA_PKG}"
BUILD_COLOR="${BUILD_COLOR}"
INJECT_EOF

# Part 2: build logic (single-quoted, no outer expansion)
cat >> "$CHROOT_SCRIPT" << 'CHROOT_EOF'
echo "nameserver 8.8.8.8" > /etc/resolv.conf

has_quirk() { echo " ${DEVICE_QUIRKS} " | grep -qw "$1"; }

# --- 1. Ubuntu APT sources ---
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse\n" > /etc/apt/sources.list
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse\n" >> /etc/apt/sources.list
printf "deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse\n" >> /etc/apt/sources.list
apt-get update

# --- 2. Bootstrap minimal tools ---
apt-get install -y curl wget ca-certificates gnupg

# --- 3. Mobian repo ---
curl -fsSL https://repo.mobian.org/mobian.gpg -o /etc/apt/trusted.gpg.d/mobian.gpg
printf "deb http://repo.mobian.org/ staging main non-free-firmware\n" > /etc/apt/sources.list.d/mobian.list
apt-get update
apt-get upgrade -y

# --- 4. Base system ---
apt-get install -y \
    initramfs-tools sudo \
    network-manager modemmanager \
    linux-firmware bluez \
    pipewire pipewire-pulse wireplumber \
    openssh-server locales tzdata

# --- 5. Kernel ---
echo ">>> Installing kernel..."
dpkg -i /tmp/kernel_payload/*.deb || apt-get install -f -y
update-initramfs -c -k all

# --- 6. UI + Display Manager ---
echo ">>> Installing UI: $UI_NAME (DM: $UI_DM)"
case "$UI_NAME" in
phosh)
    apt-get install -y phosh greetd
    apt-get install -y squeekboard 2>/dev/null || \
        apt-get install -y phosh-osk-stub 2>/dev/null || \
        echo ">>> WARNING: No OSK package available — virtual keyboard will not be installed"
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"/usr/bin/phosh\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
ubuntu-desktop-minimal)
    apt-get install -y -t "$UBUNTU_RELEASE" ubuntu-desktop-minimal
    systemctl enable gdm3
    mkdir -p /etc/dconf/db/local.d
    cat > /etc/dconf/db/local.d/01-mobuntu-theme << DCONF
[org/gnome/desktop/interface]
accent-color='$BUILD_COLOR'

[org/gnome/nautilus/desktop]
volumes-visible=false
DCONF
    dconf update 2>/dev/null || true
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
    apt-get install -y -t "$UBUNTU_RELEASE" lomiri squeekboard greetd
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"lomiri\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
*)
    echo ">>> WARNING: Unknown UI '$UI_NAME', falling back to phosh."
    apt-get install -y phosh greetd
    apt-get install -y squeekboard 2>/dev/null || \
        apt-get install -y phosh-osk-stub 2>/dev/null || true
    useradd -r -m -G video,render,input,audio greeter 2>/dev/null || \
        usermod -aG video,render,input,audio greeter 2>/dev/null || true
    mkdir -p /etc/greetd
    printf "[terminal]\nvt = 1\n\n[default_session]\ncommand = \"/usr/bin/phosh\"\nuser = \"greeter\"\n" > /etc/greetd/config.toml
    systemctl enable greetd
    ;;
esac

for dm in gdm3 lightdm sddm greetd; do
    [ "$dm" != "$UI_DM" ] && systemctl disable $dm 2>/dev/null || true
done

# --- 7. Device packages + alsa-ucm-conf ---
apt-get install -y -t "$UBUNTU_RELEASE" alsa-ucm-conf || apt-get install -y alsa-ucm-conf
if [ -n "$DEVICE_PACKAGES" ]; then
    apt-get install -y $DEVICE_PACKAGES
fi

# --- 8. Re-apply firmware archive post-apt (local bundle devices only) ---
if has_quirk "firmware_source_local" && [ -f "/tmp/firmware.tar.gz" ]; then
    echo ">>> Re-applying firmware archive (post-apt)..."
    tar -xzf /tmp/firmware.tar.gz -C /
fi

# --- 9. Adreno 630 GPU firmware (Qualcomm only) ---
if has_quirk "qcom_services"; then
    echo ">>> Fetching Adreno 630 GPU firmware..."
    KERNEL_ORG="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
    fetch_fw() {
        local DEST="$1" FILE="$2"
        mkdir -p "$DEST"
        curl -L -f -s -o "$DEST/$(basename $FILE)" "$KERNEL_ORG/$FILE" \
            && echo ">>>   OK: $FILE" \
            || echo ">>>   WARN: Failed to fetch $FILE (non-fatal)"
        return 0
    }
    fetch_fw "/lib/firmware/qcom" "qcom/a630_sqe.fw"
    fetch_fw "/lib/firmware/qcom" "qcom/a630_gmu.bin"
    if [ "$FIRMWARE_METHOD" != "git" ]; then
        fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"
    fi
fi

# --- 10. Qualcomm services (gated) ---
if has_quirk "qcom_services"; then
    mkdir -p /etc/systemd/system/pd-mapper.service.d
    printf '[Unit]\nAfter=qrtr-ns.service\nRequires=qrtr-ns.service\n' \
        > /etc/systemd/system/pd-mapper.service.d/ordering.conf
    mkdir -p /etc/systemd/system/rmtfs.service.d
    printf '[Unit]\nAfter=qrtr-ns.service\nRequires=qrtr-ns.service\n' \
        > /etc/systemd/system/rmtfs.service.d/ordering.conf

    systemctl enable qrtr-ns  2>/dev/null || true
    systemctl enable rmtfs    2>/dev/null || true
    systemctl enable pd-mapper 2>/dev/null || true
    systemctl enable tqftpserv 2>/dev/null || true
    systemctl daemon-reload   2>/dev/null || true

    systemctl mask alsa-state   2>/dev/null || true
    systemctl mask alsa-restore 2>/dev/null || true

    if [ -f /tmp/qcom-firmware ]; then
        cp /tmp/qcom-firmware /usr/share/initramfs-tools/hooks/qcom-firmware
        chmod +x /usr/share/initramfs-tools/hooks/qcom-firmware
        echo ">>>   qcom-firmware hook installed."
    else
        echo ">>>   WARNING: qcom-firmware hook not staged."
    fi

    if [ -f /tmp/51-qcom.conf ]; then
        mkdir -p /usr/share/wireplumber/wireplumber.conf.d
        cp /tmp/51-qcom.conf /usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf
        echo ">>>   51-qcom.conf installed."
    else
        echo ">>>   WARNING: 51-qcom.conf not staged."
    fi

    if [ -f /tmp/82-beryllium-remoteproc.rules ] && [ -f /tmp/remoteproc-adsp-trigger.sh ]; then
        cp /tmp/82-beryllium-remoteproc.rules /usr/lib/udev/rules.d/82-beryllium-remoteproc.rules
        cp /tmp/remoteproc-adsp-trigger.sh /usr/lib/udev/remoteproc-adsp-trigger.sh
        chmod +x /usr/lib/udev/remoteproc-adsp-trigger.sh
        udevadm control --reload-rules 2>/dev/null || true
        echo ">>>   Remoteproc sequencing rule installed."
    else
        echo ">>>   WARNING: remoteproc rule/trigger not staged."
    fi
fi

# Device-specific services (all devices)
if [ -n "$DEVICE_SERVICES" ]; then
    for svc in $DEVICE_SERVICES; do
        systemctl enable $svc 2>/dev/null || true
    done
fi

# --- 11. User account ---
useradd -m -s /bin/bash -G sudo,video,audio,netdev,dialout "$USERNAME" || true
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 0440 /etc/sudoers.d/mobuntu-user

# --- 12. Hostname ---
echo "$DEVICE_HOSTNAME" > /etc/hostname
printf "127.0.0.1   localhost\n127.0.1.1   $DEVICE_HOSTNAME\n::1         localhost ip6-localhost ip6-loopback\n" > /etc/hosts

# --- 13. Kernel hook (mkbootimg only) ---
if [ "$BOOT_METHOD" = "mkbootimg" ]; then
    mkdir -p /etc/kernel/postinst.d /etc/initramfs/post-update.d
    cp /tmp/zz-qcom-bootimg /etc/kernel/postinst.d/zz-qcom-bootimg
    cp /tmp/bootimg-initrd-hook /etc/initramfs/post-update.d/bootimg
    chmod +x /etc/kernel/postinst.d/zz-qcom-bootimg
    chmod +x /etc/initramfs/post-update.d/bootimg
fi

# --- 14. /boot/efi stub ---
mkdir -p /boot/efi

# --- 15. Extra packages ---
if [ -n "$EXTRA_PKG" ]; then
    apt-get install -y $EXTRA_PKG
fi

# --- 16. Build mkbootimg natively (mkbootimg only) ---
if [ "$BOOT_METHOD" = "mkbootimg" ]; then
    echo ">>> Building mkbootimg natively for ARM64..."
    apt-get install -y git build-essential
    rm -rf /tmp/mkbootimg-build
    git clone --depth=1 https://github.com/osm0sis/mkbootimg /tmp/mkbootimg-build
    sed -i 's/-Werror//g' /tmp/mkbootimg-build/Makefile
    sed -i 's/-Werror//g' /tmp/mkbootimg-build/libmincrypt/Makefile
    make -C /tmp/mkbootimg-build
    cp /tmp/mkbootimg-build/mkbootimg /usr/local/bin/mkbootimg
    cp /tmp/mkbootimg-build/unpackbootimg /usr/local/bin/unpackbootimg
    chmod +x /usr/local/bin/mkbootimg /usr/local/bin/unpackbootimg
    rm -rf /tmp/mkbootimg-build
    echo ">>> mkbootimg (ARM64 native) installed."
fi

# --- Cleanup ---
rm -rf /tmp/kernel_payload /tmp/firmware.tar.gz \
    /tmp/zz-qcom-bootimg /tmp/bootimg-initrd-hook \
    /tmp/qcom-firmware /tmp/51-qcom.conf \
    /tmp/82-beryllium-remoteproc.rules /tmp/remoteproc-adsp-trigger.sh
apt-get clean
echo ">>> Chroot build complete."
CHROOT_EOF

sudo cp "$CHROOT_SCRIPT" "$ROOTFS_DIR/tmp/chroot_setup.sh"
sudo chmod +x "$ROOTFS_DIR/tmp/chroot_setup.sh"
rm "$CHROOT_SCRIPT"

echo ">>> Executing chroot build (this will take a while)..."
if [ "$HOST_IS_ARM64" = "true" ]; then
    sudo chroot "$ROOTFS_DIR" /bin/bash /tmp/chroot_setup.sh
else
    sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS_DIR/usr/bin/"
    sudo chroot "$ROOTFS_DIR" /usr/bin/qemu-aarch64-static /bin/bash /tmp/chroot_setup.sh
fi

# -------------------------------------------------------
# Post-chroot: Re-apply firmware archive (wins over apt)
# -------------------------------------------------------
if has_quirk "firmware_source_local" && [ -f "$LOCAL_FW_ARCHIVE" ]; then
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
echo "   Run verify_build.sh then script 5 to seal.‍" # ‍ = ZWJ watchdog signal
echo "======================================================="
