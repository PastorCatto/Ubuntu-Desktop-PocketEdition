# OUT OF DATE! WILL UPDATE AFTER TESTING

# Project Beryllium: Ubuntu-pmOS Hybrid Porting Guide

This documentation outlines the technical process for adapting the **ROM Cooker** build system to new ARM64 Android devices. The system utilizes a "Hybrid Transplant" methodology, where postmarketOS (pmOS) provides the hardware-enablement layer (kernel, modules, DTB) and Ubuntu Noble provides the user-space environment.

---

## Technical Architecture

The build process is divided into three distinct layers:

1.  **The Foundation:** Kernel and kernel modules sourced from a postmarketOS stable branch.
2.  **The Brain:** A vanilla Ubuntu Noble RootFS generated via debootstrap.
3.  **The Nervous System:** Mandatory proprietary firmware and hardware profiles (ALSA UCM, ModemManager, udev rules) harvested from a live donor device running Mobian.

---

## Mandatory Mobian Firmware & Hardware Profile Extraction

A critical component of this build system is the **Firmware Harvest (Script 3)**. Unlike standard Linux distributions, mobile hardware requires specific mapping files that are often missing from generic RootFS builds. 

To ensure functional hardware, the script extracts the following from a live Poco F1 running Mobian:

### 1. ALSA UCM (Audio Mapping)
Path: `/usr/share/alsa/ucm2/`
Without these Use Case Manager files, the system will not recognize the internal speakers, microphone, or earpiece. These files map the software audio streams to the physical Qualcomm hardware.

### 2. ModemManager & Mobile Data
Path: `/etc/ModemManager/`
These configurations are required for the system to initialize the cellular modem. This ensures that the Ubuntu build can correctly handle SMS, calls, and LTE data via the `modemmanager` daemon.

### 3. udev Rules (Peripheral Permissions)
Path: `/lib/udev/rules.d/`
These rules grant the user permission to access hardware sensors, the GPU, and the battery management system. Without these, the UI may fail to start or hardware acceleration will be disabled.

### 4. Proprietary Firmware Blobs
Path: `/lib/firmware/postmarketos/`
These are the binary blobs required by the kernel to initialize the WiFi, Bluetooth, and Adreno GPU components.

---

## Manual Adaptation Guide

To port this script to a device other than the Poco F1 (beryllium), several hardcoded strings and logic blocks must be updated manually.

### 1. Device Identification
The scripts are currently configured for the Poco F1. You must search and replace the following identifiers across the entire script set:
* **Vendor:** Change `xiaomi` to your target manufacturer.
* **Codename:** Change `beryllium` to your target device codename.

### 2. Storage Technology (UFS vs. eMMC)
The Poco F1 utilizes UFS storage. If your target device uses eMMC, consider the following:
* **Root Delay:** In `2_pmos_setup.sh`, the flag `rootdelay=5` is injected into the kernel command line. This is necessary for UFS initialization.
* **Sector Size:** Ensure your target hardware does not require a specific sector size (e.g., 4096 vs 512) for the RootFS image in `6_seal_rootfs.sh`.

### 3. Modifying the Firmware Donor (Script 3)
If a Mobian build does not exist for your target device, you must modify the source of the mandatory harvest:
* **From Mobian(Debian):** Update the SSH/SCP commands to pull from `/vendor/firmware` and `/system/etc/firmware`.
* **From Local Files:** If you already have a verified firmware stash, replace the SSH logic with a local copy command (`cp -a`) targeting the `FIRMWARE_STASH` directory.

---

## Build Workflow Summary

1.  **1_preflight.sh:** Configure your username, password, UI flavor, and desired image size.
2.  **2_pmos_setup.sh:** Initialize the pmOS environment and clone the required partition UUIDs.
3.  **3_firmware_fetcher.sh:** Connect to a live donor (Mobian) to harvest mandatory hardware profiles.
4.  **4_the_transplant.sh:** Build the Ubuntu base and merge the kernel and firmware.
5.  **5_enter_chroot.sh:** (Optional) Manually enter the environment for custom tweaks.
6.  **6_seal_rootfs.sh:** Convert the RootFS into Android-compatible sparse images.
7.  **7_kernel_menuconfig.sh:** (Optional) Modify kernel drivers or command line flags.

---

## Flashing Instructions

Once the scripts complete, use Fastboot to deploy the images:

```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_beryllium_boot_sparse.img
fastboot flash userdata ubuntu_beryllium_root_sparse.img
```
