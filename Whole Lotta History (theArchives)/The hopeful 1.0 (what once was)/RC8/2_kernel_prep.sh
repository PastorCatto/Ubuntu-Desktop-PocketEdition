#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange — [2/5] Kernel Payload Staging"
echo "======================================================="
echo ">>> Scraping Mobian repository for the latest SDM845 kernel..."
mkdir -p kernel_payload
cd kernel_payload

POOL_URL="https://repo.mobian.org/pool/main/l/"

echo ">>> Fetching repository index..."
if ! curl -s -f -L -A "Mozilla/5.0" -o pool_index.html "$POOL_URL"; then
    echo ">>> ERROR: Cannot connect to Mobian repository at $POOL_URL"
    exit 1
fi

LATEST_SUBDIR=$(grep -oE 'linux-[0-9]+\.[0-9]+-sdm845/' pool_index.html | sort -V | tail -n 1)

if [ -z "$LATEST_SUBDIR" ]; then
    echo ">>> ERROR: Could not find any SDM845 kernel subdirectory."
    exit 1
fi

echo ">>> Latest SDM845 kernel series: $LATEST_SUBDIR"
SUBDIR_URL="${POOL_URL}${LATEST_SUBDIR}"

echo ">>> Fetching kernel package index..."
if ! curl -s -f -L -A "Mozilla/5.0" -o pkg_index.html "$SUBDIR_URL"; then
    echo ">>> ERROR: Cannot fetch kernel subdirectory at $SUBDIR_URL"
    exit 1
fi

IMG_FILE=$(grep -oE "linux-image-[0-9a-zA-Z\.\-]+-sdm845_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)
HDR_FILE=$(grep -oE "linux-headers-[0-9a-zA-Z\.\-]+-sdm845_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)

if [ -z "$IMG_FILE" ] || [ -z "$HDR_FILE" ]; then
    echo ">>> ERROR: Could not parse kernel .deb files from $SUBDIR_URL"
    exit 1
fi

echo ">>> Found: $IMG_FILE"
echo ">>> Found: $HDR_FILE"

echo ">>> Downloading kernel image..."
wget --show-progress -U "Mozilla/5.0" -O linux-image.deb "${SUBDIR_URL}${IMG_FILE}"

echo ">>> Downloading kernel headers..."
wget --show-progress -U "Mozilla/5.0" -O linux-headers.deb "${SUBDIR_URL}${HDR_FILE}"

rm -f pool_index.html pkg_index.html
cd ..
echo ">>> Kernel payloads secured in ./kernel_payload/"
echo ">>> Proceed to script 3."
