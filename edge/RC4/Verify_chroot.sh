#!/bin/bash

# --- Configuration ---
ROOTFS="Ubuntu-Beryllium"

# --- Colors for Output ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================================="
echo "   Chroot Inspector: Poco F1 (Beryllium) ROM"
echo "======================================================="

if [ ! -d "$ROOTFS" ]; then
    echo -e "${RED}[FATAL] Rootfs directory '$ROOTFS' not found!${NC}"
    echo "Did you run Script 4 (The Transplant) yet?"
    exit 1
fi

ERRORS=0

# --- Helper Functions ---
check_file() {
    if [ -f "$ROOTFS$1" ]; then
        echo -e "${GREEN}[PASS]${NC} File Found: $1"
    else
        echo -e "${RED}[FAIL]${NC} Missing File: $1"
        ERRORS=$((ERRORS+1))
    fi
}

check_dir() {
    if [ -d "$ROOTFS$1" ]; then
        # Check if directory is completely empty
        if [ -z "$(ls -A "$ROOTFS$1" 2>/dev/null)" ]; then
            echo -e "${RED}[FAIL]${NC} Directory Empty: $1"
            ERRORS=$((ERRORS+1))
        else
            echo -e "${GREEN}[PASS]${NC} Dir Populated: $1"
        fi
    else
        echo -e "${RED}[FAIL]${NC} Missing Dir: $1"
        ERRORS=$((ERRORS+1))
    fi
}

check_wildcard() {
    if ls "$ROOTFS$1" 1> /dev/null 2>&1; then
        echo -e "${GREEN}[PASS]${NC} Matches Found: $1"
    else
        echo -e "${RED}[FAIL]${NC} No Matches: $1"
        ERRORS=$((ERRORS+1))
    fi
}

# ==========================================
# 1. BOOT & KERNEL CHECKS
# ==========================================
echo -e "\n${YELLOW}>>> Checking Kernel & Boot Assets...${NC}"
check_wildcard "/boot/vmlinuz*"
check_wildcard "/boot/initramfs*"
check_dir "/lib/modules"

# ==========================================
# 2. WI-FI & DSP FIRMWARE CHECKS
# ==========================================
echo -e "\n${YELLOW}>>> Checking WCN3990 Wi-Fi & TFTP Requirements...${NC}"
check_file "/lib/firmware/wlanmdsp.mbn"
check_file "/lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin"

# Ensure Zstandard files were purged
if ls "$ROOTFS/lib/firmware/ath10k/WCN3990/hw1.0/"*.zst 1> /dev/null 2>&1; then
    echo -e "${RED}[FAIL]${NC} Zstandard (.zst) files found! These will crash the TFTP server."
    ERRORS=$((ERRORS+1))
else
    echo -e "${GREEN}[PASS]${NC} No conflicting .zst files found."
fi

# Ensure TFTP daemon is installed (checks the binary location)
check_wildcard "/usr/sbin/tqftpserv"

# ==========================================
# 3. AUDIO ROUTING CHECKS
# ==========================================
echo -e "\n${YELLOW}>>> Checking ALSA UCM Audio Profiles...${NC}"
check_dir "/usr/share/alsa/ucm2"

# ==========================================
# 4. OS & EMULATION CHECKS
# ==========================================
echo -e "\n${YELLOW}>>> Checking Base OS & Emulation...${NC}"
check_file "/usr/bin/qemu-aarch64-static"
check_file "/etc/resolv.conf"

if [ -f "$ROOTFS/etc/X11/default-display-manager" ]; then
    DM=$(cat "$ROOTFS/etc/X11/default-display-manager")
    echo -e "${GREEN}[PASS]${NC} Display Manager configured: $DM"
else
    echo -e "${RED}[FAIL]${NC} Default Display Manager not set! You may boot to a black screen."
    ERRORS=$((ERRORS+1))
fi

# ==========================================
# FINAL VERDICT
# ==========================================
echo -e "\n======================================================="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}SUCCESS! All systems go.${NC}"
    echo "Your rootfs has passed the integrity check."
    echo "You are clear to run 6_seal_rootfs.sh and pack your images!"
else
    echo -e "${RED}WARNING: $ERRORS check(s) failed.${NC}"
    echo "Please review the red errors above."
    echo "You may need to re-run Script 4, or manually enter the chroot (Script 5) to fix them."
fi
echo "======================================================="