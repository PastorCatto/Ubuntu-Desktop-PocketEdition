#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

FAILS=0

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}   PocketEdition SDM845/Beryllium Health Checker    ${NC}"
echo -e "${CYAN}====================================================${NC}"

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}[PASS]${NC} $1"
    else
        echo -e "${RED}[FAIL]${NC} $1 (Missing)"
        FAILS=$((FAILS+1))
    fi
}

check_binary() {
    # Check if the compiled binary exists in /usr/local/bin or /usr/bin
    if command -v "$1" >/dev/null 2>&1 || [ -f "/usr/local/bin/$1" ] || [ -f "/usr/bin/$1" ]; then
        echo -e "${GREEN}[PASS]${NC} Compiled binary: $1"
    else
        echo -e "${RED}[FAIL]${NC} Binary missing: $1"
        FAILS=$((FAILS+1))
    fi
}

check_service() {
    if [ -f "/etc/systemd/system/$1.service" ] || [ -f "/lib/systemd/system/$1.service" ]; then
        echo -e "${GREEN}[PASS]${NC} Systemd Service: $1.service"
    else
        echo -e "${RED}[FAIL]${NC} Service missing: $1.service"
        FAILS=$((FAILS+1))
    fi
}

echo -e "\n${YELLOW}=== 1. Compiled Daemons & Services ===${NC}"
check_binary "qrtr-cfg"
check_binary "rmtfs"
check_binary "tqftpserv"
check_binary "pd-mapper"
check_service "rmtfs"
check_service "tqftpserv"
check_service "pd-mapper"

echo -e "\n${YELLOW}=== 2. TrustZone Headers (Error -22 Prevent) ===${NC}"
check_file "/lib/firmware/qcom/sdm845/beryllium/modem.mdt"
check_file "/lib/firmware/qcom/sdm845/beryllium/adsp.mdt"
check_file "/lib/firmware/qcom/sdm845/beryllium/cdsp.mdt"

echo -e "\n${YELLOW}=== 3. DSP Split Payloads (Error -2 Prevent) ===${NC}"
# Spot check a few key split files
check_file "/lib/firmware/qcom/sdm845/beryllium/modem.b00"
check_file "/lib/firmware/qcom/sdm845/beryllium/modem.b04"
check_file "/lib/firmware/qcom/sdm845/beryllium/adsp.b00"

echo -e "\n${YELLOW}=== 4. Domain Mapping (Panic Prevent) ===${NC}"
check_file "/lib/firmware/qcom/sdm845/beryllium/jsons/modem.json"
check_file "/lib/firmware/qcom/sdm845/beryllium/jsons/adsp.json"
check_file "/lib/firmware/qcom/sdm845/beryllium/jsons/cdsp.json"
check_file "/lib/firmware/qcom/sdm845/beryllium/jsons/a630_zap.json"

echo -e "\n${YELLOW}=== 5. WiFi & Audio Subsystems ===${NC}"
check_file "/lib/firmware/ath10k/WCN3990/hw1.0/board-2.bin"

echo -e "\n${CYAN}====================================================${NC}"
if [ $FAILS -eq 0 ]; then
    echo -e "${GREEN}SYSTEM VERIFIED:${NC} The Qualcomm stack is compiled and staged."
else
    echo -e "${RED}WARNING:${NC} $FAILS components failed. The stack will crash on boot."
fi
echo -e "${CYAN}====================================================${NC}"