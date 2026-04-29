#!/bin/sh
# Mobuntu finalization script — runs inside debos chroot after all packages installed
# Equivalent to arkadin91's scripts/final.sh, adapted for beryllium

set -ex

echo ">>> Installing kernel and firmware debs..."
dpkg -i --force-overwrite /opt/linux-image-*.deb
dpkg -i --force-overwrite /opt/linux-headers-*.deb
dpkg -i --force-overwrite /opt/linux-firmware-xiaomi-beryllium-*.deb

echo ">>> Patching alsa-ucm-conf with Mobian SDM845 mappings..."
wget -q --timeout=30 \
    "https://repo.mobian.org/pool/main/a/alsa-ucm-conf/alsa-ucm-conf_1.2.15.3-1mobian3_all.deb" \
    -O /tmp/alsa-ucm-conf-mobian.deb && \
    dpkg -i --force-overwrite /tmp/alsa-ucm-conf-mobian.deb && \
    rm /tmp/alsa-ucm-conf-mobian.deb || \
    echo "[WARN] alsa-ucm-conf mobian patch failed — audio routing may be degraded"

echo ">>> Masking conflicting alsa services..."
systemctl mask alsa-state alsa-restore

echo ">>> Enabling services..."
systemctl enable grow-rootfs.service
systemctl set-default graphical.target

echo ">>> Removing DKMS hook (not needed for prebuilt kernel)..."
rm -f /etc/kernel/postinst.d/dkms

echo ">>> Cleaning up..."
apt-get -y autoremove --purge
rm -f /opt/*.deb

echo ">>> Finalization complete"
