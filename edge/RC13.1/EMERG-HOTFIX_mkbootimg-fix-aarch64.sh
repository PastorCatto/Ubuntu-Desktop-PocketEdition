#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "==================================================="
echo "  PUT THIS SCRIPT IN THE /tmp DIR OF YOUR CHROOT   "
echo "  (osm0sis fork - optimized for droid-juicer)      "
echo "==================================================="

# 1. Ask for sudo privileges upfront
sudo -v

echo "[1/6] Installing build dependencies..."
sudo apt update -qq || true
sudo apt install -y git build-essential

echo "[2/6] Cleaning up any previous or broken installations..."
sudo rm -f /usr/local/bin/mkbootimg
sudo rm -f /usr/local/bin/unpackbootimg
sudo rm -rf /opt/mkbootimg_tools
rm -rf /tmp/mkbootimg_build

echo "[3/6] Cloning the osm0sis source..."
mkdir -p /tmp/mkbootimg_build
cd /tmp/mkbootimg_build
git clone https://github.com/osm0sis/mkbootimg.git .

echo "[4/6] Patching Makefiles to bypass strict GCC warnings (-Werror)..."
# Ubuntu 26.04 GCC is much stricter than when this C code was written
sed -i 's/-Werror//g' Makefile
sed -i 's/-Werror//g' libmincrypt/Makefile

echo "[5/6] Compiling natively for ARM64..."
make clean
make

echo "[6/6] Installing binaries to /usr/local/bin..."
sudo cp mkbootimg unpackbootimg /usr/local/bin/
sudo chmod +x /usr/local/bin/mkbootimg /usr/local/bin/unpackbootimg

echo "Cleaning up temporary build files..."
cd ~
rm -rf /tmp/mkbootimg_build

echo "==================================================="
echo "  Installation Complete!                           "
echo "==================================================="
echo "Verifying installation:"
which mkbootimg
which unpackbootimg
echo ""
echo "Both tools are now globally available and ready for droid-juicer."
