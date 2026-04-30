#!/bin/sh
# Mobuntu Orange — remoteproc-adsp-trigger.sh
# Called by udev when remoteproc device appears.
# Waits until rmtfs and pd-mapper are active before starting the DSP.
# This prevents the ~60s crash caused by the ADSP booting before
# userspace firmware daemons are ready to serve blob requests.

RPROC_PATH="$DEVPATH"
RPROC_NAME=$(cat "/sys${RPROC_PATH}/name" 2>/dev/null || echo "unknown")
STATE_FILE="/sys${RPROC_PATH}/state"

logger -t remoteproc-trigger "[$RPROC_NAME] udev add fired, waiting for rmtfs + pd-mapper..."

# Already running — nothing to do
CURRENT=$(cat "$STATE_FILE" 2>/dev/null)
if [ "$CURRENT" = "running" ]; then
    logger -t remoteproc-trigger "[$RPROC_NAME] already running, skipping."
    exit 0
fi

# Wait up to 30 seconds for rmtfs and pd-mapper to be active
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    RMTFS_OK=$(systemctl is-active rmtfs 2>/dev/null)
    PDMAPPER_OK=$(systemctl is-active pd-mapper 2>/dev/null)
    if [ "$RMTFS_OK" = "active" ] && [ "$PDMAPPER_OK" = "active" ]; then
        logger -t remoteproc-trigger "[$RPROC_NAME] rmtfs + pd-mapper active after ${ELAPSED}s, starting DSP..."
        echo "start" > "$STATE_FILE" 2>/dev/null && \
            logger -t remoteproc-trigger "[$RPROC_NAME] start triggered OK." || \
            logger -t remoteproc-trigger "[$RPROC_NAME] WARNING: failed to write start to $STATE_FILE"
        exit 0
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

logger -t remoteproc-trigger "[$RPROC_NAME] TIMEOUT: rmtfs/pd-mapper not ready after ${TIMEOUT}s, skipping DSP start."
exit 1
