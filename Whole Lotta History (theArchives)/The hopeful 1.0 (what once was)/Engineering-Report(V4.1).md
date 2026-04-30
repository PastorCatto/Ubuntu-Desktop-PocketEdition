

>>>>>>> origin/cattotest:Engineering-Report.md
# Engineering Report: Beryllium Mainline Architecture
**Project:** Ubuntu Desktop for POCO F1 (Beryllium)
**Document Version:** 4.1 (Bootloader Retrospective & Channel Clarification)

This document serves as a technical deep dive into the automated build suite. It details our architectural evolution, our abandoned attempts at standardizing the bootloader via UEFI and U-Boot, and explains the intricate mechanics of our final "Partition Hijack" method.

---

## 1. The Bootloader Wars: The Search for a PC-like Boot

The ultimate holy grail of running mainline Linux on a smartphone is achieving a standard "PC-like" boot environment—where you can plug in a USB drive, access a GRUB menu, and install an OS normally. However, the Snapdragon 845 (SDM845) has a locked-down firmware chain ending in the Android Bootloader (ABL). We explored three distinct methods to break out of this chain before settling on our current architecture.

### Attempt 1: The UEFI Port (`edk2-sdm845`) & Fedora Pocketblue
The Renegade Project has made massive strides in porting the EDK2 UEFI environment to the SDM845 platform. The theory was to flash this custom UEFI firmware into the Android `boot` partition, effectively transforming the POCO F1 into a standard ARM64 PC capable of booting generic `.iso` files via systemd-boot or GRUB. 

This approach gained significant traction with the **Fedora Pocketblue** project—a brilliant community initiative aimed at bringing Fedora Atomic (immutable) OS architectures to mobile devices like the POCO F1. Attempting to marry Pocketblue's advanced image-based deployment with a true UEFI bootchain was a tantalizing prospect for our project.

* **Why it failed for our automation:** The death of this method came down to kernel configuration. The mainline Linux kernels sourced via `pmbootstrap` for the Beryllium device do not have `EFI_STUB` support enabled by default. Without `EFI_STUB`, the kernel cannot be executed by the UEFI firmware. To make this work, the automated script would have to pause, force the user to manually edit the kernel configuration (`pmbootstrap kconfig edit`), and execute a lengthy kernel recompilation from scratch. This destroyed the project's goal of being a fast, seamless, "paste-and-go" deployment tool, leading us to abandon UEFI entirely.

### Attempt 2: Chainloading U-Boot (`u-boot-beryllium`)
Our second attempt was compiling a native `u-boot` binary specifically for the Beryllium board. The strategy was to wrap the U-Boot executable inside a standard Android boot image, have the Android Bootloader (ABL) execute it, and then let U-Boot initialize the screen and search the MicroSD card or UFS for a standard `extlinux.conf` file.

* **Why it failed for our automation:** 1. **Lack of Upstream Support:** U-Boot support for the SDM845, and specifically the POCO F1, is highly fragmented and lacks robust, ongoing maintenance from the upstream community. Relying on a poorly supported, disjointed bootloader introduces massive stability risks and breaks future compatibility.
  2. **The Compilation Burden:** To make U-Boot work, it requires a highly specific, custom compilation pass for the target device. Forcing our script suite to download the U-Boot source tree, configure the Beryllium defconfigs, and cross-compile the bootloader from scratch added unnecessary bloat, extreme time delays, and multiple points of failure to what was supposed to be a streamlined tool.

### The Victor: The Native ABL Hijack (`pmos_boot.img`)
We abandoned the dream of a pre-boot menu in favor of bulletproof reliability. We utilize `pmbootstrap` to cross-compile the mainline Linux kernel (`Image.gz`), the device tree blob (`dtb`), and a minimal `initramfs`. 

* **The Mechanism:** These components are packed using standard Android `mkbootimg` parameters. The ABL reads this image, assumes it is booting standard Android, loads the kernel into specific RAM addresses, and blindly passes execution. It is fast, safe, and guarantees display initialization because we let the mainline Linux `msm` DRM driver handle the screen natively rather than relying on a secondary bootloader.

---

## 2. The Partition Hijack & Storage Routing

Because we are utilizing the native ABL, the boot sequence is hardcoded to look at the internal UFS storage. We developed a "Warm Swap" hijack method.

### 2.1 Dual-Partition Remapping
Android defines `/system` (usually 2-3GB) and `/userdata` (the rest of the 64GB+ chip). We repurpose these entirely:
* **Linux `/boot` (BootFS) -> Android `/system`**
* **Linux `/` (RootFS) -> Android `/userdata`**

### 2.2 Advanced UUID Spoofing
The postmarketOS `initramfs` is tightly generated. During compilation, it hardcodes the exact UUIDs it expects to find for the boot and root partitions inside its local `fstab`. If it doesn't find them, the kernel panics and drops to an emergency shell.

* **The Engineering Fix:** Script 2 scrapes the `PMOS_ROOT_UUID` and `PMOS_BOOT_UUID` directly from the generated pmOS chroot. Later, during image generation, Script 6 uses `mkfs.ext4 -U <spoofed_uuid>` to forcefully brand our custom Ubuntu images with those exact hexadecimal strings. The kernel reads the UFS block device, sees the expected UUIDs, and mounts the Ubuntu OS seamlessly, completely unaware it isn't running postmarketOS.

### 2.3 Resolving the `rootdelay=5` Race Condition
A critical race condition exists on the SDM845 platform: the mainline kernel boots so rapidly that it attempts to mount the RootFS before the internal UFS storage controller has finished its hardware initialization sequence. 

* **The Engineering Fix:** Script 2 dynamically alters the `deviceinfo_kernel_cmdline` variable, injecting `rootdelay=5`. This forces the kernel to halt execution for 5 seconds, allowing the UFS hardware to wake up and present its block devices (`/dev/sda`, `/dev/sde`, etc.) before the mount command fires.

---

## 3. Hardware Initialization & Firmware Splicing

A mainline kernel without proprietary firmware blobs is deaf, blind, and disconnected.

### 3.1 The DSI Display Bug & Channel Selection
We encountered a critical regression in bleeding-edge (`edge`) kernels. A DRM/KMS (Kernel Mode Setting) synchronization issue with the Beryllium's DSI timing results in the display failing to wake up, even though the OS is fully functional via SSH.

* **The Engineering Fix:** While the build suite does not strictly enforce a specific release channel, our extensive testing revealed that `v25.06` provides the most stable and reliable kernel baseline for the POCO F1. We strongly recommend users select `v25.06` during `pmbootstrap init` to ensure the `msm` (Freedreno/Turnip) driver correctly initializes the framebuffer before handing control to the display manager. Users testing the `edge` channel do so at the risk of encountering the blank screen bug.

### 3.2 The SSH Firmware Bridge
Audio routing on modern Qualcomm chips requires complex ALSA UCM (Use Case Manager) profiles. Furthermore, the Wi-Fi, Bluetooth, and Cellular Modems require closed-source binaries matched to the specific vendor partition of the device.

* **The Engineering Fix:** Rather than maintaining an illegal repository of proprietary blobs, Script 3 establishes a secure SSH bridge to a live device running **Mobian**. It surgically extracts `/usr/share/alsa/ucm2` and `/lib/firmware/postmarketos/` directly from a functional, community-stabilized OS. This ensures our Ubuntu build inherits 'day-zero' hardware support legally.

---

## 4. Chroot Escapes & Architecture Crossing

Building an `aarch64` (ARM64) filesystem on an `x86_64` host utilizing Windows Subsystem for Linux (WSL) requires a robust translation layer (`qemu-user-static`).

### 4.1 The `/proc` and `/run` Bind Mounting Requirement
During initial development, package managers utilized the virtual `/proc` filesystem to verify kernel architecture and AppArmor security profiles. An empty chroot jail triggered a fatal panic.

* **The Engineering Fix:** Scripts 4 and 5 implement a hardened bind-mount loop. We project the host machine's `/dev`, `/dev/pts`, `/sys`, `/proc`, and crucially `/run` directly into the `Ubuntu-Beryllium` workspace. This tricks the package manager into seeing a fully operational, live kernel, allowing complex `systemd` hooks and architecture checks to complete successfully.

---

## 5. UI Evolution: The War on Bloat

The transition from a command-line interface to a graphical desktop required a massive shift in how we handle Debian packages.

### 5.1 The Lomiri Deprecation
Early versions of this suite attempted to deploy **Lomiri (Ubuntu Touch)**. This failed catastrophically due to Lomiri's reliance on the `click` package manager, which utilizes Python subprocesses to verify hardware architecture. Under QEMU virtualization, the host kernel reported as x86_64, causing the ARM64 `click` installer to violently abort. 

### 5.2 Session Packages & `--no-install-recommends`
Standard Ubuntu metapackages (`ubuntu-desktop`) pull in CUPS printer spoolers, heavy email clients, and background telemetry that devastate a smartphone's resources.

* **The Engineering Fix:** The suite targets bare-metal "session" packages (e.g., `gnome-session`, `plasma-desktop`, `phosh-core`). Furthermore, the master `apt-get install` command is hardcoded with the `--no-install-recommends` flag. This violently strips out all suggested bloatware, ensuring the final image contains only the absolute minimum binaries required to render the UI.

---

## 6. Image Serialization (Sparse vs. Raw)

Android's `fastboot` protocol is notoriously unstable when flashing raw disk images exceeding 2GB. Attempting to flash an 8GB raw Ubuntu Ext4 image will result in a buffer overflow.

* **The Engineering Fix:** Script 6 utilizes the `img2simg` utility to convert our raw Ext4 filesystems into Android **Sparse Images**. This process analyzes the 8GB filesystem, identifies the empty blocks, and compresses them. The resulting sparse image is mathematically chopped into smaller chunks that `fastboot` can swallow. The POCO F1's bootloader then reconstructs the full 8GB geometry natively on the internal UFS. 

