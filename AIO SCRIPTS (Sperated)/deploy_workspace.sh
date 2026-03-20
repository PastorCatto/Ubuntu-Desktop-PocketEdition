#!/bin/bash
set -e

echo "======================================================="
echo "   ROM Cooker - Modular Workspace Generator (v4 - Minimal)"
echo "======================================================="
echo ">>> Generating independent scripts..."
echo ""

# ==============================================================================
#                      START OF SCRIPT 1: PREFLIGHT
# ==============================================================================

cat << 'EOF_1' > 1_preflight.sh
#!/bin/bash
set -e
echo "======================================================="
echo "   [1/7] Pre-Flight & Workspace Setup"
echo "======================================================="

echo ">>> Checking and installing host dependencies..."
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    debootstrap qemu-user-static qemu-system-aarch64 sudo e2fsprogs curl wget \
    xz-utils gzip zip ca-certificates file fdisk git python3 \
    python3-pip python3-venv sshpass tar kpartx dosfstools binfmt-support

echo "======================================================="
echo "   Configuration Prompts"
echo "======================================================="
read -p "Enter desired username [default: ubuntu]: " USERNAME
USERNAME=${USERNAME:-ubuntu}

read -s -p "Enter desired password [default: ubuntu]: " PASSWORD
echo ""
PASSWORD=${PASSWORD:-ubuntu}

echo "Select Desktop/Mobile UI:"
echo "--- Mobile Shells (Touch-First) ---"
echo "1) Phosh (Purism GNOME + Squeekboard)"
echo "2) Plasma Mobile (KDE Mobile + Maliit)"
echo "--- Desktop Flavors (Tablet/PC) ---"
echo "3) GNOME Minimal (Standard Ubuntu)"
echo "4) KDE Plasma Minimal (Kubuntu)"
echo "5) Ubuntu Unity Minimal (The Classic)"
echo "6) XFCE Minimal (Lightweight Xubuntu)"
echo "7) Custom (Provide your own)"
read -p "Choice [1-7, default 1]: " UI_CHOICE
UI_CHOICE=${UI_CHOICE:-1}

case $UI_CHOICE in
    2) 
       UI_PKG="plasma-mobile maliit-keyboard"
       DM_PKG="sddm"
       UI_NAME="plasma-mobile" 
       ;;
    3) 
       UI_PKG="gnome-session gnome-terminal nautilus onboard"
       DM_PKG="gdm3"
       UI_NAME="gnome-minimal" 
       ;;
    4) 
       UI_PKG="plasma-desktop konsole dolphin onboard"
       DM_PKG="sddm"
       UI_NAME="kde-minimal" 
       ;;
    5) 
       UI_PKG="unity-session gnome-terminal nautilus onboard"
       DM_PKG="lightdm"
       UI_NAME="unity-minimal" 
       ;;
    6) 
       UI_PKG="xfce4 xfce4-terminal thunar onboard"
       DM_PKG="lightdm"
       UI_NAME="xfce-minimal" 
       ;;
    7) 
       read -p "Enter full core package name(s): " CUSTOM_PKG
       read -p "Enter required Display Manager (gdm3, lightdm, sddm): " CUSTOM_DM
       UI_PKG="$CUSTOM_PKG"
       DM_PKG="$CUSTOM_DM"
       UI_NAME="custom"
       ;;
    *) 
       UI_PKG="phosh phosh-core phosh-mobile-settings squeekboard"
       DM_PKG="gdm3"
       UI_NAME="phosh" 
       ;;
esac

echo ""
read -p "Enter desired RootFS image size in GB (Minimum 8) [default: 8]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-8}
if [ "$IMG_INPUT" -lt 8 ]; then
    echo ">>> Forcing minimum size of 8GB."
    IMAGE_SIZE=8
else
    IMAGE_SIZE=$IMG_INPUT
fi

echo ""
read -p "Enter any EXTRA packages to install (space separated) [default: none]: " EXTRA_PKG
EXTRA_PKG=${EXTRA_PKG:-}

cat << EOF_ENV > build.env
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
UI_PKG="$UI_PKG"
DM_PKG="$DM_PKG"
UI_NAME="$UI_NAME"
EXTRA_PKG="$EXTRA_PKG"
IMAGE_SIZE="$IMAGE_SIZE"
UBUNTU_RELEASE="noble"
FIRMWARE_STASH="\$HOME/firmware_stash"
EOF_ENV

echo ">>> Configuration locked and saved to build.env."
echo ">>> Pre-flight complete. Proceed to Script 2."
EOF_1

# ==============================================================================
#                      START OF SCRIPT 2: PMOS SETUP & DUAL UUID CLONING
# ==============================================================================

cat << 'EOF_2' > 2_pmos_setup.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [2/7] pmbootstrap Initialization & Dual UUID Cloning"
echo "======================================================="

echo ">>> Pulling latest pmbootstrap from upstream Git..."
mkdir -p "$HOME/.local/src" "$HOME/.local/bin"
if [ ! -d "$HOME/.local/src/pmbootstrap" ]; then
    git clone https://gitlab.postmarketos.org/postmarketOS/pmbootstrap.git "$HOME/.local/src/pmbootstrap"
fi
ln -sf "$HOME/.local/src/pmbootstrap/pmbootstrap.py" "$HOME/.local/bin/pmbootstrap"
export PATH="$HOME/.local/bin:$PATH"

DEFAULT_WORK="$HOME/.local/var/pmbootstrap"
if [ -f "$HOME/.config/pmbootstrap.cfg" ]; then
    PM_WORK_DIR=$(pmbootstrap config work 2>/dev/null || echo "$DEFAULT_WORK")
else
    PM_WORK_DIR="$DEFAULT_WORK"
fi

echo "======================================================="
echo "   ATTENTION: MANUAL CONFIGURATION REQUIRED"
echo "======================================================="
echo "CRITICAL INSTRUCTIONS:"
echo "1. Channel: MUST choose 'v25.06' (Fixes blank screen bug)"
echo "2. Vendor: xiaomi"
echo "3. Device: beryllium"
echo "4. User interface: none"
echo "5. Init system: systemd"
echo "======================================================="
read -p "Press ENTER when you understand and are ready to begin..."

pmbootstrap init

# --- Kernel Cmdline Injection ---
echo ">>> Injecting rootdelay and verbose boot flags..."
DEVICEINFO_PATH=$(find "$PM_WORK_DIR/cache_git/pmaports/device" -name "device-xiaomi-beryllium" -type d 2>/dev/null)/deviceinfo
if [ -f "$DEVICEINFO_PATH" ]; then
    if ! grep -q "rootdelay=5" "$DEVICEINFO_PATH"; then
        sed -i 's/deviceinfo_kernel_cmdline="/deviceinfo_kernel_cmdline="rootdelay=5 PMOS_NOSPLASH console=tty0 /' "$DEVICEINFO_PATH"
        echo ">>> Successfully patched Beryllium kernel cmdline!"
    fi
else
    echo ">>> [WARNING] Could not find deviceinfo file to patch cmdline."
fi

# --- Generation & Extraction ---
echo ">>> Triggering pmbootstrap rootfs generation..."
pmbootstrap install

PM_WORK_DIR=$(pmbootstrap config work)
PMOS_CHROOT_PATH="$PM_WORK_DIR/chroot_rootfs_xiaomi-beryllium"

echo ">>> Verifying final pmbootstrap chroot generation..."
if [ -d "$PMOS_CHROOT_PATH/lib/modules" ]; then
    echo ">>> pmOS Chroot successfully verified!"
    
    rm -f pmos_harvest
    ln -s "$PMOS_CHROOT_PATH" pmos_harvest
    
    echo ">>> Exporting Android ABL-compatible boot image..."
    pmbootstrap export
    cp /tmp/postmarketOS-export/boot.img pmos_boot.img
    
    echo ">>> Extracting Boot & Root UUIDs from generated pmOS fstab..."
    PMOS_ROOT_UUID=$(awk '$2 == "/" {print $1}' "$PMOS_CHROOT_PATH/etc/fstab" | sed 's/UUID=//' || true)
    PMOS_BOOT_UUID=$(awk '$2 == "/boot" {print $1}' "$PMOS_CHROOT_PATH/etc/fstab" | sed 's/UUID=//' || true)
    
    sed -i '/^PMOS_ROOT_UUID=/d' build.env 2>/dev/null || true
    sed -i '/^PMOS_BOOT_UUID=/d' build.env 2>/dev/null || true
    
    if [ -n "$PMOS_ROOT_UUID" ]; then
        echo "PMOS_ROOT_UUID=\"$PMOS_ROOT_UUID\"" >> build.env
        echo ">>> Successfully cloned expected RootFS UUID:  $PMOS_ROOT_UUID"
    fi
    
    if [ -n "$PMOS_BOOT_UUID" ]; then
        echo "PMOS_BOOT_UUID=\"$PMOS_BOOT_UUID\"" >> build.env
        echo ">>> Successfully cloned expected BootFS UUID:  $PMOS_BOOT_UUID"
    fi
    
    echo ">>> System linked and ABL boot image secured. Proceed to Script 3."
else
    echo ">>> [ERROR] Could not find the generated pmOS chroot at $PMOS_CHROOT_PATH."
    exit 1
fi
EOF_2

# ==============================================================================
#                      START OF SCRIPT 3: FIRMWARE FETCHER
# ==============================================================================

cat << 'EOF_3' > 3_firmware_fetcher.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [3/7] Firmware Fetcher (Mobian Extraction)"
echo "======================================================="

if [ -d "$FIRMWARE_STASH" ] && [ "$(ls -A $FIRMWARE_STASH 2>/dev/null)" ]; then
    echo ">>> Found existing firmware stash at $FIRMWARE_STASH. Skipping network fetch."
else
    echo ">>> Local firmware stash is empty."
    echo ">>> Please ensure your Poco F1 is powered on, connected to Wi-Fi,"
    echo ">>> and actively running Mobian."
    echo ""
    read -p "Enter Poco F1 IP Address (e.g., 192.168.1.50): " PHONE_IP
    read -p "Enter Mobian username [default: mobian]: " PHONE_USER
    PHONE_USER=${PHONE_USER:-mobian}
    read -s -p "Enter Mobian password [default: 1234]: " PHONE_PASS
    echo ""
    PHONE_PASS=${PHONE_PASS:-1234}
    
    echo ">>> [Phone Side] Archiving hardware profiles via SSH..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" \
        "echo '$PHONE_PASS' | sudo -S tar -czpf ~/mobian_harvest.tar.gz /usr/share/alsa/ucm2/ /etc/ModemManager/ /lib/udev/rules.d/ /lib/firmware/postmarketos/" || true
    
    echo ">>> [Host Side] Downloading the archive..."
    mkdir -p "$FIRMWARE_STASH"
    sshpass -p "$PHONE_PASS" scp -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP:~/mobian_harvest.tar.gz" "$FIRMWARE_STASH/raw_harvest.tar.gz"
    
    echo ">>> [Host Side] Extracting into stash..."
    tar -xzpf "$FIRMWARE_STASH/raw_harvest.tar.gz" -C "$FIRMWARE_STASH/"
    rm "$FIRMWARE_STASH/raw_harvest.tar.gz"
    
    echo ">>> [Phone Side] Cleaning up temporary files..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" "rm ~/mobian_harvest.tar.gz"
fi

echo ">>> Firmware successfully stashed and secured."
echo ">>> Proceed to Script 4 (The Transplant)."
EOF_3

# ==============================================================================
#                      START OF SCRIPT 4: THE TRANSPLANT (CHROOT BUILD)
# ==============================================================================

cat << 'EOF_4' > 4_the_transplant.sh
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

echo ">>> [Merge] Injecting pmOS kernels & firmware..."
sudo cp -a pmos_harvest/lib/modules/. Ubuntu-Beryllium/lib/modules/
sudo cp -a pmos_harvest/lib/firmware/. Ubuntu-Beryllium/lib/firmware/

sudo mkdir -p Ubuntu-Beryllium/boot/
sudo cp -L pmos_harvest/boot/vmlinuz* Ubuntu-Beryllium/boot/ || true
sudo cp -L pmos_harvest/boot/initramfs* Ubuntu-Beryllium/boot/ || true
if [ -d "pmos_harvest/boot/dtbs" ]; then
    sudo cp -Lr pmos_harvest/boot/dtbs Ubuntu-Beryllium/boot/
fi

echo ">>> [Merge] Injecting stashed Mobian hardware profiles..."
if [ -d "$FIRMWARE_STASH/usr/share/alsa/ucm2" ]; then
    sudo mkdir -p Ubuntu-Beryllium/usr/share/alsa/ucm2/
    sudo cp -a "$FIRMWARE_STASH/usr/share/alsa/ucm2/." Ubuntu-Beryllium/usr/share/alsa/ucm2/ || true
fi

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

# Temporarily disable set -e for the UI install so minor warnings don't kill the script
set +e

# Pre-seed the debconf database so the display manager installs silently
echo "$DM_PKG shared/default-x-display-manager select $DM_PKG" | debconf-set-selections

# Install the UI and Display Manager with --no-install-recommends to kill bloat
apt-get install -y --no-install-recommends $UI_PKG $DM_PKG modemmanager network-manager systemd-resolved

# Hardcode the default display manager to ensure no black screens on boot
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
EOF_4

# ==============================================================================
#                      START OF SCRIPT 5: ENTER CHROOT
# ==============================================================================

cat << 'EOF_5' > 5_enter_chroot.sh
#!/bin/bash
set -e
echo "======================================================="
echo "   [5/7] Enter Chroot Environment (Hardened)"
echo "======================================================="

for d in dev dev/pts proc sys run; do
    if ! mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo mount --bind "/$d" "Ubuntu-Beryllium/$d"
        echo ">>> Mounted /$d"
    fi
done

echo ">>> Entering chroot..."
sudo chroot Ubuntu-Beryllium /bin/bash

echo ">>> Exited. Unmounting virtual filesystems..."
for d in run sys proc dev/pts dev; do
    if mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo umount -l "Ubuntu-Beryllium/$d"
    fi
done
EOF_5

# ==============================================================================
#                      START OF SCRIPT 6: SEAL DUAL ROOTFS/BOOTFS
# ==============================================================================

cat << 'EOF_6' > 6_seal_rootfs.sh
#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [6/7] Finalizing and Sealing Dual-Partition Images"
echo "======================================================="
ROOT_IMG="ubuntu_beryllium_root.img"
BOOT_IMG="ubuntu_beryllium_boot.img"

for d in run sys proc dev/pts dev; do
    if mountpoint -q "Ubuntu-Beryllium/$d"; then
        sudo umount -l "Ubuntu-Beryllium/$d"
    fi
done

echo ">>> [Packing] Allocating 256MB BootFS..."
dd if=/dev/zero of="$BOOT_IMG" bs=1M count=256 status=progress
mkfs.ext4 -L pmOS_boot -U "${PMOS_BOOT_UUID:-$(uuidgen)}" "$BOOT_IMG"

IMG_MB=$((IMAGE_SIZE * 1024))
echo ">>> [Packing] Allocating ${IMAGE_SIZE}GB RootFS..."
dd if=/dev/zero of="$ROOT_IMG" bs=1M count=$IMG_MB status=progress
mkfs.ext4 -L pmOS_root -U "${PMOS_ROOT_UUID:-$(uuidgen)}" "$ROOT_IMG"

mkdir -p mnt_root mnt_boot
sudo mount -o loop "$ROOT_IMG" mnt_root/
sudo mount -o loop "$BOOT_IMG" mnt_boot/

sudo cp -a Ubuntu-Beryllium/. mnt_root/
sudo mv mnt_root/boot/* mnt_boot/ 2>/dev/null || true

sudo umount mnt_root mnt_boot
rm -rf mnt_root mnt_boot

sudo e2fsck -f -y "$ROOT_IMG"
sudo e2fsck -f -y "$BOOT_IMG"

if ! command -v img2simg &> /dev/null; then
    sudo apt-get install -y android-sdk-libsparse-utils || sudo apt-get install -y android-tools-fsutils
fi

ROOT_SPARSE="${ROOT_IMG%.img}_sparse.img"
BOOT_SPARSE="${BOOT_IMG%.img}_sparse.img"

img2simg "$ROOT_IMG" "$ROOT_SPARSE"
img2simg "$BOOT_IMG" "$BOOT_SPARSE"

echo ">>> FLASHING INSTRUCTIONS:"
echo ">>> 1. fastboot flash boot $(pwd)/pmos_boot.img"
echo ">>> 2. fastboot flash system $(pwd)/$BOOT_SPARSE"
echo ">>> 3. fastboot flash userdata $(pwd)/$ROOT_SPARSE"
EOF_6

# ==============================================================================
#                      START OF SCRIPT 7: KERNEL CONFIG
# ==============================================================================

cat << 'EOF_7' > 7_kernel_menuconfig.sh
#!/bin/bash
set -e
echo "======================================================="
echo "   [7/7] Kernel & Device Configuration Hacking"
echo "======================================================="
echo "1) Kernel Menuconfig (Modify drivers)"
echo "2) deviceinfo File (Modify kernel command line)"
read -p "Choice [1-2, default 1]: " HACK_CHOICE
if [ "${HACK_CHOICE:-1}" == "1" ]; then
    pmbootstrap kconfig edit linux-xiaomi-beryllium
else
    PM_WORK_DIR=$(pmbootstrap config work 2>/dev/null || echo "$HOME/.local/var/pmbootstrap")
    nano "$(find "$PM_WORK_DIR/cache_git/pmaports/device" -name "device-xiaomi-beryllium" -type d 2>/dev/null)/deviceinfo"
fi
EOF_7

# ==============================================================================
#                      END OF SCRIPT GENERATION
# ==============================================================================

chmod +x 1_preflight.sh 2_pmos_setup.sh 3_firmware_fetcher.sh 4_the_transplant.sh 5_enter_chroot.sh 6_seal_rootfs.sh 7_kernel_menuconfig.sh

echo ">>> Workspace scripts generated successfully!"
echo ">>> Run 'bash 1_preflight.sh' to begin the process."
