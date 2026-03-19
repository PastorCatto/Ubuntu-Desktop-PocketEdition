#!/bin/bash
set -e
echo "======================================================="
echo "   [5/8] Enter Chroot Environment"
echo "======================================================="
sudo mount --bind /dev Ubuntu-Beryllium/dev
sudo mount --bind /dev/pts Ubuntu-Beryllium/dev/pts
sudo mount --bind /proc Ubuntu-Beryllium/proc
sudo mount --bind /sys Ubuntu-Beryllium/sys

sudo chroot Ubuntu-Beryllium /bin/bash

sudo umount Ubuntu-Beryllium/dev/pts || true
sudo umount Ubuntu-Beryllium/dev || true
sudo umount Ubuntu-Beryllium/proc || true
sudo umount Ubuntu-Beryllium/sys || true
