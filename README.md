# Ubuntu Desktop PocketEdition
# Document Version 2.2a (AI ADDED CHANGELOG!)
# Note: the Devices/Xiaomi_beryllium folder is where i do most of my work (Updated first)
# hence if you want BLEEDING EDGE (STRONGLY ADVISE AGAINST) go there for the absolute LATEST scripts
# DeveloperStarterKits are Built against the EDGE versions (pass testing with no bugs, and excluding ALPHA SDM845 scripts) 

Ubuntu Desktop PocketEdition is an advanced porting toolkit designed to deploy a functional, desktop-class Ubuntu Noble (24.04) environment onto the Xiaomi Poco F1 (beryllium) and related Snapdragon 845 (SDM845) devices. 

The project bridges the gap between mobile hardware and a standard Linux desktop by utilizing a unique "Hybrid Transplant" methodology. It leverages the hardware-enablement foundation of postmarketOS (pmOS), the stability of a vanilla Ubuntu RootFS, and verified vendor firmware from the LineageOS ecosystem.

---

## Technical Architecture: The Hybrid Transplant

This toolkit constructs a functional OS by merging three distinct layers:

1. **Hardware Foundation:** A stable kernel, kernel modules, and Device Tree Blobs (DTB) sourced from the postmarketOS (pmOS) v25.06 (stable) branch.
2. **Operating System:** A vanilla Ubuntu Noble (24.04) ARM64 RootFS generated via debootstrap.
3. **Hardware Mapping & Firmware:** A modern Qualcomm service stack (QRTR, RMTFS, PD-Mapper, TQFTPServ) combined with verified, signed firmware blobs sourced from the LineageOS/TheMuppets repositories to ensure TrustZone authentication success.

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
*Note: For SDM845 devices, it is recommended to use the new Script 8 for firmware management.*

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

### 8. Hardware Enablement (The Qualcomm Stack Compiler)
**Qualcomm_Stack_beryllium.sh** (Integrated Qualcomm_Compiler.sh)
The primary enablement script for SDM845 hardware. It automates the following in a protected chroot environment:
* **Dependency Resolution:** Installs critical build headers including libudev-dev, libzstd-dev, and liblzma-dev.
* **Source Compilation:** Compiles the latest upstream linux-msm toolchain from source (QRTR, QMIC, RMTFS, TQFTPServ, PD-Mapper).
* **Smart Detection:** Automatically locates the Ubuntu rootfs via build.env or wildcard hunting.
* **Firmware Deployment:** Performs a surgical sparse-checkout of LineageOS blobs and fixes case-sensitivity issues (Error -2 fixes).
* **Service Management:** Enables systemd units to ensure IPC daemons initialize before the DSP.

### 9. Stack Health Validation
**check_qcom_stack.sh**
A post-build auditing tool to verify the entire hardware stack.
* **Usage:** Run this within the chroot or on the live device.
* **Checks:** Validates compiled binaries, .mdt headers, JSON domain maps, and WiFi calibration files.

---

## Technical Development Changelog

### Phase 1: Base System & Hybrid Integration
* Established the bridge between pmOS boot architecture and Ubuntu Noble (24.04).
* Implemented dynamic environment loading and smart rootfs detection to handle modular filesystem naming.

### Phase 2: TrustZone & Firmware Integrity
* Resolved SCM Error -22 (EINVAL) by ensuring precise placement of .mdt metadata headers for modem and DSP subsystems.
* Implemented a global case-sensitivity patch (Error -2 fix) to automatically lowercase all vendor blobs to match mainline kernel requirements.

### Phase 3: Audio Subsystem Stabilization
* Successfully initialized the ADSP to enable internal microphone array support.
* Integrated ALSA UCM2 hardware routing profiles for the Xiaomi Poco F1.
* Mapped physical hardware mixer switches to resolve audio routing issues.

### Phase 4: Modem & WiFi Recovery
* Diagnosed and resolved Hexagon DSP watchdog panics (stalled INIT TRIAGE OWNER).
* Restored missing pd-mapper JSON configuration files required for memory domain assignment.
* Injected WCN3990-specific board-2.bin calibration data for stable wireless operation.

### Phase 5: Native IPC Toolchain Compilation
* Migrated from repository-based packages to a native source-built stack to improve sleep/wake stability.
* Integrated the Qualcomm Message Interface Compiler (QMIC) into the build pipeline.
* Optimized the build environment for Meson/Ninja and traditional Make compatibility.

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
* **SCM Errors:** If `dmesg` reports `qcom_scm error -22`, re-run Script 8 to ensure the LineageOS firmware blobs have correctly overwritten older versions.

---

## Community

For real-time development updates and support, join the Discord server:
**PastorCatto's The ISLAND:** [https://discord.gg/RZV2HveyBg](https://discord.gg/RZV2HveyBg)

---
