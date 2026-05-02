#!/bin/sh
# final.sh — post-image system configuration

set -ex

# ── Firmware: install from local debs in /opt/ ────────────────────────────────
echo "Install firmware"
dpkg -i --force-overwrite /opt/linux-firmware-*.deb

# ── Kernel: local deb first, apt fallback ────────────────────────────────────
if ls /opt/linux-image-*.deb > /dev/null 2>&1; then
    echo "Install kernel from local deb"
    dpkg -i --force-overwrite /opt/linux-image-*.deb
    if ls /opt/linux-headers-*.deb > /dev/null 2>&1; then
        dpkg -i --force-overwrite /opt/linux-headers-*.deb
    fi
else
    echo "No local kernel deb found — installing from apt"
    apt-get install -y linux-image-6.18-sdm845 linux-headers-6.18-sdm845
fi

# ── Audio: Mobian UCM2 maps ───────────────────────────────────────────────────
# Mobian repo is configured via overlays/etc/apt/sources.list.d/extrepo_mobian.sources
echo "Fix alsa-ucm-conf"
apt-get install -y --allow-downgrades alsa-ucm-conf
apt-mark hold alsa-ucm-conf

echo "Mask for working speakers"
systemctl mask alsa-state alsa-restore
systemctl set-default graphical.target

# ── Cleanup ───────────────────────────────────────────────────────────────────
echo "Clean packages"
apt-get -y autoremove --purge

# ── GNOME extensions ──────────────────────────────────────────────────────────
echo "Disable GNOME extension version validation"
gsettings set org.gnome.shell disable-extension-version-validation true

echo "Enable shell extensions"
gnome-extensions enable aurora-shell@luminusos.github.io
gnome-extensions enable touchup@mityax
gnome-extensions enable user-theme@gnome-shell-extensions.gcampax.github.com

# ── Services ──────────────────────────────────────────────────────────────────
echo "Enable rootfs resize service"
systemctl enable grow-rootfs.service
