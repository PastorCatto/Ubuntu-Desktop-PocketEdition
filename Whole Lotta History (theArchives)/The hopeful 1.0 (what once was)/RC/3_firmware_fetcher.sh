#!/bin/bash
set -e
source build.env

echo "======================================================="
echo "   [3/7] Firmware Fetcher (Mobian Extraction)"
echo "======================================================="

if [ -d "$FIRMWARE_STASH" ] && [ "$(ls -A $FIRMWARE_STASH 2>/dev/null)" ]; then
    echo ">>> Found existing firmware stash at $FIRMWARE_STASH. Skipping network fetch."
else
    echo ">>> Local firmware stash is empty."
    echo ">>> Please ensure your Poco F1 is powered on, connected to Wi-Fi,"
    echo ">>> and actively running Mobian."
    echo ""
    read -p "Enter Poco F1 IP Address (e.g., 192.168.1.50): " PHONE_IP
    read -p "Enter Mobian username [default: mobian]: " PHONE_USER
    PHONE_USER=${PHONE_USER:-mobian}
    read -s -p "Enter Mobian password [default: 1234]: " PHONE_PASS
    echo ""
    PHONE_PASS=${PHONE_PASS:-1234}
    
    echo ">>> [Phone Side] Archiving hardware profiles via SSH..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" \
        "echo '$PHONE_PASS' | sudo -S tar -czpf ~/mobian_harvest.tar.gz /usr/share/alsa/ucm2/ /etc/ModemManager/ /lib/udev/rules.d/ /lib/firmware/postmarketos/" || true
    
    echo ">>> [Host Side] Downloading the archive..."
    mkdir -p "$FIRMWARE_STASH"
    sshpass -p "$PHONE_PASS" scp -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP:~/mobian_harvest.tar.gz" "$FIRMWARE_STASH/raw_harvest.tar.gz"
    
    echo ">>> [Host Side] Extracting into stash..."
    tar -xzpf "$FIRMWARE_STASH/raw_harvest.tar.gz" -C "$FIRMWARE_STASH/"
    rm "$FIRMWARE_STASH/raw_harvest.tar.gz"
    
    echo ">>> [Phone Side] Cleaning up temporary files..."
    sshpass -p "$PHONE_PASS" ssh -o StrictHostKeyChecking=no "$PHONE_USER@$PHONE_IP" "rm ~/mobian_harvest.tar.gz"
fi

echo ">>> Firmware successfully stashed and secured."
echo ">>> Proceed to Script 4 (The Transplant)."
