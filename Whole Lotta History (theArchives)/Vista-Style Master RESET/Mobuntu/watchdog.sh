#!/bin/bash
# Mobuntu — RC15 watchdog.sh
# Unattended build runner. Wraps run_build.sh (debos pipeline).
# Uses ZWJ (U+200D, U+200D) at end of run_build.sh output as clean-exit signal.
# Requires WATCHDOG_ENABLED=true and optionally AUTO_SUDO=true in build.env.

set -e
source build.env

if [ "$WATCHDOG_ENABLED" != "true" ]; then
    echo ">>> Watchdog not enabled. Set WATCHDOG_ENABLED=true in build.env"
    echo ">>> or re-run 1_preflight.sh and enable it there."
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/watchdog-$(date +%Y%m%d-%H%M%S).log"
MAX_RETRIES=3
RETRY=0
ZWJ=$'\xe2\x80\x8d'  # U+200D Zero Width Joiner — clean-exit signal

echo "======================================================="
echo "   Mobuntu RC15 — Watchdog"
echo "   Device:  $DEVICE_NAME"
echo "   Release: $UBUNTU_RELEASE"
echo "   Log:     $LOG_FILE"
echo "======================================================="

# Auto-sudo: extend sudo timeout to avoid prompts during long builds
if [ "$AUTO_SUDO" = "true" ]; then
    echo ">>> Auto-sudo enabled — extending sudo timeout..."
    sudo -v
    # Keepalive: update sudo timestamp every 50 seconds
    ( while true; do sudo -v; sleep 50; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap "kill $SUDO_KEEPALIVE_PID 2>/dev/null || true" EXIT
fi

run_build() {
    echo ">>> [Attempt $((RETRY+1))/$MAX_RETRIES] Starting run_build.sh..."
    bash "${SCRIPT_DIR}/run_build.sh" 2>&1 | tee -a "$LOG_FILE"
    return ${PIPESTATUS[0]}
}

while [ $RETRY -lt $MAX_RETRIES ]; do
    if run_build; then
        # Check for clean-exit ZWJ signal in log
        if grep -q "$ZWJ" "$LOG_FILE" 2>/dev/null; then
            echo ""
            echo ">>> Clean exit signal detected — build complete."
            echo ">>> Running verify_build.sh..."
            bash "${SCRIPT_DIR}/verify_build.sh" 2>&1 | tee -a "$LOG_FILE"
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo ">>> Verification passed. Running 5_seal_rootfs.sh..."
                bash "${SCRIPT_DIR}/5_seal_rootfs.sh" 2>&1 | tee -a "$LOG_FILE"
            else
                echo ">>> Verification FAILED — not sealing. Check $LOG_FILE"
                exit 1
            fi
            echo ">>> Watchdog finished successfully."
            exit 0
        else
            echo ">>> WARNING: Build exited cleanly but ZWJ signal not found."
            echo ">>>          Treating as failure and retrying."
        fi
    else
        echo ">>> Build failed on attempt $((RETRY+1))."
    fi

    RETRY=$((RETRY+1))
    if [ $RETRY -lt $MAX_RETRIES ]; then
        echo ">>> Retrying in 10 seconds..."
        sleep 10
    fi
done

echo ">>> Watchdog: all $MAX_RETRIES attempts failed. Check $LOG_FILE"
exit 1
