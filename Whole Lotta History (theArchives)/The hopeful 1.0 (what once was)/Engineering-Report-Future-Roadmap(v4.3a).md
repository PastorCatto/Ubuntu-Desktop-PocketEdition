

# Engineering Report: Beryllium Mainline Architecture
**Project:** Ubuntu Desktop for POCO F1 (Beryllium)
**Document Version:** 4.3 (Alpha - Hardware Stabilization & Universal Roadmap)

This document serves as the technical source of truth for the automated build suite. It details the architectural evolution from a specialized Poco F1 tool to a generalized porting engine, explaining the "Partition Hijack" method and the recent resolution of peripheral initialization stalls.

---

## 1. The Bootloader Wars: The Search for a PC-like Boot
The Snapdragon 845 (SDM845) features a locked firmware chain ending in the Android Bootloader (ABL). We explored several methods to achieve a "standard" boot environment before settling on our current architecture.

### 1.1 Attempt 1: UEFI (`edk2-sdm845`) & Fedora Pocketblue
The theory was to flash custom UEFI firmware into the `boot` partition, transforming the phone into an ARM64 PC.
* **The Failure:** The `pmbootstrap` kernels for Beryllium lack `EFI_STUB` support by default. Enabling this requires manual `kconfig` edits and lengthy recompilations, which breaks the "seamless" goal of our automated suite.

### 1.2 Attempt 2: Chainloading U-Boot
We attempted to wrap U-Boot inside an Android boot image to search for standard `extlinux.conf` files.
* **The Failure:** Lack of upstream maintenance for SDM845 U-Boot and the heavy compilation burden made this too fragile for a streamlined tool.

### 1.3 The Victor: Native ABL Hijack (`pmos_boot.img`)
We utilize the native ABL to load a mainline Linux kernel (`Image.gz`), a device tree blob (`dtb`), and a minimal `initramfs` packed via `mkbootimg`. This ensures display initialization via the mainline `msm` DRM driver without secondary bootloader reliance.

---

## 2. The Partition Hijack & Storage Routing
To bypass the ABL's hardcoded reliance on internal UFS storage, we developed a "Warm Swap" method.

### 2.1 Dual-Partition Remapping
* **Linux `/boot` (BootFS)** -> Android `/system` (approx. 2-3GB)
* **Linux `/` (RootFS)** -> Android `/userdata` (remaining UFS capacity)

### 2.2 Advanced UUID Spoofing
The `initramfs` expects specific UUIDs. To avoid kernel panics, the Cooker script scrapes `PMOS_ROOT_UUID` and `PMOS_BOOT_UUID` from the build environment and uses `mkfs.ext4 -U <uuid>` to forcefully brand the custom Ubuntu images with those strings.

### 2.3 Resolving the `rootdelay=5` Race Condition
The mainline kernel boots faster than the UFS controller initializes. We inject `rootdelay=5` into the `deviceinfo_kernel_cmdline` to allow the hardware to present `/dev/sda` before the mount command executes.

---

## 3. Hardware Initialization & Firmware Splicing
A mainline kernel requires proprietary blobs to communicate with the hardware.

### 3.1 The SSH Firmware Bridge
Rather than hosting proprietary blobs, the suite establishes an SSH bridge to a live **Mobian** device. It extracts `/usr/share/alsa/ucm2` and `/lib/firmware/postmarketos/`, ensuring our Ubuntu build inherits community-stabilized hardware support legally.

---

## 4. Chroot Escapes & Architecture Crossing
Building an `aarch64` (ARM64) filesystem on an `x86_64` host requires a robust translation layer.

### 4.1 Bind Mounting Requirements
We implement a hardened bind-mount loop, projecting the host's `/dev`, `/dev/pts`, `/sys`, `/proc`, and `/run` into the `Ubuntu-Beryllium` workspace. This allows package managers to verify kernel architectures and security profiles during the build.

---

## 5. UI Evolution: The War on Bloat
To keep the OS responsive on mobile hardware, we moved away from full desktop metapackages.

### 5.1 Lomiri Deprecation
Ubuntu Touch (Lomiri) was abandoned due to its reliance on the `click` package manager, which frequently aborts under QEMU virtualization due to host/guest architecture mismatches.

### 5.2 Session-Only Targets
The suite targets bare-metal "session" packages (e.g., `plasma-mobile`, `phosh-core`) and utilizes the `--no-install-recommends` flag to strip out printer spoolers and other desktop-only bloat.

---

## 6. Peripheral Initialization: The Communication Layer
Peripheral support (WiFi, Sound, Sensors) on the SDM845 requires a userspace "handshake" via the Qualcomm IPC Router (QRTR) protocol.

### 6.1 The "Holy Trinity" of Services
To resolve the `USER-PD detects stalled initialization` crash, the suite injects three critical services:
* **`qrtr-ns`**: The internal phonebook for hardware nodes.
* **`pd-mapper`**: Handshakes with Protection Domains (Modem, ADSP, SLPI).
* **`rmtfs`**: Serves calibration data from UFS partitions to the co-processors.

### 6.2 Subsystem Interdependency
WiFi initialization is physically dependent on the Modem (MSS). By stabilizing the Modem via `rmtfs`, we provide the power/clock signals necessary for the **WCN3990** WiFi chip to appear.

---

## 7. Roadmap: Generic Porting & Stability

### 7.1 Phase 1: Beryllium "Gold" Stability
* **Power Management:** Stabilizing `max17050` fuel-gauge drivers for accurate battery reporting.
* **GPS & GNSS:** Finalizing `loc-mq` or `gpsd` integration via QRTR link.
* **Deep Sleep:** Tuning `s2idle` states for extended standby.
* **WiFi & Rotation:** Getting WiFI up using `pd-mapper` to communicate with the rest of the modules

### 7.2 Phase 2: The Universal Porting Engine
The Cooker is being refactored into a device-agnostic architecture. To ensure high-fidelity ports, the suite enforces a **Dual-Source Requirement**: a device must be supported by both **postmarketOS** and **Mobian**.

* **The pmOS Requirement (Hardware Foundation):** We utilize pmOS to generate the kernel, `boot.img`, and `initramfs`. Their mainline expertise ensures the low-level hardware is correctly initialized.
* **The Mobian Requirement (Userspace Polish):** We utilize Mobian as the source for proprietary firmware blobs and ALSA UCM profiles. Mobian’s commitment to a standard Debian-based mobile stack provides a cleaner userspace experience for our Ubuntu builds.

**Generic Porting with Device-Specific Overlays:**
By using this dual-source baseline, the Cooker can function as a generic porting tool. A core set of "mainline-standard" logic handles the QRTR and systemd setup, while a modular directory structure allows for **Device-Specific Patches and Fixes** (e.g., unique rotation matrices, display panel quirks, or specialized hardware buttons) to be injected during the final build phase.

---

### 8. Image Serialization
Script 6 utilizes `img2simg` to convert raw Ext4 filesystems into Android **Sparse Images**. This prevents buffer overflows during the `fastboot` process and allows the POCO F1’s bootloader to reconstruct the full 8GB geometry on the internal UFS.

