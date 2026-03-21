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
echo "3) GNOME Vanilla (ubuntu-desktop-minimal)"
echo "4) KDE Plasma Vanilla (kde-plasma-desktop)"
echo "5) Ubuntu Unity Vanilla (ubuntu-unity-desktop)"
echo "6) XFCE Vanilla (xubuntu-core)"
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
       UI_PKG="ubuntu-desktop-minimal onboard"
       DM_PKG="gdm3"
       UI_NAME="gnome-vanilla" 
       ;;
    4) 
       UI_PKG="kde-plasma-desktop onboard"
       DM_PKG="sddm"
       UI_NAME="kde-vanilla" 
       ;;
    5) 
       UI_PKG="ubuntu-unity-desktop onboard"
       DM_PKG="lightdm"
       UI_NAME="unity-vanilla" 
       ;;
    6) 
       UI_PKG="xubuntu-core onboard"
       DM_PKG="lightdm"
       UI_NAME="xfce-vanilla" 
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
read -p "Enter desired RootFS image size in GB (Minimum 8) [default: 12]: " IMG_INPUT
IMG_INPUT=${IMG_INPUT:-12}
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
