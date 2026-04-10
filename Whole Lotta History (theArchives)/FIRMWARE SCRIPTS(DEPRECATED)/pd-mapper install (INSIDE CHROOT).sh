#!/bin/bash
# Run this INSIDE your chroot.
set -ex

echo "--- Installing Build Dependencies ---"
apt update
apt install -y git build-essential pkg-config libsystemd-dev \
               libglib2.0-dev alsa-utils iio-sensor-proxy curl \
               kmod udev

# 1. FIRMWARE & PDR MAPS
echo "--- Setting up Firmware and JSON Maps ---"
mkdir -p /lib/firmware/qcom/sdm845/beryllium/
mkdir -p /var/lib/qrtr/
mkdir -p /usr/share/alsa/ucm2/xiaomi/beryllium/

cd /tmp
git clone --depth 1 https://gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium.git
cp -r firmware-xiaomi-beryllium/* /lib/firmware/qcom/sdm845/beryllium/
cp firmware-xiaomi-beryllium/*.json /var/lib/qrtr/

# 2. THE HOLY TRINITY (QRTR, RMTFS, PD-MAPPER)
echo "--- Building Qualcomm Services ---"
for repo in qrtr rmtfs pd-mapper; do
    cd /tmp
    rm -rf "$repo"
    git clone --depth 1 https://github.com/andersson/$repo.git
    cd "$repo"
    make -j$(nproc)
    make install
done

# 3. SYSTEMD SERVICE FILES
echo "--- Creating Systemd Units ---"
# QRTR-NS
cat <<EOF > /etc/systemd/system/qrtr-ns.service
[Unit]
Description=QRTR Name Service
[Service]
ExecStart=/usr/local/bin/qrtr-ns
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# PD-MAPPER
cat <<EOF > /etc/systemd/system/pd-mapper.service
[Unit]
Description=Qualcomm Protection Domain Mapper
Requires=qrtr-ns.service
After=qrtr-ns.service
[Service]
ExecStart=/usr/local/bin/pd-mapper
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# RMTFS
cat <<EOF > /etc/systemd/system/rmtfs.service
[Unit]
Description=Qualcomm Remote File System Service
Requires=qrtr-ns.service
After=qrtr-ns.service
[Service]
ExecStart=/usr/local/bin/rmtfs -r -s
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# 4. HARDWARE QUIRKS (Rotation & Sound)
echo "--- Applying Hardware Quirks ---"
# Rotation Matrix
cat <<EOF > /etc/udev/hwdb.d/61-sensor-local.hwdb
sensor:modalias:acpi:BOSC0200*:dmi:*
 ACCEL_MOUNT_MATRIX=0, 1, 0; 1, 0, 0; 0, 0, 1
EOF

# Sound UCM Symlink
ln -sf /usr/share/alsa/ucm2/xiaomi/beryllium /usr/share/alsa/ucm2/conf.d/sdm845-snd-card

# 5. ENABLE SERVICES
systemctl enable qrtr-ns pd-mapper rmtfs

echo "--- Hardware Setup Complete ---"