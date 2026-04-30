#!/bin/bash
# Mobuntu — Build Verification Script
# RC13
# Run from host after script 3 completes.
# Cross-checks build.env against device config and rootfs.

PASS=0
FAIL=0
WARN=0

ok()   { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
warn() { echo "  [WARN] $1"; ((WARN++)); }

echo "======================================================="
echo "   Mobuntu — Build Verification"
echo "======================================================="

# -------------------------------------------------------
# Step 1: Check build.env exists and is populated
# -------------------------------------------------------
echo ""
echo "--- build.env ---"

if [ ! -f "build.env" ]; then
    fail "build.env not found"
    exit 1
fi

source build.env

for var in UBUNTU_RELEASE ROOTFS_DIR DEVICE_NAME DEVICE_CODENAME \
           DEVICE_HOSTNAME BUILD_COLOR USERNAME KERNEL_METHOD \
           BOOT_METHOD FIRMWARE_METHOD UI_NAME UI_DM; do
    if [ -z "${!var}" ]; then
        fail "$var is not set in build.env"
    else
        ok "$var = ${!var}"
    fi
done

# -------------------------------------------------------
# Step 2: Check device config exists
# -------------------------------------------------------
echo ""
echo "--- Device Config ---"

if [ ! -f "$DEVICE_CONF" ]; then
    fail "Device config not found: $DEVICE_CONF"
else
    ok "Device config: $DEVICE_CONF"
fi

# -------------------------------------------------------
# Step 3: Check rootfs exists
# -------------------------------------------------------
echo ""
echo "--- RootFS ---"

if [ ! -d "$ROOTFS_DIR" ]; then
    fail "RootFS directory not found: $ROOTFS_DIR"
    exit 1
else
    ok "RootFS exists: $ROOTFS_DIR"
fi

# -------------------------------------------------------
# Step 4: Check hostname in rootfs matches build.env
# -------------------------------------------------------
echo ""
echo "--- Hostname ---"

ROOTFS_HOSTNAME=$(cat "$ROOTFS_DIR/etc/hostname" 2>/dev/null)
if [ "$ROOTFS_HOSTNAME" = "$DEVICE_HOSTNAME" ]; then
    ok "Hostname matches: $DEVICE_HOSTNAME"
else
    fail "Hostname mismatch: build.env=$DEVICE_HOSTNAME rootfs=$ROOTFS_HOSTNAME"
fi

# -------------------------------------------------------
# Step 5: Check critical packages installed
# -------------------------------------------------------
echo ""
echo "--- Packages ---"

REQUIRED_PKGS="qrtr-tools rmtfs pd-mapper tqftpserv protection-domain-mapper \
               pipewire wireplumber alsa-ucm-conf qcom-phone-utils"

for pkg in $REQUIRED_PKGS hexagonrpcd; do
    if grep -ql "^Package: $pkg$" "$ROOTFS_DIR/var/lib/dpkg/info/${pkg}.list" 2>/dev/null ||        grep -q "^Package: $pkg$" "$ROOTFS_DIR/var/lib/dpkg/status" 2>/dev/null; then
        ok "$pkg installed"
    else
        fail "$pkg NOT installed"
        case "$pkg" in
            qrtr-tools)    warn "pd-mapper and rmtfs depend on qrtr-tools" ;;
            rmtfs)         warn "ADSP/modem firmware access will fail" ;;
            pd-mapper)     warn "Protection domain mapping will fail" ;;
            wireplumber)   warn "Audio routing will not work" ;;
            alsa-ucm-conf) warn "ALSA UCM maps missing — no audio profiles" ;;
            hexagonrpcd)   warn "ADSP/audio will not work" ;;
        esac
    fi
done

# -------------------------------------------------------
# Step 6: Check services enabled
# -------------------------------------------------------
echo ""
echo "--- Services ---"

REQUIRED_SVCS="qrtr-ns rmtfs pd-mapper tqftpserv hexagonrpcd"

for svc in $REQUIRED_SVCS; do
    if [ -f "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/${svc}.service" ] || \
       [ -L "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/${svc}.service" ]; then
        ok "$svc enabled"
    else
        fail "$svc NOT enabled"
    fi
done

# -------------------------------------------------------
# Step 7: Check service ordering drop-ins
# -------------------------------------------------------
echo ""
echo "--- Service Ordering ---"

for svc in pd-mapper rmtfs hexagonrpcd; do
    if [ -f "$ROOTFS_DIR/etc/systemd/system/${svc}.service.d/ordering.conf" ]; then
        ok "${svc} ordering drop-in present"
    else
        warn "${svc} ordering drop-in missing — may start out of order"
    fi
done

# -------------------------------------------------------
# Step 8: Check WirePlumber config
# -------------------------------------------------------
echo ""
echo "--- Audio Config ---"

WP_CONF="$ROOTFS_DIR/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf"
if [ -f "$WP_CONF" ]; then
    ok "51-qcom.conf present"
    if grep -q "api.alsa.period-size" "$WP_CONF"; then
        ok "ALSA tuning values present in 51-qcom.conf"
    else
        warn "51-qcom.conf exists but ALSA tuning values missing"
    fi
else
    fail "51-qcom.conf missing — audio will not work correctly"
    warn "WirePlumber has no SDM845 ALSA tuning — expect crackling or silence"
fi

# -------------------------------------------------------
# Step 9: Check kernel installed
# -------------------------------------------------------
echo ""
echo "--- Kernel ---"

KERNEL=$(ls "$ROOTFS_DIR/boot/vmlinuz-"*sdm845* 2>/dev/null | head -n 1)
if [ -n "$KERNEL" ]; then
    ok "SDM845 kernel found: $(basename $KERNEL)"
else
    fail "No SDM845 kernel found in $ROOTFS_DIR/boot/"
fi

INITRD=$(ls "$ROOTFS_DIR/boot/initrd.img-"*sdm845* 2>/dev/null | head -n 1)
if [ -n "$INITRD" ]; then
    ok "initrd found: $(basename $INITRD)"
else
    fail "No initrd found — boot will fail"
fi

# -------------------------------------------------------
# Step 10: Check firmware
# -------------------------------------------------------
echo ""
echo "--- Firmware ---"

FW_FILES="adsp.mbn cdsp.mbn venus.mbn"
for fw in $FW_FILES; do
    if find "$ROOTFS_DIR/lib/firmware" -name "$fw" 2>/dev/null | grep -q .; then
        ok "$fw present"
    else
        warn "$fw not found — hardware may not function"
    fi
done

# -------------------------------------------------------
# Step 11: Check ALSA services masked
# -------------------------------------------------------
echo ""
echo "--- ALSA Service Masking ---"

for svc in alsa-state alsa-restore; do
    if [ -L "$ROOTFS_DIR/etc/systemd/system/${svc}.service" ]; then
        TARGET=$(readlink "$ROOTFS_DIR/etc/systemd/system/${svc}.service")
        if echo "$TARGET" | grep -q "dev/null"; then
            ok "${svc} masked"
        else
            warn "${svc} symlink exists but not masked (points to $TARGET)"
        fi
    else
        warn "${svc} not masked — may conflict with SDM845 audio"
    fi
done

# -------------------------------------------------------
# Step 12: Check qcom-firmware initramfs hook
# -------------------------------------------------------
echo ""
echo "--- Initramfs Hook ---"

if [ -f "$ROOTFS_DIR/usr/share/initramfs-tools/hooks/qcom-firmware" ]; then
    ok "qcom-firmware initramfs hook present"
    if [ -x "$ROOTFS_DIR/usr/share/initramfs-tools/hooks/qcom-firmware" ]; then
        ok "qcom-firmware hook is executable"
    else
        warn "qcom-firmware hook is not executable"
    fi
else
    fail "qcom-firmware initramfs hook missing — firmware may not load on boot"
fi

# -------------------------------------------------------
# Step 13: Check autoresize service
# -------------------------------------------------------
echo ""
echo "--- Autoresize ---"

if [ -f "$ROOTFS_DIR/etc/systemd/system/mobuntu-resize.service" ]; then
    ok "mobuntu-resize.service present"
    if [ -f "$ROOTFS_DIR/etc/mobuntu-resize-pending" ]; then
        ok "resize pending flag set (will run on first boot)"
    else
        warn "resize pending flag missing — autoresize may not trigger"
    fi
else
    warn "mobuntu-resize.service not present — partition will not auto-expand"
fi

# -------------------------------------------------------
# Step 14: Check build color matches hostname
# -------------------------------------------------------
echo ""
echo "--- Build Color ---"

if [ -n "$BUILD_COLOR" ]; then
    if echo "$DEVICE_HOSTNAME" | grep -qi "$BUILD_COLOR"; then
        ok "Hostname contains build color: $BUILD_COLOR"
    else
        warn "Hostname ($DEVICE_HOSTNAME) does not reflect BUILD_COLOR ($BUILD_COLOR)"
    fi
else
    warn "BUILD_COLOR not set in build.env"
fi

# -------------------------------------------------------
# Summary
# -------------------------------------------------------
echo ""
echo "======================================================="
echo "   RESULTS: $PASS passed  |  $WARN warnings  |  $FAIL failed"
echo "======================================================="

if [ $FAIL -eq 0 ]; then
    echo "ALL CHECKS PASSED&#x200d;" # &#x200d; = ZWJ watchdog signal (invisible)
    exit 0
else
    echo "BUILD VERIFICATION FAILED — $FAIL checks failed"
    exit 1
fi
