
# Ubuntu Desktop for POCO F1 (Beryllium)

This project provides a modular, automated build suite to deploy a full Ubuntu Desktop environment (Lomiri, XFCE, or GNOME) onto the POCO F1. By leveraging a partition-hijack method, we run a mainline Linux kernel on the Snapdragon 845 without requiring complex re-partitioning of the internal UFS storage.

-----

### Project Status and Links

  * **Development Archive:** [PastorCatto/Ubuntu-PocoF1-Archive](https://github.com/PastorCatto/Ubuntu-PocoF1-Archive)
  * **Technical Deep Dive:** [Engineering-Report.md](https://github.com/PastorCatto/Ubuntu-Desktop-For-POCO-F1-beryllium/blob/main/Engineering-Report.md) (Advanced breakdown of the hijack logic and UUID cloning)

-----

### Philosophy and AI Transparency

1.  **AI Implementation:** The bash scripts in this suite were generated using Gemini Pro (Feb-Mar 2026). This was done strictly for rapid automation.
2.  **Human-First Security:** I will not use AI to generate executables, binaries, or obfuscated code. Everything here remains human-readable bash to ensure no backdoors, exploits, or RATS are introduced. If the project scales, development will shift to a human-led polish phase.
3.  **Credits:** Kernel and boot image generation is powered by **pmbootstrap**. Firmware blobs are sourced from **Qualcomm** and **Debian**.
4.  **License:** This project is licensed under **GPL 2.0**. Upstream components fall under their respective licenses.

-----

### System Requirements

| Requirement | Specification |
| :--- | :--- |
| **Host OS** | Ubuntu 24.04.1 LTS (Native or WSL) |
| **Disk Space** | 50GB minimum (Building multiple 8GB+ images) |
| **Target Device** | POCO F1 (Beryllium) |
| **Firmware Source** | Mobian Weekly SDM845 (For SSH harvest) or local blobs |

-----

### Installation Guide

#### Step 1: Preparation and Firmware

  * Install WSL or a native Ubuntu 24.04 environment.
  * **Firmware Harvest (Optional but Recommended):**
    1.  Flash [Mobian Weekly](https://images.mobian.org/qcom/weekly/) to your device.
    2.  Connect to Wi-Fi and run: `sudo apt update && sudo apt install openssh-server && sudo systemctl enable ssh`
    3.  Note your device IP. The default password is `1234`.
  * Copy the **AIO Deployment Script** from this repository and paste it into your host terminal to generate the workspace.

#### Step 2: Critical Build Quirks

  * **The Display Bug:** Kernels post-6.14 currently suffer from a DSI panel initialization failure (Blank Screen). When `pmbootstrap` asks for a channel, you **MUST** select **v25.06**. This utilizes a stable kernel branch that supports the Tianma and EBBG panels correctly.
  * **The Prompt Loop:** During `pmbootstrap install`, you will be asked for a user password. This is a framework requirement; enter any value, as it is not utilized by the final Ubuntu environment.

#### Step 3: Script Execution Flow

Do not skip steps unless you are performing a targeted update.
Run 1,2,3,4,6 (5 and 7 are debugging scripts for devs)

1.  **deploy\_workspace.sh**: Run once to generate the build environment.
2.  **1\_preflight.sh**: Sets up host dependencies and build.env.
3.  **2\_pmos\_setup.sh**: Compiles the kernel and clones hardware UUIDs.
4.  **3\_firmware\_fetcher.sh**: Harvests blobs from your live Mobian device via SSH.
5.  **4\_the\_transplant.sh**: Builds the Ubuntu RootFS and installs the selected UI.
6.  **8\_lomiri\_hotfix.sh**: (Lomiri Only) Fixes DBus and LightDM configurations.
7.  **6\_seal\_rootfs.sh**: Finalizes the build and packs the images.
8.  **5\_enter\_chroot.sh**: (Utility) Enter the build environment for manual edits.
9.  **7\_kernel\_menuconfig.sh**: (Utility) Modify kernel parameters or deviceinfo.

-----

### Deployment and Flashing

The build process generates two types of images. **Sparse images** are for internal flashing via Fastboot. **Raw images** are for MicroSD card deployment.

#### Image Mapping Table

| File Name | Type | Target Partition | Deployment Method |
| :--- | :--- | :--- | :--- |
| **pmos\_boot.img** | Android Boot | Internal /boot | **Mandatory** (Trigger) |
| **ubuntu\_boot\_sparse.img** | Sparse Ext4 | Internal /system | Internal Hijack |
| **ubuntu\_root\_sparse.img** | Sparse Ext4 | Internal /userdata | Internal Hijack |
| **ubuntu\_boot.img** | Raw Ext4 | SD Partition 1 | MicroSD Boot |
| **ubuntu\_root.img** | Raw Ext4 | SD Partition 2 | MicroSD Boot |

#### Internal Flashing Instructions

Boot the POCO F1 into Fastboot mode (Power + Volume Down) and execute:

```bash
fastboot flash boot pmos_boot.img
fastboot flash system ubuntu_boot_sparse.img
fastboot flash userdata ubuntu_root_sparse.img
fastboot reboot
```

**Important:** After running "fastboot reboot", do not interrupt the device, fastboot is finishing the write to NAND, INTERRUPTING THIS WILL BRICK YOUR INSTALL!\!

-----

### Contribution and Prebuilts

Prebuilt images are planned once the **edge** kernel branch is fully stabilized and the "blank screen" bug on newer kernels is resolved. If you wish to contribute to the kernel debugging, please refer to the Engineering Report.

### Massive Thanks ### 
PostmarketOS (The whole postmarketOS community!) https://postmarketos.org/
Debian (Trademark of Software in the Public Interest, Inc.) https://www.debian.org/ 

-----

