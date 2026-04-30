#!/bin/bash
# Mobuntu RC15 — setup-qcom.sh
# Runs inside chroot. Gated on qcom_services quirk by the calling recipe.
# Env: DEVICE_CODENAME, DEVICE_BRAND, DEVICE_PACKAGES, DEVICE_SERVICES,
#      FIRMWARE_METHOD, FIRMWARE_REPO, DEVICE_QUIRKS
set -e
export DEBIAN_FRONTEND=noninteractive

has_quirk() { echo " ${DEVICE_QUIRKS} " | grep -qw "$1"; }

# ------- Device packages + alsa-ucm-conf -------
echo ">>> Installing alsa-ucm-conf..."
apt-get install -y alsa-ucm-conf

if [ -n "$DEVICE_PACKAGES" ]; then
    echo ">>> Installing device packages: $DEVICE_PACKAGES"
    apt-get install -y $DEVICE_PACKAGES
fi

# ------- Adreno 630 GPU firmware -------
echo ">>> Fetching Adreno 630 GPU firmware..."
KERNEL_ORG="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"
fetch_fw() {
    local DEST="$1" FILE="$2"
    mkdir -p "$DEST"
    curl -L -f -s -o "$DEST/$(basename $FILE)" "$KERNEL_ORG/$FILE" && \
        echo ">>>   OK: $FILE" || \
        echo ">>>   WARN: Failed to fetch $FILE (non-fatal)"
    return 0
}
fetch_fw "/lib/firmware/qcom"        "qcom/a630_sqe.fw"
fetch_fw "/lib/firmware/qcom"        "qcom/a630_gmu.bin"
if [ "$FIRMWARE_METHOD" != "git" ]; then
    fetch_fw "/lib/firmware/qcom/sdm845" "qcom/sdm845/a630_zap.mbn"
fi

# ------- Service ordering drop-ins -------
echo ">>> Setting up Qualcomm service ordering..."
mkdir -p /etc/systemd/system/pd-mapper.service.d
printf '[Unit]\nAfter=qrtr-ns.service\nRequires=qrtr-ns.service\n' \
    > /etc/systemd/system/pd-mapper.service.d/ordering.conf
mkdir -p /etc/systemd/system/rmtfs.service.d
printf '[Unit]\nAfter=qrtr-ns.service\nRequires=qrtr-ns.service\n' \
    > /etc/systemd/system/rmtfs.service.d/ordering.conf

# ------- Enable Qualcomm services -------
echo ">>> Enabling Qualcomm services..."
systemctl enable qrtr-ns  2>/dev/null || true
systemctl enable rmtfs    2>/dev/null || true
systemctl enable pd-mapper 2>/dev/null || true
systemctl enable tqftpserv 2>/dev/null || true
systemctl daemon-reload   2>/dev/null || true

# ------- Mask ALSA state services -------
echo ">>> Masking ALSA state services (conflicts with SDM845 audio)..."
systemctl mask alsa-state   2>/dev/null || true
systemctl mask alsa-restore 2>/dev/null || true

# ------- qcom-firmware initramfs hook -------
# Installed via overlay action in qcom.yaml
if [ -f /usr/share/initramfs-tools/hooks/qcom-firmware ]; then
    chmod +x /usr/share/initramfs-tools/hooks/qcom-firmware
    echo ">>> qcom-firmware hook permissions set."
else
    echo ">>> WARNING: qcom-firmware hook missing — firmware may not load on boot."
fi

# ------- 51-qcom.conf permissions -------
if [ -f /usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf ]; then
    echo ">>> 51-qcom.conf present."
else
    echo ">>> WARNING: 51-qcom.conf missing — audio tuning not applied."
fi

# ------- remoteproc udev rules -------
if [ -f /usr/lib/udev/rules.d/82-beryllium-remoteproc.rules ]; then
    chmod 644 /usr/lib/udev/rules.d/82-beryllium-remoteproc.rules
    echo ">>> remoteproc udev rule permissions set."
fi
if [ -f /usr/lib/udev/remoteproc-adsp-trigger.sh ]; then
    chmod +x /usr/lib/udev/remoteproc-adsp-trigger.sh
    echo ">>> remoteproc trigger script permissions set."
fi

# ------- Device services -------
if [ -n "$DEVICE_SERVICES" ]; then
    echo ">>> Enabling device services: $DEVICE_SERVICES"
    for svc in $DEVICE_SERVICES; do
        systemctl enable "$svc" 2>/dev/null || true
    done
fi

# ------- Kernel hook (mkbootimg devices only) -------
# Hook is installed via overlay in device recipe.
# Ensure executable bits are set.
if [ -f /etc/kernel/postinst.d/zz-qcom-bootimg ]; then
    chmod +x /etc/kernel/postinst.d/zz-qcom-bootimg
fi
if [ -f /etc/initramfs/post-update.d/bootimg ]; then
    chmod +x /etc/initramfs/post-update.d/bootimg
fi

mkdir -p /boot/efi
echo ">>> Qualcomm setup complete."
