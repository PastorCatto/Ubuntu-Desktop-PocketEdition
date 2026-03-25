#!/bin/bash
set -e

HOST_DUMP_DIR="./beryllium_firmware_dump"

echo "=========================================================="
echo " Starting PocketEdition Qualcomm Stack Compiler & Injector "
echo " (Reverted to Muppets/Lineage Source for Audio Stability)  "
echo "=========================================================="

# --- 1. Smart Rootfs Detection ---
if [ -f "build.env" ]; then
    source build.env
    echo "   Loaded build.env (Target: $UBUNTU_RELEASE)"
fi

if [ -n "$ROOTFS_DIR" ] && [ -d "$ROOTFS_DIR" ]; then
    echo "   [SUCCESS] Found ROOTFS_DIR from environment: $ROOTFS_DIR"
elif [ -d "./rootfs" ]; then
    ROOTFS_DIR="./rootfs"
else
    FOUND_DIR=$(find . -maxdepth 1 -type d -iname "ubuntu-*" | head -n 1)
    if [ -n "$FOUND_DIR" ]; then
        ROOTFS_DIR="$FOUND_DIR"
    else
        echo "   [FAIL] Could not locate a rootfs directory."
        exit 1
    fi
fi

export ROOTFS_DIR

# --- 2. Mount Virtual Filesystems ---
mount -t proc /proc "$ROOTFS_DIR/proc" || true
mount -t sysfs /sys "$ROOTFS_DIR/sys" || true
mount -o bind /dev "$ROOTFS_DIR/dev" || true
mount -o bind /dev/pts "$ROOTFS_DIR/dev/pts" || true
mount -o bind /run "$ROOTFS_DIR/run" || true

# 3. Execute the Build inside Chroot
chroot "$ROOTFS_DIR" /bin/bash << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "--- 1. Installing Build Dependencies ---"
apt-get update
apt-get install -y build-essential git wget curl ca-certificates pkg-config \
                   alsa-ucm-conf libglib2.0-dev meson ninja-build \
                   libudev-dev libzstd-dev liblzma-dev

echo "--- 2. Compiling Qualcomm Daemons from Source ---"
BUILD_DIR="/tmp/qcom_build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Foundation: qrtr
git clone --depth 1 https://github.com/linux-msm/qrtr.git
cd qrtr && meson setup build --prefix=/usr && ninja -C build install && cd ..

# Compiler: qmic (Required for rmtfs/pd-mapper)
git clone --depth 1 https://github.com/linux-msm/qmic.git
cd qmic && make prefix=/usr install && cd ..

# Service: rmtfs
git clone --depth 1 https://github.com/linux-msm/rmtfs.git
cd rmtfs && make prefix=/usr install && cd ..

# Service: tqftpserv
git clone --depth 1 https://github.com/linux-msm/tqftpserv.git
cd tqftpserv && meson setup build --prefix=/usr && ninja -C build install && cd ..

# Service: pd-mapper
git clone --depth 1 https://github.com/linux-msm/pd-mapper.git
cd pd-mapper && make prefix=/usr install && cd ..

echo "--- 3. Creating Systemd Services ---"
# Note: ExecStart now correctly points to /usr/bin/
cat << 'SVC' > /etc/systemd/system/rmtfs.service
[Unit]
Description=Qualcomm Remote Filesystem Service
After=network.target
[Service]
ExecStart=/usr/bin/rmtfs -r -s
Restart=always
[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/tqftpserv.service
[Unit]
Description=Qualcomm Trivial File Transfer Protocol Service
After=network.target
[Service]
ExecStart=/usr/bin/tqftpserv
Restart=always
[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/pd-mapper.service
[Unit]
Description=Qualcomm Protection Domain Mapper
After=network.target
[Service]
ExecStart=/usr/bin/pd-mapper
Restart=always
[Install]
WantedBy=multi-user.target
SVC

systemctl enable rmtfs tqftpserv pd-mapper

echo "--- 4. Fetching Firmware (Muppets/Lineage Source) ---"
FW_DIR="/lib/firmware/qcom/sdm845/beryllium"
WIFI_DIR="/lib/firmware/ath10k/WCN3990/hw1.0"
mkdir -p "$FW_DIR" "$WIFI_DIR"

cd "$BUILD_DIR"
rm -rf muppets
git init muppets && cd muppets
git remote add origin https://gitlab.com/the-muppets/proprietary_vendor_xiaomi.git
git config core.sparseCheckout true
echo "beryllium/radio/*" >> .git/info/sparse-checkout

# Pulling 'master' to avoid the lineage-20 ref error while getting the same blobs
git pull --depth 1 origin master || git pull --depth 1 origin lineage-20

echo "Deploying blobs and JSONs..."
cp beryllium/radio/*.* "$FW_DIR/" 2>/dev/null || true
# FIX: Move JSON files to the root firmware dir (no subfolder)
cp beryllium/radio/jsons/*.json "$FW_DIR/" 2>/dev/null || true
cp beryllium/radio/jsons/*.jsn "$FW_DIR/" 2>/dev/null || true

echo "Applying lowercase enforcement and board-2.bin..."
wget -q -O "$WIFI_DIR/board-2.bin" "https://github.com/jhugo/linux-firmware/raw/master/ath10k/WCN3990/hw1.0/board-2.bin"

cd "$FW_DIR"
for f in *; do 
    [ -f "$f" ] && mv "$f" "${f,,}" 2>/dev/null || true
done

EOF

# --- 3. Cleanup and Export ---
echo "-> Unmounting and exporting dump..."
umount "$ROOTFS_DIR/run" || true
umount "$ROOTFS_DIR/dev/pts" || true
umount "$ROOTFS_DIR/dev" || true
umount "$ROOTFS_DIR/sys" || true
umount "$ROOTFS_DIR/proc" || true

mkdir -p "$HOST_DUMP_DIR"
cp -r "$ROOTFS_DIR/lib/firmware/qcom/sdm845/beryllium" "$HOST_DUMP_DIR/"

echo "=========================================================="
echo " Build Complete with Legacy Source Integration! "
echo "=========================================================="