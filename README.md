# Mobuntu Orange
**Document Version 4.0 — RC9 "The Device Config Update"**

> **Note:** This project was co-developed with an AI collaborator (Claude, Anthropic). The build scripts are intentionally readable and modular for long-term maintainability.

---

Mobuntu Orange is a toolkit that builds a full Ubuntu ARM64 image for SDM845-based phones and other supported devices. The end goal is to support the full range of devices Mobian targets, running a real Ubuntu release with a touch-first Phosh interface.

No postmarketOS. No pmbootstrap. Everything is built from scratch inside a debootstrap chroot, then sealed and flashed via fastboot.

---

## Supported Devices

| Device | Codename | Firmware Method | Status |
| :--- | :--- | :--- | :--- |
| Xiaomi Poco F1 (Tianma) | beryllium | sdm845-mainline git repo | ✅ Primary target |
| Xiaomi Poco F1 (EBBG) | beryllium | sdm845-mainline git repo | ✅ Primary target |
| OnePlus 6 | enchilada | linux-firmware (apt) | 🧪 Untested |
| OnePlus 6T | fajita | linux-firmware (apt) | 🧪 Untested |

Adding a new device requires only a `devices/<brand>-<codename>.conf` file — no script changes needed.

---

## Hardware Status (Beryllium, RC9)

| Feature | Status | Notes |
| :--- | :--- | :--- |
| CPU | ✅ Working | Full performance, all cores |
| GPU / Display | ✅ Working | Freedreno hardware acceleration |
| Touch | ✅ Working | Native kernel support |
| Wi-Fi | ✅ Working | ath10k via firmware bundle |
| Bluetooth | ✅ Working | Confirmed on reference image |
| Audio | ⚠️ Partial | ACDB calibration data included in firmware bundle |
| Cellular / LTE | ⚠️ Testing | Modem firmware present, SIM PIN workaround needed |
| Sensors | 🧪 Partial | SLPI firmware included, iio-sensor-proxy required |
| Camera | ❌ Not working | Out of scope for now |
| NFC | ❌ No hardware | Not present on Poco F1 |

---

## Architecture

### The Build Pipeline

```
1_preflight.sh       — host deps, device selection, build.env config, optional auto-run
2_kernel_prep.sh     — fetch latest Mobian SDM845 kernel .deb from repo.mobian.org
3_rootfs_cooker.sh   — debootstrap, firmware staging, chroot build (phosh, services, hooks)
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

### Firmware Strategy

**Beryllium (Poco F1):**
Firmware is cloned from `gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium`, maintained by the same team behind the Mobian SDM845 kernel. This includes all signed device blobs (adsp, cdsp, mba, modem, venus, slpi, wlanmdsp), the ath10k WiFi board file, TAS2559 audio DSP, ACDB audio calibration data, and sensor configs. The repo mirrors the filesystem layout exactly and is copied directly into the rootfs.

If the git clone fails, the build falls back to OnePlus 6 blobs from the host `linux-firmware` apt package with a clear warning. These are structurally identical but not officially signed for beryllium — GPU, WiFi and BT should work, modem is not guaranteed.

**Adreno 630 GPU firmware** (`a630_sqe.fw`, `a630_gmu.bin`) is fetched separately from kernel.org as these are not device-signed and can be distributed freely.

**OnePlus 6 / 6T:** All required blobs ship in the upstream `linux-firmware` apt package, no additional steps needed.

### OTA Boot Updates

Starting RC8, `apt upgrade` automatically rebuilds `boot.img` after every kernel update via two hooks:

- `/etc/kernel/postinst.d/zz-qcom-bootimg` — fires after `apt install linux-image-*`
- `/etc/initramfs/post-update.d/bootimg` — fires after `update-initramfs`

The kernel cmdline (including the rootfs UUID) is stored in `/etc/kernel/cmdline`. The active DTB is stored in `/etc/kernel/boot_dtb`. Both are written during script 5 and read by the hook on every subsequent update. `qbootctl` is installed to allow slot updates without a PC.

---

## Build Workflow

### Prerequisites

- Ubuntu/Debian host (native or WSL2)
- ~20GB free disk space
- Internet access

### Quick Start

```bash
# Clone or copy the scripts and devices/ directory
chmod +x *.sh

# Run preflight — installs host deps, picks device, optionally auto-runs scripts 2 and 3
./1_preflight.sh

# If you chose manual mode:
./2_kernel_prep.sh    # fetch kernel
./3_rootfs_cooker.sh  # build rootfs (takes 20-40 min)

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

No first-boot firmware step is required. All firmware is pre-staged during the build.

---

## Adding a New Device

1. Create `devices/<brand>-<codename>.conf` using an existing config as a template
2. Set `FIRMWARE_METHOD`, `FIRMWARE_REPO`, `BOOT_DTB`, mkbootimg parameters, etc.
3. Run `1_preflight.sh` — your device will appear in the menu automatically

For U-Boot or UEFI devices, set `BOOT_METHOD="uboot"` or `BOOT_METHOD="uefi"` and fill in the placeholder URL fields. Full implementation for these boot methods is planned for a future RC.

---

## Troubleshooting

**No WiFi interface:**
Check `systemctl status tqftpserv` and `systemctl status rmtfs`. If either is failed, check that firmware blobs are present at `/lib/firmware/qcom/sdm845/beryllium/`.

**Random MAC address:**
Expected behaviour — the driver cannot read the encrypted `persist` partition and assigns a random MAC for privacy.

**Black screen on boot:**
Usually a DTB mismatch. Confirm your panel variant (Tianma vs EBBG) and use the correct device config. You can check your panel from TWRP terminal: `cat /sys/class/graphics/fb0/modes`.

**Kernel hook not firing after apt upgrade:**
Check `/etc/kernel/postinst.d/zz-qcom-bootimg` is executable and `/etc/kernel/cmdline` exists with a valid UUID.

---

## Community & Support

Discord: **PastorCatto's The ISLAND** — [https://discord.gg/RZV2HveyBg](https://discord.gg/RZV2HveyBg)

Special thanks to the Mobian and postmarketOS teams for SDM845 mainline kernel work, the sdm845-mainline group for the firmware repository, and samcday for Phrog.

---

*Mobuntu Orange — The orange looks nice on me, right?*
