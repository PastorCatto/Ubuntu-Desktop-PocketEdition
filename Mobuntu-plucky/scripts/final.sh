#!/bin/sh
# final.sh — post-image system configuration
# Upstream logic preserved; firmware/kernel install moved to fetch-firmware.sh

set -ex

echo "Fix alsa-ucm-conf"
wget https://repo.mobian.org/pool/main/a/alsa-ucm-conf/alsa-ucm-conf_1.2.15.3-1mobian3_all.deb
dpkg -i --force-overwrite alsa-ucm-conf_1.2.15.3-1mobian3_all.deb
rm -f alsa-ucm-conf_*.deb

echo "Mask for working speakers"
systemctl mask alsa-state alsa-restore
systemctl set-default graphical.target

echo "Fix resolv.conf for chroot network access"
rm -rf /etc/resolv.conf
echo "nameserver 1.1.1.1" > /etc/resolv.conf

echo "Clean packages"
apt-get -y autoremove --purge

echo "Disable GNOME extension version validation"
gsettings set org.gnome.shell disable-extension-version-validation true

echo "Enable shell extensions"
gnome-extensions enable aurora-shell@luminusos.github.io
gnome-extensions enable touchup@mityax
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com

echo "Enable rootfs resize service"
systemctl enable grow-rootfs.service
