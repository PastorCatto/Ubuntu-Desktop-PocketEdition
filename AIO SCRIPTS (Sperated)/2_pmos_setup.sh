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
