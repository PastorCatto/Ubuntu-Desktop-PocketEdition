#!/bin/bash
set -e
source build.env
echo "======================================================="
echo "   Mobuntu Orange — [2/5] Kernel Payload Staging"
echo "======================================================="
echo ">>> Device: $DEVICE_NAME"
echo ">>> Kernel method: $KERNEL_METHOD"

mkdir -p kernel_payload
cd kernel_payload

case "$KERNEL_METHOD" in
mobian)
    POOL_URL="${KERNEL_REPO}"
    echo ">>> Fetching Mobian repository index..."
    if ! curl -s -f -L -A "Mozilla/5.0" -o pool_index.html "$POOL_URL"; then
        echo ">>> ERROR: Cannot connect to $POOL_URL"
        exit 1
    fi

    LATEST_SUBDIR=$(grep -oE "linux-[0-9]+\.[0-9]+-${KERNEL_SERIES}/" pool_index.html | sort -V | tail -n 1)
    if [ -z "$LATEST_SUBDIR" ]; then
        echo ">>> ERROR: No ${KERNEL_SERIES} kernel found in pool index."
        exit 1
    fi
    echo ">>> Latest kernel series: $LATEST_SUBDIR"
    SUBDIR_URL="${POOL_URL}${LATEST_SUBDIR}"

    curl -s -f -L -A "Mozilla/5.0" -o pkg_index.html "$SUBDIR_URL" || {
        echo ">>> ERROR: Cannot fetch $SUBDIR_URL"; exit 1
    }

    IMG_FILE=$(grep -oE "linux-image-[0-9a-zA-Z\.\-]+-${KERNEL_SERIES}_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)
    HDR_FILE=$(grep -oE "linux-headers-[0-9a-zA-Z\.\-]+-${KERNEL_SERIES}_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)

    if [ -z "$IMG_FILE" ] || [ -z "$HDR_FILE" ]; then
        echo ">>> ERROR: Could not parse kernel .deb files."
        exit 1
    fi

    echo ">>> Kernel image:   $IMG_FILE"
    echo ">>> Kernel headers: $HDR_FILE"
    wget --show-progress -U "Mozilla/5.0" -O linux-image.deb "${SUBDIR_URL}${IMG_FILE}"
    wget --show-progress -U "Mozilla/5.0" -O linux-headers.deb "${SUBDIR_URL}${HDR_FILE}"
    rm -f pool_index.html pkg_index.html
    ;;

# --- Placeholder for future kernel methods ---
custom_url)
    # KERNEL_REPO should point directly to a .deb URL
    echo ">>> Fetching kernel from custom URL: $KERNEL_REPO"
    wget --show-progress -O linux-image.deb "$KERNEL_REPO"
    ;;

*)
    echo ">>> ERROR: Unknown KERNEL_METHOD '$KERNEL_METHOD'"
    exit 1
    ;;
esac

cd ..
echo ">>> Kernel payloads staged in ./kernel_payload/"
echo ">>> Proceed to script 3."
