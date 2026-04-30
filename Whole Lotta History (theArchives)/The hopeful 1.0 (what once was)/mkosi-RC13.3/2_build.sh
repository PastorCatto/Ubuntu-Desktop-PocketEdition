#!/bin/bash
# Mobuntu Orange — RC1-mkosi
# [2/2] Build
# Usage: bash 2_build.sh [phosh|plasma-mobile|both]
# In full mode: mkosi builds rootfs + runs finalize (boot.img + root.img)
# In debug mode: mkosi builds rootfs only
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${SCRIPT_DIR}/build.env" ]; then
    echo "ERROR: build.env not found. Run 1_preflight.sh first."
    exit 1
fi
source "${SCRIPT_DIR}/build.env"

PROFILE="${1:-both}"

echo "======================================================="
echo "   Mobuntu Orange — [2/2] Build (mkosi)"
echo "   Device:  $DEVICE_NAME"
echo "   Release: $UBUNTU_RELEASE"
echo "   Profile: $PROFILE"
[ "$DEBUG_MODE" = "true" ] && \
    echo "   Mode:    DEBUG (rootfs only)" || \
    echo "   Mode:    FULL  (rootfs + boot.img + root.img)"
echo "======================================================="

build_profile() {
    local P="$1"
    echo ""
    echo ">>> Building profile: $P"
    echo "======================================================="
    sudo mkosi \
        --profile "$P" \
        --force \
        build
    echo ">>> Profile $P: complete."
}

case "$PROFILE" in
both)
    build_profile phosh
    build_profile plasma-mobile
    ;;
phosh|plasma-mobile)
    build_profile "$PROFILE"
    ;;
*)
    echo "ERROR: Unknown profile '$PROFILE'. Use: phosh | plasma-mobile | both"
    exit 1
    ;;
esac

echo ""
echo "======================================================="
if [ "$DEBUG_MODE" = "true" ]; then
    echo "   DEBUG BUILD COMPLETE"
    echo "   Rootfs: ${SCRIPT_DIR}/output/"
    echo "   Re-run 1_preflight.sh with full mode to produce flashable images."
else
    echo "   FULL BUILD COMPLETE — images ready to flash."
fi
echo "======================================================="
