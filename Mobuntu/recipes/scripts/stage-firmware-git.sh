#!/bin/bash
# Mobuntu RC15 — stage-firmware-git.sh
# Runs on HOST (chroot: false). Clones firmware repo into rootfs.
# Env: FIRMWARE_REPO, DEVICE_CODENAME, DEVICE_BRAND
# ROOTDIR    — set by debos to the rootfs mount point
# ARTIFACTDIR — set by debos to the artifacts dir (= repo root with none backend)

set -e

# ARTIFACTDIR is the debos artifacts directory — with the none backend this is
# the working directory debos was invoked from (the Mobuntu repo root).
# Do NOT use BASH_SOURCE[0] — debos copies scripts to a temp location.
REPO_ROOT="${ARTIFACTDIR}"
LOCAL_FW_ARCHIVE="${REPO_ROOT}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}/firmware.tar.gz"

FW_STAGED=false

# --- Apply local bundle if present (always applied, non-interactive) ---
if [ -f "$LOCAL_FW_ARCHIVE" ]; then
    echo ">>> Local firmware bundle found: $LOCAL_FW_ARCHIVE"
    echo ">>> Applying local firmware bundle (base layer)..."
    tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTDIR/"
    echo ">>> Local bundle applied."
    FW_STAGED=true
else
    echo ">>> No local firmware bundle at $LOCAL_FW_ARCHIVE"
fi

# --- Git clone (overlay on top of local bundle) ---
if [ -n "$FIRMWARE_REPO" ]; then
    echo ">>> Cloning: $FIRMWARE_REPO"
    FW_TMP=$(mktemp -d /tmp/fw_XXXX)
    if git clone --depth=1 "$FIRMWARE_REPO" "$FW_TMP/fw" 2>&1; then
        cp -r "$FW_TMP/fw/lib/." "$ROOTDIR/lib/"
        [ -d "$FW_TMP/fw/usr" ] && cp -r "$FW_TMP/fw/usr/." "$ROOTDIR/usr/"
        echo ">>> Git firmware staged."
        FW_STAGED=true
    else
        echo ">>> WARNING: git clone failed — using local bundle only."
    fi
    rm -rf "$FW_TMP"
fi

# --- Re-apply local bundle post-git (local wins over git overlay) ---
if [ -f "$LOCAL_FW_ARCHIVE" ] && [ "$FW_STAGED" = "true" ]; then
    echo ">>> Re-applying local firmware bundle (priority over git)..."
    tar -xzf "$LOCAL_FW_ARCHIVE" -C "$ROOTDIR/"
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
