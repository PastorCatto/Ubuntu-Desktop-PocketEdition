#!/bin/bash
set -e

HOST_DUMP_DIR="./beryllium_firmware_dump"

echo "=========================================================="
echo " Starting PocketEdition Qualcomm Stack Compiler & Injector "
echo "=========================================================="

# --- 1. Smart Rootfs Detection ---
echo "-> Hunting for rootfs directory..."

# Step A: Load build.env if it exists
if [ -f "build.env" ]; then
    source build.env
    echo "   Loaded build.env (Target: $UBUNTU_RELEASE)"
fi

# Step B: Determine the actual rootfs path
if [ -n "$ROOTFS_DIR" ] && [ -d "$ROOTFS_DIR" ]; then
    echo "   [SUCCESS] Found ROOTFS_DIR from environment: $ROOTFS_DIR"
elif [ -d "./rootfs" ]; then
    ROOTFS_DIR="./rootfs"
    echo "   [SUCCESS] Found standard ./rootfs directory."
else
    # Step C: The fallback hunt for Ubuntu-*
    echo "   Hunting for directories matching 'Ubuntu-*' or 'ubuntu-*'..."
    FOUND_DIR=$(find . -maxdepth 1 -type d -iname "ubuntu-*" | head -n 1)
    
    if [ -n "$FOUND_DIR" ]; then
        ROOTFS_DIR="$FOUND_DIR"
        echo "   [SUCCESS] Auto-detected rootfs at: $ROOTFS_DIR"
    else
        echo "   [FAIL] Could not locate a rootfs directory."
        echo "   Please define ROOTFS_DIR in build.env or ensure an Ubuntu-* folder exists."
        exit 1
    fi
fi

# Export it so the chroot commands know where to go
export ROOTFS_DIR

# --- 2. Mount Virtual Filesystems ---
echo "-> Mounting virtual filesystems for chroot..."
mount -t proc /proc "$ROOTFS_DIR/proc" || true
mount -t sysfs /sys "$ROOTFS_DIR/sys" || true
mount -o bind /dev "$ROOTFS_DIR/dev" || true
mount -o bind /dev/pts "$ROOTFS_DIR/dev/pts" || true
mount -o bind /run "$ROOTFS_DIR/run" || true

# 2. Execute the Build inside Chroot
chroot "$ROOTFS_DIR" /bin/bash << 'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "--- 1. Installing Build Dependencies ---"
apt-get update
apt-get install -y build-essential git wget curl ca-certificates pkg-config \
                   alsa-ucm-conf libglib2.0-dev meson ninja-build libudev-dev libzstd-dev liblzma-dev

echo "--- 2. Compiling Qualcomm Daemons from Source ---"
BUILD_DIR="/tmp/qcom_build"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 1. Build qrtr (Meson) - Foundation for IPC
echo "Building qrtr..."
git clone https://github.com/linux-msm/qrtr.git
cd qrtr
meson setup build --prefix=/usr
ninja -C build
ninja -C build install
cd ..

# 2. Build qmic (Make) - The missing compiler for QMI files!
echo "Building qmic..."
git clone https://github.com/linux-msm/qmic.git
cd qmic
make prefix=/usr
make prefix=/usr install
cd ..

# 3. Build rmtfs (Make) - Needs libudev, qrtr, and qmic
echo "Building rmtfs..."
git clone https://github.com/linux-msm/rmtfs.git
cd rmtfs
make prefix=/usr
make prefix=/usr install
cd ..

# 4. Build tqftpserv (Meson) - Needs qrtr
echo "Building tqftpserv..."
git clone https://github.com/linux-msm/tqftpserv.git
cd tqftpserv
meson setup build --prefix=/usr
ninja -C build
ninja -C build install
cd ..

# 5. Build pd-mapper (Make) - Needs qrtr and qmic
echo "Building pd-mapper..."
git clone https://github.com/linux-msm/pd-mapper.git
cd pd-mapper
make prefix=/usr
make prefix=/usr install

cd ..
echo "--- 3. Creating Systemd Services for Compiled Daemons ---"
cat << 'SVC' > /etc/systemd/system/rmtfs.service
[Unit]
Description=Qualcomm Remote Filesystem Service
After=network.target

[Service]
ExecStart=/usr/local/bin/rmtfs -r -s
Restart=always

[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/tqftpserv.service
[Unit]
Description=Qualcomm Trivial File Transfer Protocol Service
After=network.target

[Service]
ExecStart=/usr/local/bin/tqftpserv
Restart=always

[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/pd-mapper.service
[Unit]
Description=Qualcomm Protection Domain Mapper
After=network.target

[Service]
ExecStart=/usr/local/bin/pd-mapper
Restart=always

[Install]
WantedBy=multi-user.target
SVC

systemctl enable rmtfs tqftpserv pd-mapper

echo "--- 4. Fetching & Staging Firmware (sdm845-mainline source) ---"
FW_DIR="/lib/firmware/qcom/sdm845/beryllium"
WIFI_DIR="/lib/firmware/ath10k/WCN3990/hw1.0"
mkdir -p "$FW_DIR" "$WIFI_DIR"

# Clean build directory
BUILD_DIR="/tmp/qcom_build"
cd "$BUILD_DIR"
rm -rf firmware-xiaomi-beryllium

# Clone the mainline-specific firmware repo
git clone --depth 1 https://gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium.git
cd firmware-xiaomi-beryllium

echo "Injecting firmware into system paths..."
# The sdm845-mainline repo usually mirrors the /lib/firmware structure
cp -r lib/firmware/qcom/sdm845/beryllium/* "$FW_DIR/"

# Grab the WiFi board-2.bin which is usually in the same repo or easily fetched
if [ -f "lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin" ]; then
    cp "lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin" "$WIFI_DIR/"
else
    wget -q -O "$WIFI_DIR/board-2.bin" "https://github.com/jhugo/linux-firmware/raw/master/ath10k/WCN3990/hw1.0/board-2.bin"
fi

echo "Ensuring all filenames are lowercase (Mainline Safety)..."
find "$FW_DIR" -type f -exec bash -c 'mv "$1" "${1%/*}/${1##*/,,}"' -- {} \;

EOF

# 3. Cleanup Mounts
echo "-> Unmounting virtual filesystems..."
umount "$ROOTFS_DIR/run" || true
umount "$ROOTFS_DIR/dev/pts" || true
umount "$ROOTFS_DIR/dev" || true
umount "$ROOTFS_DIR/sys" || true
umount "$ROOTFS_DIR/proc" || true

# 4. Dump the Firmware Stash to the Host
echo "-> Dumping compiled firmware stash to $HOST_DUMP_DIR..."
mkdir -p "$HOST_DUMP_DIR"
cp -r "$ROOTFS_DIR/lib/firmware/qcom/sdm845/beryllium" "$HOST_DUMP_DIR/"
cp -r "$ROOTFS_DIR/lib/firmware/ath10k" "$HOST_DUMP_DIR/" 2>/dev/null || true

echo "=========================================================="
echo " Build Complete! Firmware exported to $HOST_DUMP_DIR "
echo "=========================================================="
