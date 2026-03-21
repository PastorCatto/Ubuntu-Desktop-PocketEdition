# Project Beryllium: Ubuntu-pmOS Hybrid Porting Toolkit
# Document version v2.0a (the Public Port Toolkit Update)

This repository contains a modular toolkit for building a custom Ubuntu Noble (24.04) image for the Xiaomi Poco F1 (beryllium). It utilizes a "Hybrid Transplant" methodology, employing postmarketOS (pmOS) as the hardware-enablement foundation and a live Mobian installation for mandatory proprietary firmware and hardware mapping.

---

## Technical Overview

The build process creates a functional Linux environment by merging three distinct layers:

1.  **Hardware Foundation:** Kernel, modules, and Device Tree Blobs (DTB) sourced from the postmarketOS stable branch.
2.  **Operating System:** A vanilla Ubuntu Noble ARM64 RootFS generated via debootstrap.
3.  **Hardware Mapping:** Proprietary binary blobs and configuration files (ALSA, ModemManager, udev) harvested from a donor device running Mobian.

---

## Prerequisites

### Host System
* **OS:** Ubuntu 22.04 LTS or newer (x86_64).
* **Storage:** 40GB+ free space.
* **Privileges:** Sudo access is required for debootstrap and filesystem mounting.

### Hardware
* **Target:** Xiaomi Poco F1 (beryllium) with an unlocked bootloader.
* **Donor:** A secondary Poco F1 running a functional Mobian installation (required for Script 3).
* **Network:** Both the host and donor must be on the same local network for SSH harvesting.

---

## Installation and Script Generation

To initialize the workspace, run the deployment script. This generates the seven modular scripts required for the build process.

```bash
bash deploy_workspace.sh
```

---

## Step-by-Step Build Instructions

### 1. Pre-Flight Setup
```bash
bash 1_preflight.sh
```
Initializes host dependencies and saves your configuration (username, password, UI choice, and image size) to `build.env`.

### 2. postmarketOS Foundation
```bash
bash 2_pmos_setup.sh
```
Initializes `pmbootstrap`. When prompted, you must select:
* **Channel:** v25.06
* **Vendor:** xiaomi
* **Device:** beryllium
* **UI:** none
* **Init:** systemd

The script patches the kernel command line for UFS compatibility and clones the partition UUIDs to ensure the Ubuntu RootFS is mountable by the pmOS initramfs.

### 3. Mandatory Firmware Harvest
```bash
bash 3_firmware_fetcher.sh
```
Requires the Mobian donor device's IP address. This script performs a mandatory extraction of:
* **ALSA UCM:** Required for audio routing and speaker/mic functionality.
* **ModemManager:** Required for LTE, SMS, and Voice calls.
* **udev Rules:** Required for hardware peripheral permissions (GPU, Sensors).
* **Proprietary Blobs:** WiFi, Bluetooth, and Adreno GPU firmware.

### 4. The Transplant (OS Build)
```bash
bash 4_the_transplant.sh
```
Generates the Ubuntu Noble base via debootstrap and merges the kernel from Stage 2 with the hardware profiles from Stage 3. It then chroots into the environment to install the selected UI (Phosh, Plasma Mobile, etc.).

### 5. Manual Maintenance
```bash
bash 5_enter_chroot.sh
```
Provides a hardened entry point into the Ubuntu chroot for manual software installation or configuration tweaks.

### 6. Image Sealing
```bash
bash 6_seal_rootfs.sh
```
Allocates the final images, applies the cloned UUIDs via `mkfs.ext4`, and converts the raw images into Android-compatible sparse images (`.img`).

### 7. Kernel Configuration
```bash
bash 7_kernel_menuconfig.sh
```
Optional utility to modify kernel drivers via menuconfig or edit the `deviceinfo` file.

---

## Porting to Other Devices

To adapt this toolkit for a different device, the following manual updates are required:

1.  **Identifiers:** Perform a global search and replace for `xiaomi` and `beryllium` with your target vendor and codename.
2.  **Storage Logic:** If the target device uses eMMC instead of UFS, you may reduce the `rootdelay=5` flag in Script 2.
3.  **Firmware Source:** If a Mobian donor is unavailable, Script 3 must be modified to pull blobs from an Android `/vendor` partition or a local directory.
4.  **Audio Mapping:** In Script 4, ensure the ALSA UCM paths match the SoC of the new target (e.g., `ucm2/conf.d/sdm845`).

---

## Deployment (Flashing)

After completing Script 6, place the target device in Fastboot mode and execute:

```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_beryllium_boot_sparse.img
fastboot flash userdata ubuntu_beryllium_root_sparse.img
fastboot reboot
```

---

## Troubleshooting

* **Black Screen on Boot:** Ensure the v25.06 channel was used in Step 2.
* **No Audio:** Verify that the ALSA UCM harvest in Step 3 completed without SSH errors.
* **Filesystem Read-Only:** Verify the UUID cloning in Step 2; if the UUIDs in `build.env` do not match the final images, the initramfs will fail to mount the RootFS as writeable.

## Refer to the Readme(v1.0a) for more of a general idea of the project
## As well as the Engineering Report (Future Roadmap) for more details Long-Term