#!/bin/bash
set -e
echo "======================================================="
echo "   [7/7] Kernel & Device Configuration Hacking"
echo "======================================================="
echo "1) Kernel Menuconfig (Modify drivers)"
echo "2) deviceinfo File (Modify kernel command line)"
read -p "Choice [1-2, default 1]: " HACK_CHOICE
if [ "${HACK_CHOICE:-1}" == "1" ]; then
    pmbootstrap kconfig edit linux-xiaomi-beryllium
else
    PM_WORK_DIR=$(pmbootstrap config work 2>/dev/null || echo "$HOME/.local/var/pmbootstrap")
    nano "$(find "$PM_WORK_DIR/cache_git/pmaports/device" -name "device-xiaomi-beryllium" -type d 2>/dev/null)/deviceinfo"
fi
