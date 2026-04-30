#!/bin/bash
# Mobuntu RC15 — setup-hostname.sh
# Runs inside chroot. Env: DEVICE_HOSTNAME
set -e

echo "$DEVICE_HOSTNAME" > /etc/hostname
printf "127.0.0.1   localhost\n127.0.1.1   %s\n::1         localhost ip6-localhost ip6-loopback\n" \
    "$DEVICE_HOSTNAME" > /etc/hosts
