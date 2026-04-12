# Mobuntu Orange
**Document Version 4.1 — RC10.1 "The UI & Firmware Archive Update"**

> **Note:** This project was co-developed with an AI collaborator (Claude, Anthropic), and arkadin91 (as of RC7). The build scripts are intentionally readable and modular for long-term maintainability.

---

Mobuntu Orange is a toolkit that builds a full Ubuntu ARM64 image for SDM845-based phones and other supported devices. The end goal is to support the full range of devices Mobian targets, running a real Ubuntu release with a touch-first mobile interface.

No postmarketOS. No pmbootstrap. Everything is built from scratch inside a debootstrap chroot, then sealed and flashed via fastboot.

---

## Supported Devices

| Device | Codename | Firmware Method | Status |
| :--- | :--- | :--- | :--- |
| Xiaomi Poco F1 (Tianma) | beryllium | Local archive → git repo → OnePlus fallback | ✅ Confirmed working |
| Xiaomi Poco F1 (EBBG) | beryllium | Local archive → git repo → OnePlus fallback | ✅ Confirmed working |
| OnePlus 6 | enchilada | linux-firmware (apt) | 🧪 Untested |
| OnePlus 6T | fajita | linux-firmware (apt) | 🧪 Untested |

Adding a new device requires only a `devices/<brand>-<codename>.conf` file — no script changes needed.

---

## Hardware Status (Beryllium, RC10.1)

| Feature | Status | Notes |
| :--- | :--- | :--- |
| CPU | ✅ Working | Full performance, all cores |
| GPU / Display | ✅ Working | Freedreno hardware acceleration |
| Touch | ✅ Working | Native kernel support |
| Wi-Fi | ✅ Confirmed | ath10k, tested on device |
| Bluetooth | ✅ Working | Confirmed on reference image |
| Audio | ⚠️ Partial | ACDB calibration data included, may need UCM maps |
| Cellular / LTE | ⚠️ Testing | Modem firmware present, SIM PIN workaround needed |
| Sensors | 🧪 Partial | SLPI firmware included, iio-sensor-proxy required |
| Camera | ❌ Not working | Out of scope for now |
| NFC | ❌ No hardware | Not present on Poco F1 |

---

## Architecture

### The Build Pipeline

```
1_preflight.sh       — host deps, device selection, UI picker, release picker, build.env, optional auto-run
2_kernel_prep.sh     — fetch latest Mobian SDM845 kernel .deb from repo.mobian.org
3_rootfs_cooker.sh   — debootstrap, firmware staging, chroot build (UI, services, kernel hooks)
4_enter_chroot.sh    — debug utility, drops you into the rootfs interactively
5_seal_rootfs.sh     — UUID, cmdline, fstab, boot.img, rootfs image, sparse convert
```

### Device Config System

Every device-specific setting lives in `devices/<brand>-<codename>.conf`:

- Kernel method and repo
- Boot method (`mkbootimg` / `uboot` / `uefi`) and all parameters
- Firmware method (`git` / `apt` / `droid-juicer`) and repo URL
- DTB filename, panel picker toggle, DTB-append quirk
- Device-specific apt packages and systemd services
- Hostname and image label

Script 1 presents a menu of available device configs. Everything flows into `build.env` and all subsequent scripts read from there.

### UI Picker

Script 1 now prompts for your preferred desktop environment:

| Option | UI | Display Manager | Notes |
| :--- | :--- | :--- | :--- |
| 1 | Phosh [x] | greetd + phrog | Default, recommended for phones |
| 2 | Ubuntu Desktop Minimal | GDM3 | Touch-friendly GNOME |
| 3 | Unity | LightDM | |
| 4 | Plasma Desktop | SDDM | Better for tablets |
| 5 | Plasma Mobile | SDDM | Touch-first KDE |
| 6 | Lomiri | greetd | Ubuntu Touch shell — experimental, warning shown |
* [x]There seems to be an issue with phrog, where it just doesnt load. please use any other option (except lomiri)
  
### Firmware Strategy

Firmware is staged in three priority tiers:

**Priority 1 — Local archive (fastest, most reliable):**
Place a `firmware.tar.gz` in `firmware/<brand>-<codename>/` before building. Script 3 will extract it directly into the rootfs. This is the recommended approach for confirmed-working firmware.

To create an archive from a known-good image mounted at `/mnt/loop0p2`:
```bash
cd /mnt/loop0p2
sudo tar -czf firmware.tar.gz lib/firmware/qcom/sdm845/beryllium
mv firmware.tar.gz /path/to/mobuntu/firmware/xiaomi-beryllium/
```

**Priority 2 — Git clone:**
If no local archive is found, firmware is cloned from `gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium`. Maintained by the same team as the Mobian SDM845 kernel.

**Priority 3 — OnePlus 6 fallback:**
If the git clone also fails, core blobs are copied from the host's `linux-firmware` apt package (`sdm845/oneplus6/`) into the beryllium firmware path, with a clear warning. GPU, WiFi and BT should work; modem is not guaranteed.

**Adreno 630 GPU firmware** (`a630_sqe.fw`, `a630_gmu.bin`) is always fetched from kernel.org separately — these are not device-signed and can be distributed freely.

**OnePlus 6 / 6T:** All required blobs ship in the upstream `linux-firmware` apt package.

### OTA Boot Updates

`apt upgrade` automatically rebuilds `boot.img` after every kernel update via two hooks:

- `/etc/kernel/postinst.d/zz-qcom-bootimg` — fires after `apt install linux-image-*`
- `/etc/initramfs/post-update.d/bootimg` — fires after `update-initramfs`

The rootfs UUID is stored in `/etc/kernel/cmdline` and the active DTB in `/etc/kernel/boot_dtb`. Both are written during script 5. `qbootctl` is installed for slot updates without a PC.

---

## Supported Ubuntu Releases

| Release | Codename | Status |
| :--- | :--- | :--- |
| 24.04 LTS | noble | ✅ Recommended |
| 24.10 | oracular | ✅ Supported |
| 25.04 | plucky | ✅ Supported |
| 26.04 dev | devel | ⚠️ Experimental — warning shown at build time |
| 26.04 LTS | quill | 🔒 Disabled until release |

---

## Build Workflow

### Prerequisites

- Ubuntu/Debian x86-64 host (native or WSL2) — arm64 host support planned for RC11
- ~20GB free disk space
- Internet access

### Quick Start

```bash
# Make scripts executable
chmod +x *.sh

# Run preflight — installs host deps, picks device, UI, release, optionally auto-runs 2 and 3
./1_preflight.sh

# If you chose manual mode:
./2_kernel_prep.sh    # fetch kernel
./3_rootfs_cooker.sh  # build rootfs (20-40 min)

# Seal and generate flash images
./5_seal_rootfs.sh

# Optional: drop into the rootfs for debugging
./4_enter_chroot.sh
```

### Flashing

Boot your device into fastboot mode (Power + Volume Down), then:

```bash
fastboot flash boot   mobuntu_beryllium_<release>_boot.img
fastboot flash system mobuntu_beryllium_<release>_root_sparse.img
fastboot reboot
```

> **Do not unplug during reboot** — the device is writing to NAND from RAM.

No first-boot firmware step required when using a local firmware archive.

---

## Adding a New Device

1. Create `devices/<brand>-<codename>.conf` using an existing config as a template
2. Set `FIRMWARE_METHOD`, `FIRMWARE_REPO`, `BOOT_DTB`, mkbootimg parameters, etc.
3. Optionally place a `firmware.tar.gz` in `firmware/<brand>-<codename>/`
4. Run `1_preflight.sh` — your device will appear in the menu automatically

For U-Boot or UEFI devices, set `BOOT_METHOD="uboot"` or `BOOT_METHOD="uefi"` and fill in the placeholder URL fields. Full implementation planned for a future RC.

---

## Troubleshooting

**Emergency mode on boot:**
Run `systemctl --failed` and `cat /etc/fstab`. If `/boot/efi` appears in fstab, remove it: `sudo sed -i '/boot\/efi/d' /etc/fstab`.

**qcom_scm -22 error:**
SCM is rejecting a firmware blob — usually `a630_zap.mbn`. Confirm the blob is present at `/lib/firmware/qcom/sdm845/beryllium/a630_zap.mbn`. If using the git repo, try switching to a local firmware archive harvested from a known-good image.

**No WiFi interface:**
Check `systemctl status tqftpserv` and `systemctl status rmtfs`. Confirm firmware blobs are present at `/lib/firmware/qcom/sdm845/beryllium/`.

**Random MAC address:**
Expected — the driver cannot read the encrypted `persist` partition and assigns a random MAC for privacy.

**Black screen on boot:**
Usually a DTB mismatch. Confirm your panel variant (Tianma vs EBBG) and use the correct device config. Check from TWRP terminal: `cat /sys/class/graphics/fb0/modes`.

**Kernel hook not firing after apt upgrade:**
Check `/etc/kernel/postinst.d/zz-qcom-bootimg` is executable and `/etc/kernel/cmdline` exists with a valid UUID.

---

## Planned (RC11)

- ARM64 host support (skip QEMU, use direct chroot)
- Watchdog script for build monitoring
- U-Boot and UEFI boot method implementation
- Ubuntu 26.04 quill stable when released

---

## Community & Support

Discord: **PastorCatto's The ISLAND** — [https://discord.gg/RZV2HveyBg](https://discord.gg/RZV2HveyBg)

Special thanks to the Mobian and postmarketOS teams for SDM845 mainline kernel work, the sdm845-mainline group for the firmware repository, samcday for Phrog, and arkadin91 for the reference image and firmware discoveries that made Pre-Release 1.0 possible.

---

*Mobuntu Orange — The orange looks nice on me, right?*
