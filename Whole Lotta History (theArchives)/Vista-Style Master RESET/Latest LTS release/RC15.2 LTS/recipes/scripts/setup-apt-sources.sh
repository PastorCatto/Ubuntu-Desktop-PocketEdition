#!/bin/bash
# Mobuntu RC15 — setup-apt-sources.sh
# Runs inside chroot. Env: UBUNTU_RELEASE
set -e

cat > /etc/apt/sources.list << EOF
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE} main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ ${UBUNTU_RELEASE}-security main restricted universe multiverse
EOF

curl -fsSL https://repo.mobian.org/mobian.gpg \
    -o /etc/apt/trusted.gpg.d/mobian.gpg

echo "deb http://repo.mobian.org/ staging main non-free-firmware" \
    > /etc/apt/sources.list.d/mobian.list

apt-get update
apt-get upgrade -y
