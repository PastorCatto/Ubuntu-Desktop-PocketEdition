#!/bin/bash
# Mobuntu — Watchdog / Auto Build
# RC13
# Runs: script 2 → script 3 → verify → script 5
# Appends _autobuild to output image filenames on success.
# Uses hidden ZWJ (U+200D) signal character to confirm clean exits.

SCRIPT_DIR="$(dirname "$0")"
LOG="watchdog_$(date '+%Y%m%d_%H%M%S').log"
SIGNAL=$'\u200d' # ZWJ — hidden watchdog signal character (invisible in terminal)

log()  { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
fail() { log ">>> WATCHDOG FAILED: $1"; exit 1; }

# Auto-sudo wrapper — only active if AUTO_SUDO=true in build.env
maybe_sudo() {
    if [ "$AUTO_SUDO" = "true" ]; then
        sudo -n "$@" 2>/dev/null || sudo "$@"
    else
        "$@"
    fi
}

echo "======================================================="
echo "   Mobuntu — Watchdog / Auto Build"
echo "======================================================="
log ">>> Starting watchdog build. Log: $LOG"

# -------------------------------------------------------
# Step 1: Verify build.env is fully generated
# -------------------------------------------------------
log ">>> Checking build.env..."

if [ ! -f "$SCRIPT_DIR/build.env" ]; then
    fail "build.env not found. Run script 1 first."
fi

source "$SCRIPT_DIR/build.env"

REQUIRED_VARS=(
    UBUNTU_RELEASE ROOTFS_DIR DEVICE_NAME DEVICE_CODENAME
    DEVICE_HOSTNAME BUILD_COLOR USERNAME KERNEL_METHOD
    BOOT_METHOD FIRMWARE_METHOD UI_NAME UI_DM
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        fail "build.env is incomplete — $var is not set. Re-run script 1."
    fi
done

log ">>> build.env OK"

if [ "$AUTO_SUDO" = "true" ]; then
    log ">>> Auto-sudo is ENABLED. Ensure you are in a WSL2 container or VM."
    # Pre-cache sudo credentials
    sudo -v 2>/dev/null || { fail "Auto-sudo enabled but sudo credentials failed."; }
fi

# -------------------------------------------------------
# Step 2: Run script 2 (kernel prep)
# -------------------------------------------------------
log ">>> Running script 2 (kernel prep)..."

SCRIPT2_OUT=$("$SCRIPT_DIR/2_kernel_prep.sh" 2>&1 | tee -a "$LOG")

if echo "$SCRIPT2_OUT" | grep -qP "\x{200d}"; then
    log ">>> Script 2: PASSED (clean signal received)"
else
    fail "Script 2 did not complete cleanly. Check $LOG for details."
fi

# -------------------------------------------------------
# Step 3: Run script 3 (rootfs cooker)
# -------------------------------------------------------
log ">>> Running script 3 (rootfs cooker)..."

SCRIPT3_OUT=$("$SCRIPT_DIR/3_rootfs_cooker.sh" 2>&1 | tee -a "$LOG")

if echo "$SCRIPT3_OUT" | grep -qP "\x{200d}"; then
    log ">>> Script 3: PASSED (clean signal received)"
else
    fail "Script 3 did not complete cleanly. Check $LOG for details."
fi

# -------------------------------------------------------
# Step 4: Run verification
# -------------------------------------------------------
log ">>> Running build verification..."

VERIFY_OUT=$("$SCRIPT_DIR/verify_build.sh" 2>&1 | tee -a "$LOG")

if echo "$VERIFY_OUT" | grep -qP "\x{200d}"; then
    log ">>> Verification: PASSED (clean signal received)"
else
    fail "Build verification failed. Check $LOG for details."
fi

# -------------------------------------------------------
# Step 5: Seal the image
# -------------------------------------------------------
log ">>> Sealing image (script 5)..."

"$SCRIPT_DIR/5_seal_rootfs.sh" 2>&1 | tee -a "$LOG"

if [ $? -ne 0 ]; then
    fail "Script 5 (seal) failed. Check $LOG for details."
fi

log ">>> Image sealed successfully."

# -------------------------------------------------------
# Step 6: Rename output images with _autobuild tag
# -------------------------------------------------------
log ">>> Tagging output images with _autobuild..."

for img in *.img *.img.sparse; do
    [ -f "$img" ] || continue
    BASENAME="${img%.img}"
    BASENAME="${BASENAME%.img.sparse}"
    EXT="${img##*.}"
    NEWNAME="${BASENAME}_autobuild.${EXT}"
    mv "$img" "$NEWNAME"
    log ">>> Renamed: $img → $NEWNAME"
done

# -------------------------------------------------------
# Done
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   WATCHDOG COMPLETE — Auto build successful"
echo "   Log: $LOG"
echo "======================================================="
