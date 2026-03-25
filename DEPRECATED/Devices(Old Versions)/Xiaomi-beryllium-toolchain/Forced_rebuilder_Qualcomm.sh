cat << 'EOF' > /tmp/build_services.sh
#!/bin/bash
set -ex

echo "--- 1. Forcing Dependency Installation ---"
apt-get update
apt-get install -y build-essential pkg-config libsystemd-dev git

echo "--- 2. Building QRTR (IPC Router) ---"
rm -rf /tmp/qrtr
git clone --depth 1 https://github.com/andersson/qrtr.git /tmp/qrtr
cd /tmp/qrtr
make
make install prefix=/usr

echo "--- 3. Building PD-Mapper ---"
rm -rf /tmp/pd-mapper
git clone --depth 1 https://github.com/andersson/pd-mapper.git /tmp/pd-mapper
cd /tmp/pd-mapper
make
make install prefix=/usr

echo "--- 4. Building TQFTPSERV (Firmware Server) ---"
rm -rf /tmp/tqftpserv
git clone --depth 1 https://github.com/andersson/tqftpserv.git /tmp/tqftpserv
cd /tmp/tqftpserv
make
make install prefix=/usr

echo "--- 5. Securing Executable Permissions ---"
chmod +x /usr/bin/qrtr-ns
chmod +x /usr/bin/pd-mapper
chmod +x /usr/bin/tqftpserv

echo "--- 6. Verifying Installation ---"
ls -l /usr/bin/qrtr-ns /usr/bin/pd-mapper /usr/bin/tqftpserv

echo "--- SUCCESS: Services Compiled and Installed! ---"
EOF

chmod +x /tmp/build_services.sh
/tmp/build_services.sh