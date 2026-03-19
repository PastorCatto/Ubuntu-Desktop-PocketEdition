#!/bin/bash
set -e

echo "======================================================="
echo "   [8/8] Lomiri UI Hotfix & Greeter Patch"
echo "======================================================="
echo ">>> Did your Lomiri install kick back dbus/systemd errors?"
echo ">>> Look for: 'Failed to connect to bus', 'dpkg: error processing package',"
echo ">>> or if you booted into an ugly PC-style login box previously."
echo ">>> This script will surgical-strike the chroot, force-configure dpkg,"
echo ">>> nuke the PC greeter, and lock LightDM to Ubuntu Touch."
echo "-------------------------------------------------------"
read -p "Apply the Lomiri hotfix to the chroot now? (y/n) [default: y]: " APPLY_FIX
APPLY_FIX=${APPLY_FIX:-y}

if [ "$APPLY_FIX" == "y" ]; then
    if [ ! -d "Ubuntu-Beryllium" ]; then
        echo ">>> [ERROR] Ubuntu-Beryllium directory not found."
        exit 1
    fi
    
    echo ">>> Mounting virtual filesystems..."
    sudo mount --bind /dev Ubuntu-Beryllium/dev 2>/dev/null || true
    sudo mount --bind /dev/pts Ubuntu-Beryllium/dev/pts 2>/dev/null || true
    sudo mount --bind /proc Ubuntu-Beryllium/proc 2>/dev/null || true
    sudo mount --bind /sys Ubuntu-Beryllium/sys 2>/dev/null || true

    echo ">>> Injecting hotfix into chroot..."
    sudo chroot Ubuntu-Beryllium /bin/bash << 'CHROOT_EOF'
export DEBIAN_FRONTEND=noninteractive
echo ">>> Forcing package configuration..."
dpkg --configure -a || true
apt-get update
apt-get install -y lomiri lomiri-greeter ubuntu-touch-session lightdm

echo ">>> Purging GTK greeter to prevent hybrid boot..."
apt-get purge -y lightdm-gtk-greeter || true
apt-get autoremove -y

echo ">>> Hardcoding LightDM configuration for Lomiri..."
mkdir -p /etc/lightdm/lightdm.conf.d
cat << 'CONF_EOF' > /etc/lightdm/lightdm.conf.d/99-lomiri.conf
[Seat:*]
greeter-session=lomiri-greeter
user-session=lomiri
CONF_EOF
CHROOT_EOF

    echo ">>> Unmounting virtual filesystems..."
    sudo umount Ubuntu-Beryllium/sys 2>/dev/null || true
    sudo umount Ubuntu-Beryllium/proc 2>/dev/null || true
    sudo umount Ubuntu-Beryllium/dev/pts 2>/dev/null || true
    sudo umount Ubuntu-Beryllium/dev 2>/dev/null || true
    
    echo ">>> Lomiri Hotfix successfully applied! You can now run bash 6_seal_rootfs.sh."
else
    echo ">>> Skipping Lomiri hotfix."
fi
