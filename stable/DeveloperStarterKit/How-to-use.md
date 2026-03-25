## Toolchain Adaptation and Deployment Guide

This toolchain is designed as a modular "script factory" for porting Linux distributions (specifically Ubuntu) to mobile and tablet devices. Instead of manually editing scripts for every new hardware target, this system uses a tiered automation approach to generate a device-specific build environment.

---

## Overview of the Workflow

The process moves through three distinct layers:

1.  **The Morphing Layer (`10_Toolchain_Device_Modifier.sh`):** A meta-script that performs a recursive string replacement on the master template to swap out vendor names, device codenames, and hardware models.
2.  **The Workspace Layer (`deploy_workspace.sh`):** A generation script that, when executed, "unpacks" itself into seven independent Bash scripts tailored to the target device.
3.  **The Execution Layer (Scripts 1-7):** The actual build pipeline that handles everything from dependency installation to final image flashing.

---

## Step 1: Adapting the Toolchain for New Hardware

Before building, you must "morph" the toolchain to recognize your specific device (e.g., shifting from a Poco F1/beryllium to a Samsung Tab A9+/gtaxl).

1.  **Run the Modifier:**
    ```bash
    bash 10_Toolchain_Device_Modifier.sh
    ```
2.  **Provide Device Details:** The script will prompt for the Vendor (e.g., `samsung`), the Codename (e.g., `gtaxl`), and the Model Name (e.g., `Galaxy Tab A9 Plus`).
3.  **Inject Extra Logic:** If your device requires specific kernel patches or unique udev rules, you can provide a path to an extra script snippet when prompted.
4.  **Result:** This generates a new file named `deploy_workspace_new.sh`.

---

## Step 2: Deploying the Build Workspace

Once you have your device-specific factory script, you must deploy the environment.

1.  **Execute the Factory Script:**
    ```bash
    bash deploy_workspace_new.sh
    ```
2.  **Result:** This creates seven numbered scripts (`1_preflight.sh` through `7_kernel_menuconfig.sh`) in your current directory. These scripts are now hardcoded with your device's paths and configurations.

---

## Step 3: The Build Sequence

Follow the scripts in numerical order to complete the porting process:

| Order | Script | Function |
| :--- | :--- | :--- |
| **1** | `1_preflight.sh` | Installs host dependencies (`qemu`, `debootstrap`) and sets user credentials/UI preferences. |
| **2** | `2_pmos_setup.sh` | Uses `pmbootstrap` to retrieve the device-specific kernel, headers, and boot configurations. |
| **3** | `3_firmware_fetcher.sh` | Pulls proprietary hardware blobs (Wi-Fi, GPU, Modem) from a device running a reference OS (like Mobian) via SSH. |
| **4** | `4_the_transplant.sh` | **The Core Build:** Bootstraps the Ubuntu ARM64 RootFS and merges it with the pmOS kernel and firmware. |
| **5** | `5_enter_chroot.sh` | A utility to "step inside" the new RootFS to perform manual configuration or install extra packages. |
| **6** | `6_seal_rootfs.sh` | Packages the build into sparse `.img` files ready for deployment via `fastboot`. |
| **7** | `7_kernel_menuconfig.sh` | A debugging tool to quickly access the kernel configuration for the target device. |

---

## Technical Details

* **Automation Method:** The modifier uses `sed` (Stream Editor) to perform case-sensitive replacements for codenames and vendors across thousands of lines of code.
* **Environment Isolation:** Each build is designed to run in its own directory (e.g., `Ubuntu-Beryllium` or `Ubuntu-Gtaxl`) to prevent cross-contamination between different device ports.
* **Safety:** The system checks for active mount points before sealing images to prevent data corruption.

