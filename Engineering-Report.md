[ Engineering Report: How the Build Suite Operates ]

1. Leveraging the pmbootstrap "Core"
   We do not reinvent the wheel for kernel compilation. We use pmbootstrap 
   as a 'headless engine' to handle the cross-compilation of the mainline 
   Snapdragon 845 kernel. 
   - Our script (Script 2) initiates a pmbootstrap instance in 'none' 
     UI mode to generate a minimal Alpine-based environment. 
   - We then 'Harvest' the following from the pmbootstrap chroot:
     * /boot/vmlinuz         (The Mainline Kernel)
     * /boot/dtbs/* (Device Tree Blobs for Tianma/EBBG panels)
     * /lib/modules/* (Essential kernel drivers/modules)
     * /boot/initramfs       (The initial boot environment)

2. The Remote Firmware Extraction (The Mobian SSH Bridge)
   Mainline Linux on mobile hardware requires proprietary 'blobs' for 
   Wi-Fi, Bluetooth, and Audio (ALSA UCM profiles). 
   - Why SSH? Modern Qualcomm firmware is often version-matched to the 
     specific Android vendor image. Mobian has already done the heavy 
     lifting of stabilizing these for the SDM845. 
   - Script 3 creates a bridge to a live Mobian device to surgically 
     extract:
     * /usr/share/alsa/ucm2  (Audio routing profiles)
     * /lib/firmware/post... (Modem and GPU firmware)
     * /etc/ModemManager     (Cellular configuration)
   - This ensures your Ubuntu build has 'day-zero' hardware support.

3. Automated RootFS Transplantation
   Unlike standard Android ROMs which use 'Update.zip' packages, we 
   perform a 'Warm Swap' of the entire OS:
   - Script 4 builds a clean Ubuntu Noble (24.04) arm64 base using 
     'debootstrap'. 
   - We then 'Transplant' the pmOS kernel and Mobian firmware into 
     this base. 
   - This creates a hybrid: An Ubuntu OS with a postmarketOS 
     heart and Mobian hardware-senses.

4. Image Serialization (Raw vs. Sparse)
   Android's 'fastboot' protocol cannot handle raw disk images larger 
   than a few gigabytes. 
   - Script 6 uses 'img2simg' to convert our massive 8GB+ Ubuntu 
     partitions into 'Sparse Images'. 
   - This compresses the 'empty space' in the image, allowing the 
     POCO F1's bootloader to swallow a full desktop-sized OS without 
     timing out or hitting memory limits.

5. The "Beryllium" Display Fix (v25.06 Lock)
   The scripts are hardcoded to suggest the v25.06 stable channel. 
   Newer 'edge' kernels (6.14+) currently have a DSI-panel timing 
   bug that causes a black screen. By locking to v25.06, we ensure 
   the 'msm' DRM driver initializes the display before the 
   Lomiri/XFCE greeter starts.