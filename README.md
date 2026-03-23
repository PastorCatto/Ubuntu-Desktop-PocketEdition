# Ubuntu Desktop PocketEdition
# Document Version 2.1a
# Note: the Devices/Xiaomi_beryllium folder is where i do most of my work (Updated first)
# hence if you want BLEEDING EDGE (STRONGLY ADVISE AGAINST) go there for the absolute LATEST scripts
# DeveloperStarterKits are Built against the EDGE versions (pass testing with no bugs, and excluding ALPHA SDM845 scripts) 
Ubuntu Desktop PocketEdition is an advanced porting toolkit designed to deploy a functional, desktop-class Ubuntu Noble (24.04) environment onto the Xiaomi Poco F1 (beryllium) and related Snapdragon 845 (SDM845) devices. 

The project bridges the gap between mobile hardware and a standard Linux desktop by utilizing a unique "Hybrid Transplant" methodology. It leverages the hardware-enablement foundation of postmarketOS (pmOS), the stability of a vanilla Ubuntu RootFS, and verified vendor firmware from the LineageOS ecosystem.

---

## Technical Architecture: The Hybrid Transplant

This toolkit constructs a functional OS by merging three distinct layers:

1.  **Hardware Foundation:** A stable kernel, kernel modules, and Device Tree Blobs (DTB) sourced from the postmarketOS (pmOS) v25.06 (stable) branch.
2.  **Operating System:** A vanilla Ubuntu Noble (24.04) ARM64 RootFS generated via debootstrap.
3.  **Hardware Mapping & Firmware:** A modern Qualcomm service stack (QRTR, RMTFS, PD-Mapper, TQFTPServ) combined with verified, signed firmware blobs sourced from the LineageOS/TheMuppets repositories to ensure TrustZone authentication success.

---

## The LineageOS Firmware Experiment

The latest iteration of this toolkit moves away from harvesting firmware from live donor devices. Instead, it pulls cryptographically signed vendor blobs directly from verified community repositories. This shift addresses common "QCOM_SCM -22" errors and TrustZone rejections by ensuring the firmware version matches the device's late-stage bootloader (MIUI 11/12/Android 10).

---

## Prerequisites

### Host System
* **OS:** Ubuntu 22.04 LTS or newer (x86_64).
* **Storage:** 40GB+ of free space.
* **Privileges:** Sudo access is required for filesystem operations and chroot management.

### Target Hardware
* **Device:** Xiaomi Poco F1 (beryllium) with an unlocked bootloader.
* **Firmware:** The device should ideally be updated to the latest available MIUI global firmware (Android 10 base) before flashing.

---

## Build Workflow

The toolkit is modular. To initialize the workspace and generate the build scripts, run:
```bash
bash deploy_workspace.sh
```

### 1. Initial Configuration
**1_preflight.sh**
Sets up host dependencies and records your build configuration (username, password, preferred UI, and image sizing) into `build.env`.

### 2. Kernel Foundation
**2_pmos_setup.sh**
Initializes `pmbootstrap`. This script patches the kernel command line for UFS storage compatibility and synchronizes partition UUIDs to ensure the Ubuntu RootFS is correctly identified by the pmOS initramfs.

### 3. Firmware Acquisition
**3_firmware_fetcher.sh**
(Optional/Legacy) Provides a mechanism to harvest proprietary blobs from a donor device running Mobian via SSH. 
*Note: For SDM845 devices, it is recommended to use the new Script 9 for firmware management.*

### 4. The Transplant
**4_the_transplant.sh**
The core OS build script. It generates the Ubuntu Noble base via debootstrap and integrates the kernel from Stage 2. It then enters a chroot to install the selected user interface (Phosh, Plasma Mobile, GNOME, etc.).

### 5. Maintenance Mode
**5_enter_chroot.sh**
A utility script to safely enter the Ubuntu environment for manual configuration, software installation, or debugging.

### 6. Image Finalization
**6_seal_rootfs.sh**
Allocates the final system images, applies filesystem labels, and converts raw images into Android-compatible sparse images (.img) ready for fastboot.

### 7. Kernel Customization
**7_kernel_menuconfig.sh**
Allows for manual kernel driver adjustments via the standard Linux menuconfig interface.

### 8. Hardware Enablement (The Master Fix)
**Qualcomm_Compiler.sh**
The primary enablement script for SDM845 hardware. It automates the following in a protected environment:
* **Audio:** Installs ALSA UCM profiles from the sdm845-mainline project for speaker and microphone routing.
* **Firmware:** Downloads and deploys verified LineageOS blobs to `/lib/firmware`.
* **Services:** Compiles and enables the Qualcomm stack (QRTR, RMTFS, PD-Mapper, TQFTPServ) to initialize WiFi, Bluetooth, and the Modem.

---

## Deployment and Flashing

Once the images are sealed (Script 6), place the device in Fastboot mode and execute:

```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_beryllium_boot_sparse.img
fastboot flash userdata ubuntu_beryllium_root_sparse.img
fastboot reboot
```

---

## Troubleshooting

* **Wait on RootFS:** Ensure UUIDs in `build.env` match the final images; if mismatching, the initramfs cannot find the system partition.
* **Bluetooth/WiFi Inactive:** Check service status with `systemctl status rmtfs.service` or `tqftpserv.service`.
* **Audio Routing:** Verify that `/usr/share/alsa/ucm2/conf.d/sdm845` exists. Without these maps, the OS will not recognize physical audio hardware.
* **SCM Errors:** If `dmesg` reports `qcom_scm error -22`, re-run Script 9 to ensure the LineageOS firmware blobs have correctly overwritten older versions.

---

## Community

For real-time development updates and support, join the Discord server:
**PastorCatto's The ISLAND:** [https://discord.gg/RZV2HveyBg](https://discord.gg/RZV2HveyBg)

(My dumbass forgot to remove what the AI asked me afterwards! lmao. i will re-do all of this once i hit stable on the POCO F1 as i intend to daily drive this distro!)
