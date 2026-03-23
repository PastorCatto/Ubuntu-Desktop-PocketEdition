#!/bin/bash
set -ex

# Prevent apt from prompting for user input during installation
export DEBIAN_FRONTEND=noninteractive

echo "--- 1. Installing All Dependencies ---"
apt-get update
# Includes standard build tools + the specific headers we found missing today
apt-get install -y build-essential git pkg-config meson ninja-build libudev-dev liblzma-dev libzstd-dev

# Create a clean working directory
WORKDIR="/tmp/qcom-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "--- 2. Building qrtr (Meson) ---"
git clone --depth 1 https://github.com/andersson/qrtr.git
cd qrtr
meson setup build --prefix=/usr/local
ninja -C build
ninja -C build install
cd ..

echo "--- 3. Building qmic (Make) ---"
git clone --depth 1 https://github.com/andersson/qmic.git
cd qmic
make
make install prefix=/usr/local
cd ..

echo "--- 4. Building rmtfs (Make) ---"
git clone --depth 1 https://github.com/andersson/rmtfs.git
cd rmtfs
make
make install prefix=/usr/local
cd ..

echo "--- 5. Building pd-mapper (Make) ---"
git clone --depth 1 https://github.com/andersson/pd-mapper.git
cd pd-mapper
make
make install prefix=/usr/local
cd ..

echo "--- Building tqftpserv (Meson) ---"
cd /tmp/qcom-build
git clone --depth 1 https://github.com/linux-msm/tqftpserv.git
cd tqftpserv
meson setup build --prefix=/usr/local
ninja -C build
ninja -C build install
cd ..

echo "--- 6. Writing Systemd Services ---"
cat <<EOF > /etc/systemd/system/qrtr-ns.service
[Unit]
Description=QRTR Name Service
After=network.target
[Service]
ExecStart=/usr/local/bin/qrtr-ns
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/pd-mapper.service
[Unit]
Description=Qualcomm Protection Domain Mapper
After=qrtr-ns.service
[Service]
ExecStart=/usr/local/bin/pd-mapper
Restart=always
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/tqftpserv.service
[Unit]
Description=Qualcomm TFTP Server (tqftpserv)
Requires=qrtr-ns.service
After=qrtr-ns.service
[Service]
ExecStart=/usr/local/bin/tqftpserv
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# Enable the services so they start automatically on boot in the final image
systemctl enable qrtr-ns.service
systemctl enable pd-mapper.service
systemctl enable tqftpserv.service

echo "--- 7. Cleaning up Image Space ---"
# Remove source code and clear the apt cache to keep your image size small
rm -rf "$WORKDIR"
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "--- Build and Installation Complete! ---"
