#!/bin/bash
# Mobuntu Orange — RC1-mkosi
# Watchdog — automated build pipeline
# Runs: preflight (if needed) → build phosh → build plasma-mobile → seal both
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="watchdog_$(date '+%Y%m%d_%H%M%S').log"

log()  { echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"; }
fail() { log "WATCHDOG FAILED: $1"; exit 1; }

echo "======================================================="
echo "   Mobuntu Orange — Watchdog (mkosi)"
echo "======================================================="
log ">>> Starting. Log: $LOG"

# -------------------------------------------------------
# Step 1: Check build.env
# -------------------------------------------------------
if [ ! -f "${SCRIPT_DIR}/build.env" ]; then
    log ">>> build.env not found — running preflight..."
    bash "${SCRIPT_DIR}/1_preflight.sh" | tee -a "$LOG"
fi
source "${SCRIPT_DIR}/build.env"
log ">>> build.env OK — Device: $DEVICE_NAME  Release: $UBUNTU_RELEASE"

# -------------------------------------------------------
# Step 2: Build both profiles
# -------------------------------------------------------
for PROFILE in phosh plasma-mobile; do
    log ">>> Building profile: $PROFILE..."
    bash "${SCRIPT_DIR}/2_build.sh" "$PROFILE" 2>&1 | tee -a "$LOG"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        fail "Build failed for profile: $PROFILE"
    fi
    log ">>> Profile $PROFILE: built OK."
done

# -------------------------------------------------------
# Step 3: Seal both profiles
# -------------------------------------------------------
for PROFILE in phosh plasma-mobile; do
    log ">>> Sealing profile: $PROFILE..."
    # Auto-answer seal prompts: quiet splash, autoresize yes
    echo -e "1\n1" | bash "${SCRIPT_DIR}/3_seal.sh" "$PROFILE" 2>&1 | tee -a "$LOG"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        fail "Seal failed for profile: $PROFILE"
    fi
    log ">>> Profile $PROFILE: sealed OK."
done

# -------------------------------------------------------
# Step 4: Tag outputs
# -------------------------------------------------------
log ">>> Tagging output images..."
for img in *.img *.img.sparse 2>/dev/null; do
    [ -f "$img" ] || continue
    NEWNAME="${img%.img}_autobuild.img"
    mv "$img" "$NEWNAME" 2>/dev/null && log ">>> Renamed: $img → $NEWNAME" || true
done

echo ""
echo "======================================================="
echo "   WATCHDOG COMPLETE"
echo "   Log: $LOG"
echo "======================================================="
