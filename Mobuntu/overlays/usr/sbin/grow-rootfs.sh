#!/bin/sh

# Identify the root partition
ROOT_DEV=$(findmnt / -o SOURCE -n)
ROOT_DISK=$(lsblk -no PKNAME $ROOT_DEV)
PART_NUM=$(cat /sys/class/block/${ROOT_DEV#/dev/}/partition)

# Resize partition and filesystem
growpart /dev/$ROOT_DISK $PART_NUM
resize2fs $ROOT_DEV

# Disable this service
systemctl disable grow-rootfs.service
