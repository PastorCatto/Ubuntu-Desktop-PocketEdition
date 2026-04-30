#!/bin/sh

set -x

echo "Update full source.list"
apt-get update
apt-get full-upgrade -y

echo "Remove for successful generated initrd"
rm -rf /etc/kernel/postinst.d/dkms
