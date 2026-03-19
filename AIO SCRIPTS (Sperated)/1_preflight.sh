#!/bin/bash
set -e
echo "======================================================="
echo "   [1/8] Pre-Flight & Workspace Setup"
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

echo "Select Desktop UI:"
echo "1) Lomiri (Ubuntu Touch experience)"
echo "2) XFCE (Lightweight, best for performance)"
echo "3) GNOME (Modern, heavy, tablet-friendly)"
echo "4) Custom (Provide your own core package names)"
read -p "Choice [1-4, default 1]: " UI_CHOICE

case $UI_CHOICE in
    2) UI_PKG="xfce4 xfce4-goodies xorg"; UI_NAME="xfce" ;;
    3) UI_PKG="ubuntu-desktop-minimal"; UI_NAME="gnome" ;;
    4) 
       read -p "Enter full core package name(s) (e.g., kde-standard): " CUSTOM_PKG
       UI_PKG="$CUSTOM_PKG xorg lightdm"
       UI_NAME="custom"
       ;;
    *) UI_PKG="lomiri lomiri-greeter ubuntu-touch-session lightdm mir-graphics-drivers-desktop"; UI_NAME="lomiri" ;;
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
UI_NAME="$UI_NAME"
EXTRA_PKG="$EXTRA_PKG"
IMAGE_SIZE="$IMAGE_SIZE"
UBUNTU_RELEASE="noble"
FIRMWARE_STASH="\$HOME/firmware_stash"
EOF_ENV

echo ">>> Configuration locked and saved to build.env."
echo ">>> Pre-flight complete. Proceed to Script 2."
