# Mobuntu Release Roadmap

> **Rough draft — subject to change at any time.**
> Priorities shift based on hardware availability, upstream kernel changes, community feedback, and contributor bandwidth.
> Nothing here is a promise.

---

## RC15 — "The Debos Update" *(current)*

**Focus:** Stabilise the debos pipeline, fix repo layering, ship the first resolute build.

- [x] Pure debootstrap → debos pipeline (no pmbootstrap)
- [x] Ubuntu 26.04 (resolute) support
- [x] Base/device recipe split — Ubuntu packages resolved before Mobian repo added
- [x] Beryllium (Poco F1 Tianma + EBBG) building and booting
- [x] Watchdog + ZWJ clean-exit signal
- [x] fastrpc arm64 cross-build pipeline
- [x] DSP binary bundle from MIUI 12 dsp.img
- [x] install-fastrpc-device.sh staged into qcom.yaml
- [x] OTA kernel/initramfs hooks (zz-qcom-bootimg, bootimg)
- [x] WirePlumber S16LE/48kHz overlay
- [x] ALSA state service masking
- [x] Qualcomm service ordering drop-ins
- [x] Comprehensive RC15 documentation
- [ ] First confirmed boot on beryllium hardware *(in progress)*
- [ ] OnePlus 6/6T (enchilada/fajita) first boot test

---

## RC16 — "Hardware Shake" *(next)*

**Focus:** Fix everything the first real boots expose. Stability over features.

**Beryllium**
- [ ] Confirm audio working end-to-end (UCM profiles, PipeWire, WirePlumber)
- [ ] Confirm WiFi/BT functional without modem interference
- [ ] Confirm OTA hook rebuilds boot.img correctly after kernel upgrade
- [ ] Update KERNEL_VERSION_PIN to latest 6.18-sdm845 once build is confirmed stable

**fastrpc / DSP**
- [ ] Wire install-fastrpc-device.sh properly into qcom.yaml (currently staged but not confirmed working in a booted image)
- [ ] Confirm adsprpcd/cdsprpcd start cleanly on boot
- [ ] Investigate sdsprpcd / SLPI crash loop — determine if DSP bundle resolves it or if additional work needed

**Build pipeline**
- [ ] Fix script numbering gap (2_kernel_prep / 3_rootfs_cooker retired — renumber or document)
- [ ] Add `none` backend cleanup trap (unmount bind mounts on failure)
- [ ] Improve verify_build.sh firmware checks to account for new dsp.tar.gz layout
- [ ] Update MOBUNTU-DOCS.md to reflect RC16 changes

**OnePlus 6/6T**
- [ ] First build attempt (enchilada/fajita)
- [ ] Confirm WirePlumber overlay differences vs beryllium
- [ ] Report hardware status

---

## RC17 — "Sensor Sprint"

**Focus:** SLPI sensors, fastrpc full stack, quality of life.

**SLPI / Sensors**
- [ ] Investigate CHRE daemon integration for sensor support via sdsp fastrpc shell
- [ ] Determine if hexagon-dsp-binaries (Debian unstable) ships beryllium-compatible blobs
- [ ] Contribute beryllium DSP binaries to hexagon-dsp-binaries upstream if licensing permits
- [ ] sdsprpcd service enablement once SLPI is stable

**Chroot Edition (prototype)**
- [ ] Proof-of-concept: Mobuntu base tarball running via chroot-distro on a rooted Android device
- [ ] Document as an unofficial accessibility path for unsupported devices
- [ ] Evaluate demand before committing to standalone APK

**General**
- [ ] Phosh UI polish pass — greetd config, default apps, mobile-friendly defaults
- [ ] SSH key provisioning option in preflight (instead of password-only)
- [ ] First-boot resize service testing and confirmation

---

## 1.0 — "Stable Base"

**Focus:** The first release we're comfortable pointing non-technical users at. Poco F1 and Nintendo Switch ship as the two supported platforms.

**Requirements for 1.0:**
- [ ] Poco F1 (both panels): CPU/GPU/WiFi/BT/Audio/Touch confirmed working, stable across reboots
- [ ] OTA kernel upgrade tested end-to-end (apt upgrade → boot.img rebuilds → reboots successfully)
- [ ] Nintendo Switch: kernel repo populated, L4T build pipeline confirmed working, Hekate flash documented
- [ ] verify_build.sh passes clean on both device builds
- [ ] One-page user install guide (flash + first boot)
- [ ] GitHub Releases with pre-built images for both devices
- [ ] CHANGELOG.md covering RC15 → 1.0

**Explicitly out of scope for 1.0:**
- Cellular / modem support
- Camera
- SLPI sensors (nice to have, not blocking)
- Any device beyond Poco F1 and Switch

---

## Post-1.0 Backlog *(unscheduled)*

These are confirmed ideas, no timeline attached.

**Chroot Edition app**
- Standalone APK wrapping chroot-distro engine + Mobuntu base tarball
- Target: any rooted Android device regardless of SoC
- Provides Mobuntu as an accessibility/compatibility layer for devices that will never get a native port (Samsung Exynos, MediaTek, etc.)
- Level 1: chroot-distro JSON descriptor (low effort, enables manual install)
- Level 2: Standalone APK with launcher UI (significant effort, post-demand-validation)

**New native devices**
- Devices accepted based on: mainline kernel DTS upstream, fastboot-compatible bootloader, contributor willing to test
- Samsung Galaxy A21s (SM-A217F / Exynos 850): researched — blocked on no upstream A21s DTS, S-LK bootloader requires uniLoader shim, no fastboot. Revisit if upstream DTS lands.

**kernel_method="ubuntu_generic" (Linux 7.0)**
- Test Ubuntu 7.0 generic kernel on beryllium — removes Mobian dependency entirely
- Requires firmware path update (`qcom/sdm845/Xiaomi/beryllium/` — already in mainline DTS as of December 2025 patches)

**Switch L4T pipeline**
- Populate KERNEL_REPO for all four Switch variants (V1/V2/Lite/OLED)
- Verify DTB filenames
- Test Hekate UMS flash workflow

**modem investigation**
- Determine exact condition that causes WiFi+BT crash when ModemManager is active
- Long-term goal: safe cellular support on beryllium

---

*Last updated: April 2026 — RC15 development cycle*
*Discord: https://discord.gg/RZV2HveyBg*
