# Mobuntu Orange
<<<<<<< HEAD
**Document Version 4.0 — RC9 "The Device Config Update"**

> **Note:** This project was co-developed with an AI collaborator (Claude, Anthropic). The build scripts are intentionally readable and modular for long-term maintainability.

---

Mobuntu Orange is a toolkit that builds a full Ubuntu ARM64 image for SDM845-based phones and other supported devices. The end goal is to support the full range of devices Mobian targets, running a real Ubuntu release with a touch-first Phosh interface.

No postmarketOS. No pmbootstrap. Everything is built from scratch inside a debootstrap chroot, then sealed and flashed via fastboot.
=======
**Document Version 3.0a (The Droid-Juicer Update)**

> **Note:** This README and the latest hardware-enablement logic were co-developed with an **AI collaborator**. Together, we’ve untangled the complex Qualcomm DSP boot sequence to bring full, stable hardware support to the Poco F1. This Entire 
> project has been possible with Gemini Pro, as it has generated ALL the bash scripts we use to build this image. Everything is readable for a reason, and this whole setup is modular, so should be easy to maintian for longevity

---

Mobuntu Orange is a series of scripts designed to build a Ubuntu Based image for SDM845 and other supported devices, end goal is to support the whole stack of devices Mobian supports with a Ubuntu release!

With recent updates, we no longer depend on postmarketOS, and instead do everything inside the Chroot, and afterwards, pull the kernel and any required files and build the image on the Host.
>>>>>>> origin/main

---

## Supported Devices

<<<<<<< HEAD
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
=======
This toolkit constructs a functional OS by doing a series of the following

1.  **Ubuntu Rootfs:** so we need to build the OS, we do that using debootstrap, so we are able to pick and choose any avalible version and generate a chroot.
2.  **Firmware Enablement Stack:** With RC7 of our build stack, we now utilize Droid-Juicer and fwload, only quirk seems to be rotation (very much testing as of writing)
3.  **The Boot Stack (New!):** Previously i used to rely on pmbootstrap, but refering to issue#1, there was a better way, so now when the rootfs is made, we pull the kernel and everything, and pack it outside the chroot, so its easy to update the kernel, just install a newer version and remove the old one!
4.  Starting with RC8, we have implemented an OTA Boot Updater, where the OS auto-flashes the new boot.img to the /boot partition, eliminating the need to flash a new Boot.img manually after updates! (thanks to arkadin91 for the OTA Script for initramfs)

---

## Recent Breakthroughs (Phase 7: the Independant update!)

The latest version introduces Droid-juicer, which should bypass the need to harvest the rest of the firmware:

* **Dual-Path Firmware Injection:** We use Droid-Juicer for a majority of the heavy lifting, but the GPU blobs still need to be aquired, hence 2 types of injections
* **Multi-Device Builder:** with the introduction of RC7, we now have added initial support for both POCO F1 and now Oneplus 6/T and Xiaomi Mi 8 (UNTESTED!)
* **Ubuntu Version Selector:** RC7 introduces the ability to choose a version of Ubuntu based on a query of availible repos for supported versions (as low as Trusty Tahr 14.04! 24.10 is the lowest SUPPORTED BY US!, anything lower is at YOUR OWN RISK!)

# RC8 Does not contain the distro version selector, instead you get to pick between 24.04 -> 25.10 (will bring back in RC9)
>>>>>>> origin/main

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

<<<<<<< HEAD
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
=======
### 1. Pre-Flight
**`1_preflight.sh`**
Configures your build environment, installs host dependencies (`qemu-user-static`, `debootstrap`), and records your desired UI (Phosh, GNOME, KDE, etc.) into `build.env`. (With RC7+ builds, we also now store Ubuntu Versions as well!)

### 2. Kernel & UUID Sync
**`2_Kernel_Setup.sh`**
Due to the recent Deprecation of pmbootstrap, we now pull a kernel and image files directly from kernel.org, this download the required debs for the latest LTS kernel and injects them into /tmp for install inside the chroot after generation (gets picked up by Cooker script #4)

### 3. The Harvest (Deprecated/Internal)
**`3_firmware_fetcher.sh`**
Now serves as a legacy script. Firmware is now handled natively via the Kernel.org repo (formerly pmOS harvest) and internal downloader logic in Script 4.

### 4. The Transplant (Core Build)
**`4_Rootfs_cooker.sh`**
The heavy lifter. It builds the Ubuntu base and performs the **"Qualcomm Surgery"**:
* Builds the basic Chroot (debootstrap)
* apt Updates and installs the UI chosen by injected script thats run inside the chroot
* Flattens the firmware directory structure to resolve pathing errors.

### 5. Verification (OUTDATED, WILL RETURN)
**`verify_chroot.sh`** DEPRECATED FOR NOW!
A diagnostic tool to run before you flash. It checks for:
* Presence of the 3.7MB WiFi payload.
* Correct Display Manager configuration (GDM3/SDDM/LightDM).
* ALSA UCM audio routing maps.
* Binary header integrity for the `ath10k` driver.

### 6. Finalization
**`6_seal_rootfs.sh`**
Allocates the final `.img` files, applies filesystem labels, and converts them into Android-compatible **Sparse Images** for fastboot.
also generates the Boot.img and generated a UUID on the fly

---

## Deployment and Flashing

With the device in **Fastboot mode**, run:

```bash
fastboot flash boot Mobuntu_orange_boot

(DEPRECATED! WOO!)fastboot flash system ubuntu_beryllium_boot.img

fastboot flash userdata Mobuntu_orange_rootfs.img

fastboot reboot (DO NOT UNPLUG UNTIL IT REBOOTS! ITS ACTIVELY WRITING TO NAND FROM RAM!)
>>>>>>> origin/main
```

> **Do not unplug during reboot** — the device is writing to NAND from RAM.

No first-boot firmware step is required. All firmware is pre-staged during the build.

---

<<<<<<< HEAD
## Adding a New Device

1. Create `devices/<brand>-<codename>.conf` using an existing config as a template
2. Set `FIRMWARE_METHOD`, `FIRMWARE_REPO`, `BOOT_DTB`, mkbootimg parameters, etc.
3. Run `1_preflight.sh` — your device will appear in the menu automatically

For U-Boot or UEFI devices, set `BOOT_METHOD="uboot"` or `BOOT_METHOD="uefi"` and fill in the placeholder URL fields. Full implementation for these boot methods is planned for a future RC.

=======
## RC4 Hardware Status (Beryllium)

| Feature | Status | Note |
| :--- | :--- | :--- |
| **CPU/GPU** | ✅ Working* | Full hardware acceleration via Freedreno. |
| **Wi-Fi** | ✅ Stable | Fixed via TFTP + Pristine Kernel Firmware. |
| **Audio** | ❌ DEAD | Requires ALSA UCM2 maps (included). |
| **Touch/LCD** | ✅ Working | Native support. |
| **Cellular/LTE** | ⚠️ Testing | Modem initializes; requires `mcfg.tmp` injection. |
| **Sensors** | ❌ Disabled | SLPI disabled to ensure WiFi/TrustZone stability. |
* Possible bugs with the pmOS kernel, as its having bugs (similar behaviour to stock postmarketOS v25.06)
kernel 6.14-RC5 is what i currently use, will build against newer kernel! (can be done using edge or v25.12 version of pmOS)
* Recent builds against the EDGE channel of postmarketOS results in a Kernel Race Condition where the display doesnt fully Initialize in time (present on Kernel 6.16.7) Roughly 30-60% of the time its a Bad init
* The newest build no longer suffers the display bug, as we moved away from postmarketOS for our kernel
>>>>>>> origin/main
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
<<<<<<< HEAD

*Mobuntu Orange — The orange looks nice on me, right?*
=======
**Mobuntu Orange** — *The orange looks nice on me, right?*
>>>>>>> origin/main
