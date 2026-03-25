#!/bin/bash
set -ex

# Prevent apt from prompting for user input during installation
export DEBIAN_FRONTEND=noninteractive

echo "--- 1. Installing All Dependencies ---"
apt-get update
# We MUST install these. Meson, Ninja, and pkg-config are mandatory for the new repos.
apt-get install -y build-essential git pkg-config meson ninja-build libudev-dev liblzma-dev libzstd-dev

# Create a clean working directory
WORKDIR="/tmp/qcom-build"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "--- 2. Building QRTR (Meson) ---"
git clone --depth 1 https://github.com/andersson/qrtr.git
cd qrtr
# Using /usr ensures pkg-config can find libqrtr.so for the next steps
meson setup build --prefix=/usr
ninja -C build
ninja -C build install
# Update the linker cache so pd-mapper can see the new library
ldconfig
cd "$WORKDIR"

echo "--- 3. Building QMIC (Make) ---"
git clone --depth 1 https://github.com/andersson/qmic.git
cd qmic
make
make install prefix=/usr
cd "$WORKDIR"

echo "--- 4. Building RMTFS (Make) ---"
git clone --depth 1 https://github.com/andersson/rmtfs.git
cd rmtfs
make
make install prefix=/usr
cd "$WORKDIR"

echo "--- 5. Building PD-Mapper (Make) ---"
git clone --depth 1 https://github.com/andersson/pd-mapper.git
cd pd-mapper
make
make install prefix=/usr
cd "$WORKDIR"

echo "--- 6. Building TQFTPSERV (Meson) ---"
git clone --depth 1 https://github.com/linux-msm/tqftpserv.git
cd tqftpserv
meson setup build --prefix=/usr
ninja -C build
ninja -C build install
cd "$WORKDIR"

echo "--- 7. Securing Executable Permissions ---"
chmod +x /usr/bin/qrtr-ns
chmod +x /usr/bin/pd-mapper
chmod +x /usr/bin/tqftpserv
chmod +x /usr/bin/rmtfs
ls -l /usr/bin/qrtr-ns /usr/bin/pd-mapper /usr/bin/tqftpserv /usr/bin/rmtfs

echo "--- 8. Writing Systemd Services ---"
cat << 'SVC' > /etc/systemd/system/qrtr-ns.service
[Unit]
Description=QRTR Name Service
After=network.target
[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always
[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/pd-mapper.service
[Unit]
Description=Qualcomm Protection Domain Mapper
Requires=qrtr-ns.service
After=qrtr-ns.service
[Service]
ExecStart=/usr/bin/pd-mapper
Restart=always
[Install]
WantedBy=multi-user.target
SVC

cat << 'SVC' > /etc/systemd/system/tqftpserv.service
[Unit]
Description=Qualcomm TFTP Server (tqftpserv)
Requires=qrtr-ns.service
After=qrtr-ns.service
[Service]
ExecStart=/usr/bin/tqftpserv
Restart=always
[Install]
WantedBy=multi-user.target
SVC

# Enable the services so they start automatically on boot
systemctl enable qrtr-ns.service
systemctl enable pd-mapper.service
systemctl enable tqftpserv.service
systemctl enable rmtfs.service || true

echo "--- 9. Cleaning up Image Space ---"
# Remove source code and clear the apt cache to keep your image size small
rm -rf "$WORKDIR"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "--- Build and Installation Complete! ---"
