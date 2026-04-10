#!/bin/bash

# --- 1. Load Build Context ---
[ -f "build.env" ] && source build.env

# Smart Rootfs Detection
if [ -n "$ROOTFS_DIR" ] && [ -d "$ROOTFS_DIR" ]; then
    TARGET="$ROOTFS_DIR"
elif [ -d "./rootfs" ]; then
    TARGET="./rootfs"
else
    TARGET=$(find . -maxdepth 1 -type d -iname "ubuntu-*" | head -n 1)
fi

if [ -z "$TARGET" ]; then
    echo "Error: No rootfs found. Run this from the project root."
    exit 1
fi

# Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}   PocketEdition SDM845 Hardware Audit v2.3         ${NC}"
echo -e "   Target: ${YELLOW}$TARGET${NC}"
echo -e "${CYAN}====================================================${NC}"

# Helper function for files
audit_file() {
    if [ -f "$TARGET$1" ]; then
        echo -e "${GREEN}[PASS]${NC} Found: $1"
        ((PASS_COUNT++))
    else
        echo -e "${RED}[FAIL]${NC} Missing: $1"
        ((FAIL_COUNT++))
    fi
}

# Helper function for binaries
audit_bin() {
    local bin_path=""
    if [ -f "$TARGET/usr/bin/$1" ]; then bin_path="/usr/bin/$1"
    elif [ -f "$TARGET/usr/local/bin/$1" ]; then bin_path="/usr/local/bin/$1"
    fi

    if [ -n "$bin_path" ]; then
        echo -e "${GREEN}[PASS]${NC} Binary '$1' found at $bin_path"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "${RED}[FAIL]${NC} Binary '$1' NOT found in /usr/bin or /usr/local/bin"
        ((FAIL_COUNT++))
        return 1
    fi
}

# --- 1. The Toolchain (The "Qualcomm Compiler" check) ---
echo -e "\n${YELLOW}Checking Compiled Daemons...${NC}"
audit_bin "qrtr-cfg"
audit_bin "qmic"
audit_bin "rmtfs"
audit_bin "tqftpserv"
audit_bin "pd-mapper"

# --- 2. The Service Layer (The "Path Match" check) ---
echo -e "\n${YELLOW}Checking Systemd Integration...${NC}"
for svc in rmtfs tqftpserv pd-mapper; do
    svc_file="/etc/systemd/system/$svc.service"
    if [ -f "$TARGET$svc_file" ]; then
        # Check if ExecStart path actually points to where the binary is
        exec_path=$(grep "ExecStart=" "$TARGET$svc_file" | cut -d'=' -f2 | awk '{print $1}')
        if [ -f "$TARGET$exec_path" ]; then
            echo -e "${GREEN}[PASS]${NC} $svc.service (Path verified: $exec_path)"
            ((PASS_COUNT++))
        else
            echo -e "${RED}[CRITICAL]${NC} $svc.service points to $exec_path, but binary is NOT there!"
            ((FAIL_COUNT++))
        fi
    else
        echo -e "${RED}[FAIL]${NC} $svc.service is missing"
        ((FAIL_COUNT++))
    fi
done

# --- 3. The Firmware (The "Mainline / Lowercase" check) ---
echo -e "\n${YELLOW}Checking Mainline Firmware Blobs...${NC}"
FW_BASE="/lib/firmware/qcom/sdm845/beryllium"
# Key blobs from sdm845-mainline
audit_file "$FW_BASE/adsp.mbn"
audit_file "$FW_BASE/cdsp.mbn"
audit_file "$FW_BASE/modem.mbn"
audit_file "$FW_BASE/mba.mbn"
audit_file "$FW_BASE/adspr.jsn"
audit_file "$FW_BASE/modemr.jsn"

# Check lowercase enforcement
UPPER_CHECK=$(find "$TARGET$FW_BASE" -name '*[A-Z]*')
if [ -z "$UPPER_CHECK" ]; then
    echo -e "${GREEN}[PASS]${NC} Case-Sensitivity: All blobs are lowercase."
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} Found uppercase files in firmware folder! Kernel will reject these."
    ((FAIL_COUNT++))
fi

# --- 4. Host Side Dump ---
echo -e "\n${YELLOW}Checking Host Side Dump...${NC}"
if [ -d "./beryllium_firmware_dump" ]; then
    echo -e "${GREEN}[PASS]${NC} Firmware dump found on host."
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} ./beryllium_firmware_dump is missing."
    ((FAIL_COUNT++))
fi

# --- Final Summary ---
echo -e "\n${CYAN}====================================================${NC}"
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}  ALL SYSTEMS GO! ${NC} Image is ready for Script 6."
else
    echo -e "${RED}  AUDIT FAILED!   ${NC} Found $FAIL_COUNT critical issues."
fi
echo -e "  Passed: $PASS_COUNT | Failed: $FAIL_COUNT"
echo -e "${CYAN}====================================================${NC}"