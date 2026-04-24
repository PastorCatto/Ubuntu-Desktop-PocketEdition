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

# -------------------------------------------------------
# Check for existing kernel payload — skip download if present
# -------------------------------------------------------
IMG_EXISTING=$(ls linux-image*.deb 2>/dev/null | head -n 1)
HDR_EXISTING=$(ls linux-headers*.deb 2>/dev/null | head -n 1)

if [ -n "$IMG_EXISTING" ] && [ -n "$HDR_EXISTING" ]; then
    echo ">>> Found existing kernel payload:"
    echo "    Image:   $IMG_EXISTING"
    echo "    Headers: $HDR_EXISTING"
    echo ">>> Skipping download."
    cd ..
    echo ">>> Kernel payloads ready in ./kernel_payload/"
    echo ">>> Proceed to script 3."
    exit 0
fi

case "$KERNEL_METHOD" in
mobian)
    POOL_URL="${KERNEL_REPO}"

    if [ -n "$KERNEL_VERSION_PIN" ]; then
        # --- Pinned version mode ---
        echo ">>> Pinned kernel version: $KERNEL_VERSION_PIN"
        KERNEL_MAJOR_MINOR=$(echo "$KERNEL_VERSION_PIN" | grep -oE "^[0-9]+\.[0-9]+")
        SUBDIR_URL="${POOL_URL}linux-${KERNEL_MAJOR_MINOR}-${KERNEL_SERIES}/"

        echo ">>> Fetching package index from $SUBDIR_URL ..."
        wget -q --timeout=30 -U "Mozilla/5.0" -O pkg_index.html "$SUBDIR_URL" || true
        if [ ! -s pkg_index.html ]; then
            echo ">>> ERROR: Cannot fetch $SUBDIR_URL"
            exit 1
        fi

        IMG_FILE=$(grep -oE "linux-image-[^_]+_${KERNEL_VERSION_PIN}-[^_]+_arm64\.deb" pkg_index.html | head -n 1)
        HDR_FILE=$(grep -oE "linux-headers-[^_]+_${KERNEL_VERSION_PIN}-[^_]+_arm64\.deb" pkg_index.html | head -n 1)

        if [ -z "$IMG_FILE" ] || [ -z "$HDR_FILE" ]; then
            echo ">>> ERROR: Pinned version $KERNEL_VERSION_PIN not found in repo."
            echo ">>> Available versions:"
            grep -oE "linux-image-[^_]+_[^_]+_arm64\.deb" pkg_index.html | sort -V | uniq
            rm -f pkg_index.html
            exit 1
        fi

    else
        # --- Latest version mode ---
        echo ">>> Fetching Mobian repository index..."
        wget -q --timeout=30 -U "Mozilla/5.0" -O pool_index.html "$POOL_URL" || true
        if [ ! -s pool_index.html ]; then
            echo ">>> ERROR: Cannot connect to $POOL_URL"
            exit 1
        fi

        echo ""
        echo "Available kernel series (pin one by setting KERNEL_VERSION_PIN in your device config):"
        mapfile -t SERIES_LIST < <(grep -oE "linux-[0-9]+\.[0-9]+-${KERNEL_SERIES}/" pool_index.html | sort -V -u | \
            sed "s/linux-//;s/-${KERNEL_SERIES}\///" )

        for i in "${!SERIES_LIST[@]}"; do
            TAG=""
            [ $i -eq $((${#SERIES_LIST[@]}-1)) ] && TAG=" (latest)"
            echo "  $((i+1))) ${SERIES_LIST[$i]}$TAG  ->  KERNEL_VERSION_PIN=\"${SERIES_LIST[$i]}.x\""
        done
        echo ""

        DEFAULT_IDX=${#SERIES_LIST[@]}
        read -p "Select kernel [1-${#SERIES_LIST[@]}, default $DEFAULT_IDX (latest)]: " KERNEL_CHOICE
        KERNEL_CHOICE=${KERNEL_CHOICE:-$DEFAULT_IDX}
        SELECTED_SERIES="linux-${SERIES_LIST[$((KERNEL_CHOICE-1))]}-${KERNEL_SERIES}/"

        if [ -z "$SELECTED_SERIES" ]; then
            echo ">>> ERROR: Invalid selection."
            exit 1
        fi
        echo ">>> Selected: $SELECTED_SERIES"

        LATEST_SUBDIR="$SELECTED_SERIES"
        rm -f pool_index.html

        if [ -z "$LATEST_SUBDIR" ]; then
            echo ">>> ERROR: No ${KERNEL_SERIES} kernel found in pool index."
            exit 1
        fi

        echo ">>> Using latest: $LATEST_SUBDIR"
        SUBDIR_URL="${POOL_URL}${LATEST_SUBDIR}"

        wget -q --timeout=30 -U "Mozilla/5.0" -O pkg_index.html "$SUBDIR_URL" || true
        if [ ! -s pkg_index.html ]; then
            echo ">>> ERROR: Cannot fetch $SUBDIR_URL"
            exit 1
        fi

        IMG_FILE=$(grep -oE "linux-image-[0-9a-zA-Z\.\-]+-${KERNEL_SERIES}_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)
        HDR_FILE=$(grep -oE "linux-headers-[0-9a-zA-Z\.\-]+-${KERNEL_SERIES}_[^\"]+_arm64\.deb" pkg_index.html | sort -V | tail -n 1)

        if [ -z "$IMG_FILE" ] || [ -z "$HDR_FILE" ]; then
            echo ">>> ERROR: Could not parse kernel .deb files."
            exit 1
        fi
    fi

    echo ">>> Kernel image:   $IMG_FILE"
    echo ">>> Kernel headers: $HDR_FILE"
    wget --show-progress -U "Mozilla/5.0" -O linux-image.deb "${SUBDIR_URL}${IMG_FILE}"
    wget --show-progress -U "Mozilla/5.0" -O linux-headers.deb "${SUBDIR_URL}${HDR_FILE}"
    rm -f pkg_index.html
    ;;

custom_url)
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