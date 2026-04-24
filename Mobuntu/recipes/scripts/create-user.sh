#!/bin/bash
# Mobuntu RC15 — create-user.sh
# Runs inside chroot. Env: USERNAME, PASSWORD
set -e

echo ">>> Creating user: $USERNAME"
useradd -m -s /bin/bash -G sudo,video,audio,netdev,dialout "$USERNAME" || true
echo "$USERNAME:$PASSWORD" | chpasswd
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mobuntu-user
chmod 0440 /etc/sudoers.d/mobuntu-user
