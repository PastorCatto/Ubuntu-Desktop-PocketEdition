


# UPDATE! WE NOW HAVE A PORTING GUIDE TO PORT TO OTHER DEVICES! YOU CAN ADAPT THIS SCRIPT TO BUILD FOR WHAT YOU NEED!
# GOOD LUCK!


# Ubuntu Desktop for POCO F1 (Beryllium)

This project provides a modular, automated build suite to deploy a clean, functional Ubuntu Linux OS directly onto the POCO F1 (Snapdragon 845). 

Rather than relying on pre-compiled, opaque system images, this toolset empowers you to build the operating system entirely from scratch on your own machine. It utilizes a "Partition Hijack" method to run a mainline Linux kernel natively on the Android bootloader, without requiring risky re-partitioning of the internal UFS storage.

---

### Project Philosophy
1. **Human-Readable Code:** Everything in this repo is standard, auditable bash to ensure zero backdoors or hidden exploits. 
2. **Vanilla Stability, Surgical Debloat:** Minimal session packages often lack critical polkit rules and Wayland wrappers, resulting in dead screens. This suite installs the full, stable "vanilla" desktop environments to ensure background services wire correctly, but automatically runs surgical purges (like aggressively stripping out the LibreOffice suite) before sealing the image to save space and RAM.
3. **Credits & Upstream:** Kernel and boot image generation is powered by the incredible **pmbootstrap** from the postmarketOS team. Firmware blobs are sourced natively from **Mobian/Debian** and **Qualcomm**. All upstream code falls under their respective open-source licenses; this project is licensed under GPL 2.0.

---

### System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Host OS** | Ubuntu 24.04 LTS (Native PC, Container, or WSL) |
| **Disk Space** | 50GB minimum (The script generates a 12GB+ RootFS, plus pmbootstrap caches) |
| **Target Device** | POCO F1 (Beryllium) |
| **Firmware Source** | Mobian Weekly SDM845 (For SSH hardware harvesting) or local archive |

---

### Available OS Flavors
When generating your workspace, you can choose from the following environments. The script dynamically configures the correct Display Manager (`gdm3`, `sddm`, or `lightdm`) in the background so you never boot to a black screen.

**Mobile Shells (Touch-First, Wayland Native)**
* **Phosh:** Purism's mobile GNOME shell. Includes Squeekboard for virtual typing.
* **Plasma Mobile:** KDE's mobile interface. Includes Maliit for virtual typing.

**Desktop Flavors (Tablet/PC Experience)**
* **GNOME Vanilla:** The standard Ubuntu desktop (`ubuntu-desktop-minimal`).
* **KDE Plasma Vanilla:** The standard Kubuntu experience (`kde-plasma-desktop`).
* **Ubuntu Unity Vanilla:** The classic left-dock interface (`ubuntu-unity-desktop`).
* **XFCE Vanilla:** Fast, CPU-rendered, and rock-solid (`xubuntu-core`).

*(Note: All desktop flavors automatically install the `onboard` virtual keyboard so you can log in without requiring a USB-C OTG hub, and have LibreOffice purged by default).*

---

### Installation & Build Guide

#### Step 1: Host Preparation & Firmware Harvesting
1. Prepare your Ubuntu 24.04 host environment.
2. **Harvest the Firmware:** Mainline Linux requires proprietary Qualcomm blobs (Audio UCMs, Modem rules) to talk to the SDM845 hardware. 
   * Flash [Mobian Weekly](https://images.mobian.org/qcom/weekly/) to your POCO F1.
   * Boot the phone, connect to Wi-Fi, and enable the SSH server: `sudo apt update && sudo apt install openssh-server && sudo systemctl enable ssh`
   * *Note: The default Mobian password is `1234`.*
3. Copy the master `deploy_workspace.sh` script from this repo into an empty folder on your PC and run it.

#### Step 2: Critical pmbootstrap Quirks
When the script triggers `pmbootstrap init`, pay attention to this upstream quirk:
* **The Display Bug:** Kernels newer than 6.14 currently suffer from a DSI panel initialization failure (resulting in a blank screen). We **highly recommend** choosing the **`v25.06`** channel during initialization. This locks the build to a stable kernel branch that properly initializes the Tianma and EBBG screens. Testing the `edge` channel is done at your own risk.
* **The Ghost Password:** During the install phase, pmbootstrap will ask for a user password. Enter any value; it is a placeholder that our Ubuntu chroot completely ignores.

#### Step 3: Script Execution Flow
Run the generated scripts in this exact order.

1. **1_preflight.sh**: Installs host dependencies (qemu, debootstrap) and creates your `build.env` configuration.
2. **2_pmos_setup.sh**: Compiles the mainline kernel via pmbootstrap, injects UFS timing fixes (`rootdelay=5`), and clones the hardware UUIDs.
3. **3_firmware_fetcher.sh**: SSHs into your live Mobian phone, bundles the hardware directories, and pulls them to your host PC.
4. **4_the_transplant.sh**: The heavy lifter. Builds a clean Ubuntu ARM64 root filesystem, injects the kernel and firmware, installs your chosen UI, and purges LibreOffice.
5. **5_enter_chroot.sh**: *(Optional)* Safely mounts host pipes (`/proc`, `/run`, `/sys`) and drops you into the OS as root for manual tweaking.
6. **6_seal_rootfs.sh**: Packs the raw folder into flashable Android sparse images.
7. **7_kernel_menuconfig.sh**: *(Optional)* A quick-launch menu for advanced kernel `kconfig` editing and `deviceinfo` patching.

---

### Flashing & Deployment

#### Method A: Internal Storage (The Hijack)
This wipes Android completely. Boot the POCO F1 into Fastboot mode (Power + Volume Down) and execute:
```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_beryllium_boot_sparse.img
fastboot flash userdata ubuntu_beryllium_root_sparse.img
fastboot reboot
```
**CRITICAL:** After sending the reboot command, do NOT touch the power button. The initial boot sequence requires several minutes to expand the filesystem and initialize the Display Manager. Just wait.

#### Method B: MicroSD Card Testing
Use `fdisk` or `gparted` to create two Ext4 partitions on a MicroSD card. Use `dd` to flash the **Raw** (`.img`) files to the SD card. You must still flash the `pmos_boot.img` to the phone's internal `/boot` partition via Fastboot to trigger the kernel.

---

### Advanced: Kernel Debugging & Verbose Boot
If your POCO F1 is hanging on the postmarketOS splash screen and you need to read the kernel `dmesg` logs to see what hardware failed, you can force a verbose matrix-style boot.

#### Method 1: On-the-Fly Fastboot Injection (Live Boot Only)
For a quick, temporary test without recompiling the image, you can instruct Fastboot to inject the flags directly into RAM. *Note: Depending on your specific Xiaomi firmware version, the Android Bootloader may block real-time string injections. If the screen remains blank, use Method 2.*
```bash
fastboot --cmdline "PMOS_NOSPLASH console=tty0" boot pmos_boot.img
```

#### Method 2: Permanent Header Modification (`deviceinfo` trick)
To bake the verbose flags permanently into the boot image header:
1. On your host PC, locate your deviceinfo file:
   `nano ~/.local/var/pmbootstrap/cache_git/pmaports/device/*/device-xiaomi-beryllium/deviceinfo`
2. Scroll to the bottom and add (or modify) the command line variable:
   `deviceinfo_kernel_cmdline="PMOS_NOSPLASH console=tty0 msm.vblank_workaround=0"`
3. Rebuild the ramdisk and export the new boot image:
   `pmbootstrap initfs && pmbootstrap export`
4. Flash the resulting `/tmp/postmarketOS-export/boot.img` to your device. The splash screen will be permanently disabled, routing all kernel text directly to the display.

---
*(For a deeper dive into how the dual-UUID partition spoofing works, please refer to the `Engineering-Report.md` document).*

