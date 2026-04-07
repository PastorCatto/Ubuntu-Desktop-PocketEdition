# Ubuntu Desktop PocketEdition
**Document Version 2.3 (Beryllium WiFi-Stable)**
> **Note:** This README and the latest hardware-enablement logic were co-developed with an **AI collaborator**. Together, we’ve untangled the complex Qualcomm DSP boot sequence to bring full, stable hardware support to the Poco F1.

---

Ubuntu Desktop PocketEdition is an advanced porting toolkit designed to deploy a functional, desktop-class **Ubuntu Noble (24.04)** environment onto the **Xiaomi Poco F1 (beryllium)** and related Snapdragon 845 (SDM845) devices. 

By merging a **postmarketOS (pmOS)** kernel foundation with a vanilla Ubuntu RootFS and a surgically injected Qualcomm service stack, this project turns a 2018 flagship into a pocket-sized Linux workstation.

---

## Technical Architecture: The Hybrid Transplant

This toolkit constructs a functional OS by merging three distinct layers:

1.  **Hardware Foundation:** Stable kernel (mainline-based) and Device Tree Blobs (DTB) from **postmarketOS v25.06**.
2.  **Operating System:** A vanilla **Ubuntu Noble (24.04)** ARM64 RootFS generated via `debootstrap`.
3.  **The "Bridge" (New!):** A custom-configured **QRTR + TFTP** stack that allows the Linux kernel and the Hexagon DSP to swap firmware binaries in real-time, bypassing the traditional Android proprietary limitations.

---

## Recent Breakthroughs (Phase 6: Wireless & DSP Stability)

The latest version includes critical fixes for the **WCN3990 WiFi** chip and **TrustZone memory management**:

* **Dual-Path Firmware Injection:** Solved the "Invalid Magic" error by serving the **Atheros kernel binary** to the Linux driver while simultaneously serving the **Qualcomm DSP payload** via a local TFTP bridge.
* **TFTP Server Automation:** Integrated `tqftpserv` natively into the build. The server is now pre-configured to handle the Poco F1's hardcoded Android firmware paths.
* **Bus-Clear Protocol:** Implemented a "Safety Sabotage" of the crashing Sensor DSP (SLPI) firmware. This prevents the Hexagon watchdog from locking up the SCM (Secure Channel Manager), ensuring WiFi can always request power from the regulators.
* **Zstd Purge:** Automatically strips `.zst` compressed firmware files that are known to cause silent initialization failures on the SDM845.



---

## Build Workflow

### 1. Pre-Flight
**`1_preflight.sh`**
Configures your build environment, installs host dependencies (`qemu-user-static`, `debootstrap`), and records your desired UI (Phosh, GNOME, KDE, etc.) into `build.env`.

### 2. Kernel & UUID Sync
**`2_pmos_setup.sh`**
Initializes `pmbootstrap` and extracts the kernel. Critically, it syncs the **UUIDs** between your Ubuntu images and the pmOS initramfs to ensure the phone doesn't get stuck in a bootloop searching for a missing partition.

### 3. The Harvest (Deprecated/Internal)
**`3_firmware_fetcher.sh`**
Now serves as a legacy script. Firmware is now handled natively via the pmOS harvest and internal downloader logic in Script 4.

### 4. The Transplant (Core Build)
**`4_the_transplant.sh`**
The heavy lifter. It builds the Ubuntu base and performs the **"Qualcomm Surgery"**:
* Downloads pristine `firmware-5.bin` from `kernel.org`.
* Stages `wlanmdsp.mbn` for the TFTP server.
* Installs and enables the `tqftpserv` daemon.
* Flattens the firmware directory structure to resolve pathing errors.

### 5. Verification (New!)
**`verify_chroot.sh`**
A diagnostic tool to run before you flash. It checks for:
* Presence of the 3.7MB WiFi payload.
* Correct Display Manager configuration (GDM3/SDDM/LightDM).
* ALSA UCM audio routing maps.
* Binary header integrity for the `ath10k` driver.

### 6. Finalization
**`6_seal_rootfs.sh`**
Allocates the final `.img` files, applies filesystem labels, and converts them into Android-compatible **Sparse Images** for fastboot.

---

## Deployment and Flashing

With the device in **Fastboot mode**, run:

```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_beryllium_boot.img
fastboot flash userdata ubuntu_beryllium_root.img
fastboot reboot
```

---

## Current Hardware Status (Beryllium)

| Feature | Status | Note |
| :--- | :--- | :--- |
| **CPU/GPU** | ✅ Working | Full hardware acceleration via Freedreno. |
| **Wi-Fi** | ✅ Stable | Fixed via TFTP + Pristine Kernel Firmware. |
| **Audio** | ✅ Working | Requires ALSA UCM2 maps (included). |
| **Touch/LCD** | ✅ Working | Native support. |
| **Cellular/LTE** | ⚠️ Testing | Modem initializes; requires `mcfg.tmp` injection. |
| **Sensors** | ❌ Disabled | SLPI disabled to ensure WiFi/TrustZone stability. |

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
**Ubuntu Desktop PocketEdition** — *The desktop in your pocket.*
