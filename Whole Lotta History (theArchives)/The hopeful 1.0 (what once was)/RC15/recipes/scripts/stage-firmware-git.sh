#!/bin/bash
# Mobuntu RC15 — stage-firmware-git.sh
# Runs on HOST (chroot: false). Clones firmware repo into rootfs.
# Env: FIRMWARE_REPO, DEVICE_CODENAME, DEVICE_BRAND
# ROOTDIR is set by debos to the rootfs mount point.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_FW_ARCHIVE="${SCRIPT_DIR}/../../firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}/firmware.tar.gz"

FW_STAGED=false

# --- Prompt if local bundle present ---
if [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>> Local firmware bundle detected: $(basename $LOCAL_FW_ARCHIVE)"
    read -p ">>> Apply local bundle before git clone? [Y/n]: " BUNDLE_CHOICE
    case "${BUNDLE_CHOICE:-Y}" in
        [Nn]*) USE_LOCAL_FIRST=false ;;
        *)     USE_LOCAL_FIRST=true  ;;
    esac
    if [ "$USE_LOCAL_FIRST" = "true" ]; then
        echo ">>> Applying local firmware bundle (base layer)..."
        tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTDIR/"
        echo ">>> Local bundle applied."
        FW_STAGED=true
    fi
fi

# --- Git clone ---
if [ -n "$FIRMWARE_REPO" ]; then
    echo ">>> Cloning: $FIRMWARE_REPO"
    FW_TMP=$(mktemp -d /tmp/fw_XXXX)
    if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>/dev/null; then
        cp -r "$FW_TMP/fw/lib/." "$ROOTDIR/lib/"
        [ -d "$FW_TMP/fw/usr" ] && cp -r "$FW_TMP/fw/usr/." "$ROOTDIR/usr/"
        echo ">>> Git firmware staged."
        FW_STAGED=true
    else
        echo ">>> WARNING: git clone failed."
        if [ "$FW_STAGED" = "false" ] && [ -f "$LOCAL_FW_ARCHIVE" ]; then
            echo ">>> Falling back to local archive..."
            tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTDIR/"
            FW_STAGED=true
        fi
    fi
    rm -rf "$FW_TMP"
fi

# --- OnePlus 6 fallback (last resort, beryllium only) ---
if [ "$FW_STAGED" = "false" ]; then
    echo ""
    echo ">>> ============================================================"
    echo ">>> WARNING: No firmware staged. Falling back to OnePlus 6 blobs."
    echo ">>> These are NOT officially signed for $DEVICE_CODENAME."
    echo ">>> GPU, WiFi and BT should work. Modem is not guaranteed."
    echo ">>> ============================================================"
    ONEPLUS_SRC="/usr/lib/firmware/qcom/sdm845/oneplus6"
    if [ -d "$ONEPLUS_SRC" ]; then
        FW_DEST="$ROOTDIR/lib/firmware/qcom/sdm845/${DEVICE_CODENAME}"
        mkdir -p "$FW_DEST"
        for f in adsp.mbn adspr.jsn adspua.jsn cdsp.mbn cdspr.jsn \
                  ipa_fws.mbn mba.mbn modem.mbn modemr.jsn modemuw.jsn \
                  slpi.mbn slpir.jsn slpius.jsn venus.mbn wlanmdsp.mbn a630_zap.mbn; do
            [ -f "$ONEPLUS_SRC/$f" ] && cp "$ONEPLUS_SRC/$f" "$FW_DEST/$f"
        done
        echo ">>> Fallback firmware staged."
    else
        echo ">>> WARNING: OnePlus6 fallback not found on host."
        echo ">>>   sudo apt install linux-firmware"
    fi
fi

# --- Re-apply local bundle post-git (wins over git overlay) ---
if [ -f "$LOCAL_FW_ARCHIVE" ] && [ "$FW_STAGED" = "true" ]; then
    echo ">>> Re-applying local firmware bundle (priority over git)..."
    tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTDIR/"
fi
