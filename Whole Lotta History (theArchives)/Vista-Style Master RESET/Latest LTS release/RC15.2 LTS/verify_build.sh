#!/bin/bash
# Mobuntu — Build Verification Script
# RC15 — verifies debos output tarball before sealing
set -e

PASS=0; FAIL=0; WARN=0
ok()   { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
warn() { echo "  [WARN] $1"; ((WARN++)); }

echo "======================================================="
echo "   Mobuntu — Build Verification RC15"
echo "======================================================="

# -------------------------------------------------------
# Step 1: build.env
# -------------------------------------------------------
echo ""
echo "--- build.env ---"
[ ! -f "build.env" ] && { fail "build.env not found"; exit 1; }
source build.env

has_quirk() { echo " ${DEVICE_QUIRKS} " | grep -qw "$1"; }

for var in UBUNTU_RELEASE DEVICE_NAME DEVICE_CODENAME DEVICE_IMAGE_LABEL \
           DEVICE_HOSTNAME BUILD_COLOR USERNAME KERNEL_METHOD \
           BOOT_METHOD FIRMWARE_METHOD UI_NAME UI_DM FAKEMACHINE_BACKEND; do
    if [ -z "${!var}" ]; then
        fail "$var not set in build.env"
    else
        ok "$var = ${!var}"
    fi
done

# -------------------------------------------------------
# Step 2: Device tarball
# -------------------------------------------------------
echo ""
echo "--- Device Tarball ---"

DEVICE_TARBALL="${DEVICE_IMAGE_LABEL}-${UBUNTU_RELEASE}.tar.gz"
BASE_TARBALL="base-${UBUNTU_RELEASE}.tar.gz"

if [ -f "$BASE_TARBALL" ]; then
    ok "Base tarball present: $BASE_TARBALL ($(du -h $BASE_TARBALL | cut -f1))"
else
    warn "Base tarball not found: $BASE_TARBALL"
fi

if [ ! -f "$DEVICE_TARBALL" ]; then
    fail "Device tarball not found: $DEVICE_TARBALL"
    echo ""
    echo "Run: bash run_build.sh"
    echo "RESULTS: $PASS passed | $WARN warnings | $FAIL failed"
    exit 1
fi
ok "Device tarball: $DEVICE_TARBALL ($(du -h $DEVICE_TARBALL | cut -f1))"

# Sanity check tarball is not tiny (< 200MB indicates something went wrong)
TARBALL_BYTES=$(stat -c%s "$DEVICE_TARBALL")
if [ "$TARBALL_BYTES" -lt 209715200 ]; then
    warn "Device tarball is suspiciously small ($(du -h $DEVICE_TARBALL | cut -f1)) — build may have failed"
else
    ok "Device tarball size looks reasonable"
fi

# -------------------------------------------------------
# Step 3: Unpack to temp dir for inspection
# -------------------------------------------------------
echo ""
echo "--- Rootfs Inspection ---"

VERIFY_DIR=$(mktemp -d /tmp/mobuntu-verify-XXXX)
echo ">>> Unpacking to $VERIFY_DIR (this may take a moment)..."
sudo tar -xzf "$DEVICE_TARBALL" -C "$VERIFY_DIR/" 2>/dev/null
echo ">>> Unpacked."

# -------------------------------------------------------
# Step 4: Hostname
# -------------------------------------------------------
echo ""
echo "--- Hostname ---"
ROOTFS_HOSTNAME=$(cat "$VERIFY_DIR/etc/hostname" 2>/dev/null)
if [ "$ROOTFS_HOSTNAME" = "$DEVICE_HOSTNAME" ]; then
    ok "Hostname: $DEVICE_HOSTNAME"
else
    fail "Hostname mismatch: expected=$DEVICE_HOSTNAME actual=$ROOTFS_HOSTNAME"
fi

# -------------------------------------------------------
# Step 5: Packages + services (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Packages (Qualcomm) ---"
    for pkg in qrtr-tools rmtfs pd-mapper tqftpserv \
               pipewire wireplumber alsa-ucm-conf; do
        if grep -q "^Package: $pkg$" \
           "$VERIFY_DIR/var/lib/dpkg/status" 2>/dev/null; then
            ok "$pkg installed"
        else
            fail "$pkg NOT installed"
        fi
    done
    # hexagonrpcd must be absent
    if grep -q "^Package: hexagonrpcd$" \
       "$VERIFY_DIR/var/lib/dpkg/status" 2>/dev/null; then
        fail "hexagonrpcd present (must NOT be installed — see known issues)"
    else
        ok "hexagonrpcd absent (correct)"
    fi

    echo ""
    echo "--- Services (Qualcomm) ---"
    for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
        WANTS="$VERIFY_DIR/etc/systemd/system/multi-user.target.wants/${svc}.service"
        [ -f "$WANTS" ] || [ -L "$WANTS" ] && ok "$svc enabled" || fail "$svc NOT enabled"
    done

    echo ""
    echo "--- Service Ordering ---"
    for svc in pd-mapper rmtfs; do
        DROP="$VERIFY_DIR/etc/systemd/system/${svc}.service.d/ordering.conf"
        [ -f "$DROP" ] && ok "$svc ordering drop-in present" || \
            warn "$svc ordering drop-in missing"
    done

    echo ""
    echo "--- Audio Config ---"
    WP_CONF="$VERIFY_DIR/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf"
    if [ -f "$WP_CONF" ]; then
        ok "51-qcom.conf present"
    else
        fail "51-qcom.conf missing — audio tuning not applied"
    fi

    echo ""
    echo "--- ALSA Masking ---"
    for svc in alsa-state alsa-restore; do
        MASK="$VERIFY_DIR/etc/systemd/system/${svc}.service"
        if [ -L "$MASK" ] && readlink "$MASK" | grep -q "dev/null"; then
            ok "$svc masked"
        else
            warn "$svc not masked — may conflict with SDM845 audio"
        fi
    done

    echo ""
    echo "--- Initramfs Hook ---"
    HOOK="$VERIFY_DIR/usr/share/initramfs-tools/hooks/qcom-firmware"
    if [ -f "$HOOK" ]; then
        ok "qcom-firmware hook present"
        [ -x "$HOOK" ] && ok "qcom-firmware hook executable" || \
            warn "qcom-firmware hook not executable"
    else
        fail "qcom-firmware hook missing — firmware may not load on boot"
    fi

    echo ""
    echo "--- Firmware ---"
    for fw in adsp.mbn cdsp.mbn venus.mbn; do
        find "$VERIFY_DIR/lib/firmware" -name "$fw" 2>/dev/null | grep -q . && \
            ok "$fw present" || warn "$fw not found"
    done
fi

# -------------------------------------------------------
# Step 6: Kernel
# -------------------------------------------------------
echo ""
echo "--- Kernel ---"
if has_quirk "qcom_services"; then
    KERNEL=$(ls "$VERIFY_DIR/boot/vmlinuz-"*sdm845* 2>/dev/null | head -n 1)
    KERN_LABEL="SDM845"
else
    KERNEL=$(ls "$VERIFY_DIR/boot/vmlinuz-"* 2>/dev/null | head -n 1)
    KERN_LABEL="$DEVICE_CODENAME"
fi

if [ -n "$KERNEL" ]; then
    ok "$KERN_LABEL kernel: $(basename $KERNEL)"
else
    fail "No $KERN_LABEL kernel found"
fi

INITRD=$(ls "$VERIFY_DIR/boot/initrd.img-"* 2>/dev/null | head -n 1)
[ -n "$INITRD" ] && ok "initrd: $(basename $INITRD)" || fail "initrd missing"

# -------------------------------------------------------
# Step 7: Autoresize
# -------------------------------------------------------
echo ""
echo "--- Autoresize ---"
RESIZE_SVC="$VERIFY_DIR/etc/systemd/system/mobuntu-resize.service"
if [ -f "$RESIZE_SVC" ]; then
    ok "mobuntu-resize.service present"
    [ -f "$VERIFY_DIR/etc/mobuntu-resize-pending" ] && \
        ok "resize pending flag set" || \
        warn "resize pending flag missing"
else
    warn "mobuntu-resize.service absent — partition will not auto-expand"
fi

# -------------------------------------------------------
# Step 8: run_build.sh present and not stale
# -------------------------------------------------------
echo ""
echo "--- Build Artifacts ---"
[ -f "run_build.sh" ] && ok "run_build.sh present" || fail "run_build.sh missing"
[ -f "build.env" ]    && ok "build.env present"    || fail "build.env missing"

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
echo ""
echo ">>> Cleaning up verification directory..."
sudo rm -rf "$VERIFY_DIR"

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   RESULTS: $PASS passed  |  $WARN warnings  |  $FAIL failed"
echo "======================================================="
if [ $FAIL -eq 0 ]; then
    echo "ALL CHECKS PASSED&#x200d;"
    exit 0
else
    echo "VERIFICATION FAILED — $FAIL checks failed"
    exit 1
fi
