#!/bin/bash
# Mobuntu — Build Verification Script
# RC14
set -e
PASS=0; FAIL=0; WARN=0
ok()   { echo "  [PASS] $1"; ((PASS++)); }
fail() { echo "  [FAIL] $1"; ((FAIL++)); }
warn() { echo "  [WARN] $1"; ((WARN++)); }

echo "======================================================="
echo "   Mobuntu — Build Verification -- RC14"
echo "======================================================="

# -------------------------------------------------------
# Step 1: build.env
# -------------------------------------------------------
echo ""
echo "--- build.env ---"
if [ ! -f "build.env" ]; then
    fail "build.env not found"; exit 1
fi
source build.env

has_quirk() { echo " ${DEVICE_QUIRKS} " | grep -qw "$1"; }

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
# Step 2: Device config
# -------------------------------------------------------
echo ""
echo "--- Device Config ---"
if [ ! -f "$DEVICE_CONF" ]; then
    fail "Device config not found: $DEVICE_CONF"
else
    ok "Device config: $DEVICE_CONF"
fi

# -------------------------------------------------------
# Step 3: RootFS exists
# -------------------------------------------------------
echo ""
echo "--- RootFS ---"
if [ ! -d "$ROOTFS_DIR" ]; then
    fail "RootFS directory not found: $ROOTFS_DIR"; exit 1
else
    ok "RootFS exists: $ROOTFS_DIR"
fi

# -------------------------------------------------------
# Step 4: Hostname
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
# Step 5: Packages (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Packages (Qualcomm) ---"
    REQUIRED_PKGS="qrtr-tools rmtfs pd-mapper tqftpserv protection-domain-mapper \
                   pipewire wireplumber alsa-ucm-conf"
    for pkg in $REQUIRED_PKGS; do
        if grep -q "^Package: $pkg$" "$ROOTFS_DIR/var/lib/dpkg/status" 2>/dev/null; then
            ok "$pkg installed"
        else
            fail "$pkg NOT installed"
        fi
    done
fi

# -------------------------------------------------------
# Step 6: Services (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Services (Qualcomm) ---"
    for svc in qrtr-ns rmtfs pd-mapper tqftpserv; do
        if [ -f "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/${svc}.service" ] || \
           [ -L "$ROOTFS_DIR/etc/systemd/system/multi-user.target.wants/${svc}.service" ]; then
            ok "$svc enabled"
        else
            fail "$svc NOT enabled"
        fi
    done
fi

# -------------------------------------------------------
# Step 7: Service ordering drop-ins (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Service Ordering (Qualcomm) ---"
    for svc in pd-mapper rmtfs; do
        if [ -f "$ROOTFS_DIR/etc/systemd/system/${svc}.service.d/ordering.conf" ]; then
            ok "${svc} ordering drop-in present"
        else
            warn "${svc} ordering drop-in missing — may start out of order"
        fi
    done
fi

# -------------------------------------------------------
# Step 8: WirePlumber config (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Audio Config (Qualcomm) ---"
    WP_CONF="$ROOTFS_DIR/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf"
    if [ -f "$WP_CONF" ]; then
        ok "51-qcom.conf present"
        grep -q "api.alsa.period-size" "$WP_CONF" && ok "ALSA tuning values present" || \
            warn "51-qcom.conf exists but ALSA tuning values missing"
    else
        fail "51-qcom.conf missing — audio will not work correctly"
    fi
fi

# -------------------------------------------------------
# Step 9: Kernel
# -------------------------------------------------------
echo ""
echo "--- Kernel ---"
if has_quirk "qcom_services"; then
    KERNEL=$(ls "$ROOTFS_DIR/boot/vmlinuz-"*sdm845* 2>/dev/null | head -n 1)
    INITRD=$(ls "$ROOTFS_DIR/boot/initrd.img-"*sdm845* 2>/dev/null | head -n 1)
    KERN_LABEL="SDM845"
else
    KERNEL=$(ls "$ROOTFS_DIR/boot/vmlinuz-"* 2>/dev/null | head -n 1)
    INITRD=$(ls "$ROOTFS_DIR/boot/initrd.img-"* 2>/dev/null | head -n 1)
    KERN_LABEL="$DEVICE_CODENAME"
fi
[ -n "$KERNEL" ] && ok "$KERN_LABEL kernel found: $(basename $KERNEL)" || fail "No $KERN_LABEL kernel found"
[ -n "$INITRD" ] && ok "initrd found: $(basename $INITRD)" || fail "No initrd found — boot will fail"

# -------------------------------------------------------
# Step 10: Firmware blobs (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Firmware (Qualcomm) ---"
    for fw in adsp.mbn cdsp.mbn venus.mbn slpi.mbn; do
        if find "$ROOTFS_DIR/lib/firmware" -name "$fw" 2>/dev/null | grep -q .; then
            ok "$fw present"
        else
            warn "$fw not found — hardware may not function"
        fi
    done
    # Check sidecars
    for jsn in slpir.jsn slpius.jsn adspr.jsn adspua.jsn; do
        if find "$ROOTFS_DIR/lib/firmware" -name "$jsn" 2>/dev/null | grep -q .; then
            ok "$jsn present"
        else
            warn "$jsn not found — remoteproc recovery may fail"
        fi
    done
fi

# -------------------------------------------------------
# Step 11: ALSA services masked (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- ALSA Service Masking (Qualcomm) ---"
    for svc in alsa-state alsa-restore; do
        if [ -L "$ROOTFS_DIR/etc/systemd/system/${svc}.service" ]; then
            TARGET=$(readlink "$ROOTFS_DIR/etc/systemd/system/${svc}.service")
            echo "$TARGET" | grep -q "dev/null" && ok "${svc} masked" || \
                warn "${svc} symlink exists but not masked (points to $TARGET)"
        else
            warn "${svc} not masked — may conflict with SDM845 audio"
        fi
    done
fi

# -------------------------------------------------------
# Step 12: qcom-firmware initramfs hook (Qualcomm only)
# -------------------------------------------------------
if has_quirk "qcom_services"; then
    echo ""
    echo "--- Initramfs Hook (Qualcomm) ---"
    if [ -f "$ROOTFS_DIR/usr/share/initramfs-tools/hooks/qcom-firmware" ]; then
        ok "qcom-firmware initramfs hook present"
        [ -x "$ROOTFS_DIR/usr/share/initramfs-tools/hooks/qcom-firmware" ] && \
            ok "qcom-firmware hook is executable" || warn "qcom-firmware hook is not executable"
    else
        fail "qcom-firmware initramfs hook missing — firmware may not load on boot"
    fi
fi

# -------------------------------------------------------
# Step 13: Autoresize
# -------------------------------------------------------
echo ""
echo "--- Autoresize ---"
if [ -f "$ROOTFS_DIR/etc/systemd/system/mobuntu-resize.service" ]; then
    ok "mobuntu-resize.service present"
    [ -f "$ROOTFS_DIR/etc/mobuntu-resize-pending" ] && \
        ok "resize pending flag set" || warn "resize pending flag missing"
else
    warn "mobuntu-resize.service not present — partition will not auto-expand"
fi

# -------------------------------------------------------
# Step 14: Build color in hostname
# -------------------------------------------------------
echo ""
echo "--- Build Color ---"
if [ -n "$BUILD_COLOR" ]; then
    echo "$DEVICE_HOSTNAME" | grep -qi "$BUILD_COLOR" && \
        ok "Hostname contains build color: $BUILD_COLOR" || \
        warn "Hostname ($DEVICE_HOSTNAME) does not reflect BUILD_COLOR ($BUILD_COLOR)"
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
    echo "ALL CHECKS PASSED‍"
    exit 0
else
    echo "BUILD VERIFICATION FAILED — $FAIL checks failed"
    exit 1
fi
