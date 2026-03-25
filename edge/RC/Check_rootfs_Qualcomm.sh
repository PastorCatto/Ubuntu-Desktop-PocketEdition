#!/bin/bash

ROOTFS="Ubuntu-Beryllium"

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "======================================================="
echo "   Beryllium Pre-Flight Health & Exec Check"
echo "======================================================="

if [ ! -d "$ROOTFS" ]; then
    echo -e "${RED}[FATAL] Rootfs folder '$ROOTFS' not found!${NC}"
    exit 1
fi

ERRORS=0

# Checks if a file exists
check_file() {
    if [ -f "$ROOTFS/$1" ]; then
        echo -e "${GREEN}[PASS]${NC} $1"
    else
        echo -e "${RED}[FAIL]${NC} $1 (Missing File)"
        ERRORS=$((ERRORS+1))
    fi
}

# Checks if a file exists AND is executable
check_exec() {
    if [ -x "$ROOTFS/$1" ]; then
        echo -e "${GREEN}[EXEC]${NC} $1 (Ready to run)"
    elif [ -f "$ROOTFS/$1" ]; then
        echo -e "${RED}[FAIL]${NC} $1 (Exists, but NOT executable. Run chmod +x)"
        ERRORS=$((ERRORS+1))
    else
        echo -e "${RED}[FAIL]${NC} $1 (Missing Executable)"
        ERRORS=$((ERRORS+1))
    fi
}

# Checks if a directory exists
check_dir() {
    if [ -d "$ROOTFS/$1" ]; then
        echo -e "${GREEN}[PASS]${NC} $1/"
    else
        echo -e "${RED}[FAIL]${NC} $1/ (Missing Directory)"
        ERRORS=$((ERRORS+1))
    fi
}

echo "--- 1. Core Operating System Binaries ---"
check_exec "bin/bash"
check_exec "sbin/init"
check_exec "usr/bin/systemctl"

echo -e "\n--- 2. TrustZone / DSP Firmware (Monolithic) ---"
check_dir "lib/firmware/qcom/sdm845/beryllium"
check_file "lib/firmware/qcom/sdm845/beryllium/adsp.mbn"
check_file "lib/firmware/qcom/sdm845/beryllium/cdsp.mbn"
check_file "lib/firmware/qcom/sdm845/beryllium/wlanmdsp.mbn"
check_file "lib/firmware/qcom/sdm845/beryllium/modem.mbn"

echo -e "\n--- 3. GPU Hardware Acceleration ---"
check_file "lib/firmware/qcom/sdm845/beryllium/a630_zap.mbn"
check_file "lib/firmware/qcom/a630_sqe.fw"

echo -e "\n--- 4. WiFi & Bluetooth ---"
check_file "lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin"
check_dir "lib/firmware/qca"

echo -e "\n--- 5. ALSA Audio Routing ---"
check_dir "usr/share/alsa/ucm2/conf.d/sdm845"

echo -e "\n--- 6. Qualcomm IPC Services (Compiled Binaries) ---"
# qrtr-ns removed for in-kernel routing compatibility
check_exec "usr/bin/pd-mapper"
check_exec "usr/bin/tqftpserv"
# Added check for rmtfs based on your build script
check_exec "usr/bin/rmtfs" 

echo -e "\n--- 7. Systemd Service Configurations ---"
# qrtr-ns.service removed for in-kernel routing compatibility
check_file "etc/systemd/system/pd-mapper.service"
check_file "etc/systemd/system/tqftpserv.service"
# Added check for rmtfs service based on your build script
check_file "etc/systemd/system/rmtfs.service"

echo "======================================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}ALL SYSTEMS GO! The image is fully verified and ready to be sealed.${NC}"
else
    echo -e "${RED}WARNING: $ERRORS critical components failed validation.${NC}"
fi
echo "======================================================="