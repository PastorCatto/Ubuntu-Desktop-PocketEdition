#!/bin/bash
# fetch-firmware.sh — downloads and installs device firmware + kernel
# Called from image.yaml with env vars injected by debos

set -ex

: "${DEVICE:?DEVICE env var required}"
: "${FW_ARCHIVE_URL:?FW_ARCHIVE_URL env var required}"
: "${KERNEL_IMAGE_URL:?KERNEL_IMAGE_URL env var required}"
: "${KERNEL_HEADERS_URL:?KERNEL_HEADERS_URL env var required}"

TMPDIR="/tmp/mobuntu-fw-${DEVICE}"
mkdir -p "$TMPDIR"
cd "$TMPDIR"

echo "Fetching firmware archive for ${DEVICE}..."
wget -q --show-progress "$FW_ARCHIVE_URL" -O firmware.tar.gz

mkdir -p firmware
tar -C firmware -xzf firmware.tar.gz
ls firmware/

echo "Installing firmware..."
cp -RT firmware/* /usr/
rm -rf firmware firmware.tar.gz

echo "Fetching kernel packages..."
wget -q --show-progress "$KERNEL_IMAGE_URL"   -O kernel-image.deb
wget -q --show-progress "$KERNEL_HEADERS_URL" -O kernel-headers.deb

echo "Installing kernel..."
dpkg -i --force-overwrite kernel-image.deb kernel-headers.deb

echo "Cleanup..."
cd /
rm -rf "$TMPDIR"

echo "Firmware and kernel installed for ${DEVICE}."
