# Mobuntu Orange
**Document Version 3.0a (The Droid-Juicer Update)**

> **Note:** This README and the latest hardware-enablement logic were co-developed with an **AI collaborator**. Together, we’ve untangled the complex Qualcomm DSP boot sequence to bring full, stable hardware support to the Poco F1. This Entire 
> project has been possible with Gemini Pro, as it has generated ALL the bash scripts we use to build this image. Everything is readable for a reason, and this whole setup is modular, so should be easy to maintian for longevity

---

Mobuntu Orange is a series of scripts designed to build a Ubuntu Based image for SDM845 and other supported devices, end goal is to support the whole stack of devices Mobian supports with a Ubuntu release!

With recent updates, we no longer depend on postmarketOS, and instead do everything inside the Chroot, and afterwards, pull the kernel and any required files and build the image on the Host.

---

## Technical Architecture: The Hybrid Transplant

This toolkit constructs a functional OS by doing a series of the following

1.  **Ubuntu Rootfs:** so we need to build the OS, we do that using debootstrap, so we are able to pick and choose any avalible version and generate a chroot.
2.  **Firmware Enablement Stack:** With RC7 of our build stack, we now utilize Droid-Juicer and fwload, only quirk seems to be rotation (very much testing as of writing)
3.  **The Boot Stack (New!):** Previously i used to rely on pmbootstrap, but refering to issue#1, there was a better way, so now when the rootfs is made, we pull the kernel and everything, and pack it outside the chroot, so its easy to update the kernel, just install a newer version and remove the old one!
4.  Starting with RC9 (planned) we intend to also implement an OTA Boot Updater, where the OS auto-flashes the new boot.img to the /boot partition, eliminating the need to flash a new Boot.img manually after updates! (thanks to arkadin91 for the OTA Script for initramfs)

---

## Recent Breakthroughs (Phase 7: the Independant update!)

The latest version introduces Droid-juicer, which should bypass the need to harvest the rest of the firmware:

* **Dual-Path Firmware Injection:** We use Droid-Juicer for a majority of the heavy lifting, but the GPU blobs still need to be aquired, hence 2 types of injections
* **Multi-Device Builder:** with the introduction of RC7, we now have added initial support for both POCO F1 and now Oneplus 6/T and Xiaomi Mi 8 (UNTESTED!)
* **Ubuntu Version Selector:** RC7 introduces the ability to choose a version of Ubuntu based on a query of availible repos for supported versions (as low as Trusty Tahr 14.04! 24.04 is the lowest SUPPORTED BY US!, anything lower is at YOUR OWN RISK!)

# RC8 Does not contain the distro version selector, instead you get to pick between 24.04 -> 25.10 (will bring back in RC9)



---

## Build Workflow

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
```

---

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
* The newest build no longer suffers the display 
---

## Troubleshooting

* **No WiFi Interface:** Check if the TFTP server is running: `systemctl status tqftpserv`. If it says "stat failed," re-run the verification script.
* **Invalid MAC Address:** This is expected. The driver chooses a random MAC address for privacy since it cannot read the encrypted `persist` partition.
* **Black Screen on Boot:** Ensure you selected a Display Manager in `1_preflight.sh`. If in doubt, check `/etc/X11/default-display-manager` via Script 5.

---

## Community & Support

For real-time development updates and support, join the Discord:
**PastorCatto's The ISLAND:** [https://discord.gg/RZV2HveyBg](https://discord.gg/RZV2HveyBg)

*Special thanks to the postmarketOS and Mobian teams for providing the groundwork for SDM845 mainline support.*

---
**Mobuntu Orange** — *The orange looks nice on me, right?*
