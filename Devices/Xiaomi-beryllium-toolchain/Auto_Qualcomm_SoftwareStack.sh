#!/bin/bash
set -e

# Ensure the user provides the path to the chroot directory
CHROOT_DIR=$1
INNER_SCRIPT="Qualcomm_Compiler.sh"

if [ -z "$CHROOT_DIR" ]; then
    echo "Usage: sudo $0 /path/to/your/chroot"
    exit 1
fi

if [ ! -f "$INNER_SCRIPT" ]; then
    echo "Error: Cannot find $INNER_SCRIPT in the current directory."
    exit 1
fi

echo "--- Preparing Chroot Environment at $CHROOT_DIR ---"

# Mount necessary virtual filesystems for apt and hardware compilation
mount --bind /dev "$CHROOT_DIR/dev"
mount --bind /dev/pts "$CHROOT_DIR/dev/pts"
mount --bind /proc "$CHROOT_DIR/proc"
mount --bind /sys "$CHROOT_DIR/sys"

# Ensure the chroot has internet access to download packages
cp /etc/resolv.conf "$CHROOT_DIR/etc/resolv.conf"

echo "--- Injecting and Executing Payload ---"
# Copy the inner script to the chroot's /tmp directory
cp "$INNER_SCRIPT" "$CHROOT_DIR/tmp/$INNER_SCRIPT"
chmod +x "$CHROOT_DIR/tmp/$INNER_SCRIPT"

# Enter the chroot and run the script
chroot "$CHROOT_DIR" /bin/bash -c "/tmp/$INNER_SCRIPT"

echo "--- Tearing Down Chroot Environment ---"
# Clean up the script
rm -f "$CHROOT_DIR/tmp/$INNER_SCRIPT"

# Unmount the filesystems cleanly
umount "$CHROOT_DIR/sys"
umount "$CHROOT_DIR/proc"
umount "$CHROOT_DIR/dev/pts"
umount "$CHROOT_DIR/dev"

echo "--- Image Prep Complete! You can now safely package your image. ---"