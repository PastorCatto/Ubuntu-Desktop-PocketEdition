# Mobuntu Orange — Changelog (RC7-9 was assisted by Claude Sonnet 4.6 Extended)

# There was substantial progress made thanks to arkadin91 and his Ubuntu 26.04 Beta release image (and pointing me at Kupfer and SDM845-mainline for firmware!)
# OTA script logic was provided by arkadin91

## RC9 (Current session)
**Device Config System**
- Introduced `devices/*.conf` device profile system — all scripts now source a device config via `build.env`
- Added device configs: `xiaomi-beryllium-tianma`, `xiaomi-beryllium-ebbg`, `oneplus-enchilada`, `oneplus-fajita`
- Device configs carry all mkbootimg parameters, firmware method, kernel method, services, quirks, hostname, image label

**Firmware**
- Replaced droid-juicer with direct `git clone` of `gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium`
- Full firmware bundle confirmed: all beryllium signed blobs + ath10k WiFi board file + TAS2559 audio amp + ACDB audio calibration + DSP userspace libs + sensor configs
- Added OnePlus 6 fallback: if git clone fails, copies `sdm845/oneplus6/` blobs from host `linux-firmware` into `sdm845/beryllium/` with a clear warning naming the source directory
- OnePlus 6/6T use `apt` firmware method (blobs ship in upstream `linux-firmware`)

**Boot method abstraction**
- Script 5 branches on `BOOT_METHOD`: `mkbootimg` (fully implemented), `uboot` (placeholder), `uefi` (placeholder)
- `BOOT_DTB_APPEND`, `BOOT_PANEL_PICKER`, all mkbootimg offsets driven from device config

**Script 1 auto-run**
- After saving `build.env`, script 1 optionally chains directly into scripts 2 and 3

**Script renumbering**
- Finalised 5-script pipeline: old `4,5,6` → new `3,4,5`

---

## RC8
**Phrog / greetd** (REMOVED TEMPORARILY)
- Replaced GDM3 with `greetd` + `phrog` — login screen is native Phosh lockscreen, touch-friendly
- No more broken GNOME UI state on first boot
- Confirmed Phrog is the official greeter for Mobian/beryllium (FOSDEM 2025 demo was a Poco F1)
- `greeter` user created, `/etc/greetd/config.toml` written pointing to phrog

**Kernel hook (OTA-safe boot.img)**
- Installed `/etc/kernel/postinst.d/zz-qcom-bootimg` — rebuilds `boot.img` automatically after every `apt upgrade` that updates the kernel
- Installed `/etc/initramfs/post-update.d/bootimg` — same trigger after `update-initramfs`
- `/etc/kernel/cmdline` written by script 5 with real UUID so hook works correctly
- `/etc/kernel/boot_dtb` written by script 5 so hook picks the correct panel DTB
- Hook filters on `*sdm845*` kernel version to avoid accidentally using the generic Ubuntu kernel

**qbootctl**
- Installed in rootfs — enables OTA-style slot updates without fastboot after first flash

**Firmware investigation (reference image)**
- Reverse-engineered a working Ubuntu 26.04 ARM64 beryllium image (pre-first-boot)
- Confirmed GPU, WiFi, BT worked before droid-juicer ran
- Discovered `sdm845/beryllium/` blobs were manually staged — not tracked by dpkg
- Confirmed `sdm845/a630_zap.mbn` ships in `linux-firmware` apt; beryllium-specific signed blobs do not
- Confirmed OnePlus 6 firmware file list is identical to beryllium (different binaries, device-signed)

**fstab**
- Added `/boot/efi vfat` stub entry — empty FAT32 partition, required by Ubuntu desktop metapackage

---

## RC7 (Session start)
**Build system**
- 7-script pipeline inherited; deprecated scripts identified and removed; renumbering planned
- `build.env` used to pass config between scripts
- osm0sis mkbootimg fork confirmed required (Ubuntu package broken — GKI module error)
- `sed -i 's/-Werror//g'` fix applied to libmincrypt Makefile

**Kernel**
- Dynamic fetch from `repo.mobian.org` pool for latest `linux-image-*-sdm845` and headers
- DTB confirmed appended to kernel binary (not `--dtb` flag) — required for SDM845 bootloader
- DTB filenames confirmed: `sdm845-xiaomi-beryllium-tianma.dtb` / `-ebbg.dtb`

**RootFS**
- debootstrap two-stage build with QEMU arm64 binfmt
- WSL2 binfmt injection fallback
- Nested heredoc bug fixed — chroot script written to mktemp file
- `apt-get: command not found` bug fixed — explicit second stage + PATH
- `mke2fs -d` broken — replaced with `fallocate` + `mkfs.ext4` + loop mount + `rsync -aHAXx`

**Firmware (original strategy)**
- `a630_sqe.fw`, `a630_gmu.bin` from `linux-firmware` apt
- `a630_zap.mbn` curled from kernel.org
- adsp/cdsp/mba/modem/venus/wlan via droid-juicer on first boot
- Mobian repo added for droid-juicer, qrtr-tools, rmtfs, tqftpserv, pd-mapper

**Bugs fixed during RC7**
- `return 1` inside fetch functions killed script with `set -e` — fixed with explicit `return 0`
- `basename: missing operand` — fixed with `for f in /boot/vmlinuz-*sdm845*` loop
- binfmt not active on WSL2 — added manual hex registration fallback
- `Exec format error` in chroot — fixed with `qemu-aarch64-static` explicit invocation
