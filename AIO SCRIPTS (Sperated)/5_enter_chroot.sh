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
