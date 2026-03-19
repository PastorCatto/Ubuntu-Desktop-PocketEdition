# Ubuntu Desktop for POCO F1 (Beryllium)


#### AI GENERATED TO SAVE TIME, HUMAN-WRITTEN README ALSO ATTACHED ####
#### My REPO i used to store all my progress is located here: https://github.com/PastorCatto/Ubuntu-PocoF1-Archive  ####
#### My organization is a mess (IM SORRY!) so hence the fresh repo once i got system booting! ####
#### Check Engineering-Report.md for a more advanced breakdown of how we got here and what actually happens ####


Welcome! This project provides a fully automated, paste-and-go script suite to build and install a custom Ubuntu Desktop OS (Lomiri, XFCE, or GNOME) directly onto your POCO F1.

The intention here is transparency: you should know what is installed and how it was done. Because **YOU** built it, you can see the logs, you choose the UI, and you know exactly what is running on your device, rather than relying on some random person's prebuilt image. If you don't trust the scripts, read over them here on GitHub before you download them. Once you are comfortable with it, let's begin!

### Philosophy, AI, & Credits
Let's get a few things out of the way first:
* **The Code:** The scripts you are about to use were AI-generated using Gemini Pro (Feb-Mar 2026). That was ALL that was generated. I will not, nor EVER use AI in anything relating to generating executables or anything past basic, human-readable bash scripts (unless we all somehow find a universal approval of using it). This is to avoid hot water with exploits, backdoors, RATs, etc. Should this project magically take off, I am going human-first to make the system more polished!
* **The Blobs:** The firmware blobs are Qualcomm and Debian (massive shoutout to them!).
* **The Engine:** `pmbootstrap` is used in this installer to generate both the kernel and the boot image. They have a boot image that made debugging way easier, so a massive shoutout to the postmarketOS team as well!
* **License:** This project is under GPL 2.0 (just like what Linus Torvalds uses for the kernel). Upstream code and blobs fall under their respective licenses.

---

## System Requirements

* **Host OS:** Built and tested under WSL on Ubuntu 24.04.1 LTS (Microslop store) and native Ubuntu host/containers. I reset the container numerous times during testing to ensure the script acts as a true "paste and go" tool.
* **Storage Space:** **This requires a LOT of space (50GB on the higher end).** We are generating roughly 6 large images. (Looking into space optimizations down the road).
* **Firmware:** You will need Mobian installed on your phone to harvest firmware blobs (UNLESS you download the pre-provided firmware blobs from this repo).

---

## Installation Guide

### STEP 1: Preparation
1. Install WSL or run an Ubuntu Host/container (24.04 or later).
2. **Grab the firmware.** You can use the provided files, OR extract them yourself:
   * Flash Mobian Weekly SDM845 (Plasma-Mobile Recommended) to your device: https://images.mobian.org/qcom/weekly/ 
   * Boot into Mobian, connect to Wi-Fi, and enable SSH by running:
     `sudo apt update && sudo apt install openssh-server && sudo systemctl enable ssh`
   * *Note: The default Mobian password is `1234`.*
3. Open the AIO script in your browser and copy all of it. When you are ready, paste it into your host terminal.

### STEP 2: The Build Process & Quirks
The AIO script will auto-run the second you paste it. Follow the prompts until you hit Script 2. 

**[!] CRITICAL QUIRKS TO READ:**
* **The Blank Screen Bug:** We have a few rough quirks with booting kernels past 6.14 (blank screen and no boot image). To fix this, during the pmbootstrap setup, when the prompt asks for what channel to use (default is edge), **set it to `v25.06`**. Doing this gives us an older kernel that doesn't have the display quirk. (This will be addressed in the future when fixed upstream).
* **The Dummy Password:** When we run `pmbootstrap install`, it is going to ask for a user password. Enter whatever you want—we won't actually need it, but that is a quirk of our script hooking into their system.
* **Defaults:** If you are unsure about options other than the ones explicitly told to set, just press Enter.

### STEP 3: Execution Order
I tried to make this as debuggable as possible, so there are extra scripts. Run them in the following order (skipping the optional bits if you don't need them):

```text
[ The Build Scripts: Execution Order ]

  +-- deploy_workspace.sh
  |   (Run Once) The master generator. Run this first to spawn the script suite below.
  |
  +-- 1_preflight.sh
  |   (Step 1) Installs host PC dependencies and generates your build.env configuration.
  |
  +-- 2_pmos_setup.sh
  |   (Step 2) Initializes pmbootstrap, builds the mainline kernel, and clones the required UUIDs.
  |
  +-- 3_firmware_fetcher.sh
  |   (Step 3 - Optional) SSHs into a running Mobian phone to harvest proprietary audio/modem firmware.
  |
  +-- 4_the_transplant.sh
  |   (Step 4) Builds the base Ubuntu arm64 rootfs, injects the kernel/firmware, and installs the UI.
  |
  +-- 8_lomiri_hotfix.sh
  |   (Conditional) Run immediately AFTER Script 4 ONLY if you chose Lomiri and need to patch DBus/LightDM.
  |
  +-- 5_enter_chroot.sh
  |   (Optional Hacking Tool) Mounts and enters the unsealed Ubuntu folder as root for manual tweaking.
  |
  +-- 6_seal_rootfs.sh
  |   (Final Step) Packs the folder into the dual raw and sparse .img files for deployment.
  |
  +-- 7_kernel_menuconfig.sh
      (Optional Hacking Tool) Opens the kernel menuconfig or deviceinfo file to modify boot parameters.
	  
	  Flash this according to the method you chose to install
	  (Internal or MicroSD)
	  
	  (Fastboot) Flash using:
	  fastboot flash boot pmos_boot.img
	  fastboot flash system ubuntu_beryllium_boot_sparse.img
	  fastboot flash userdata ubuntu_beryllium_root_sparse.img
	  fastboot reboot (DO NOT REBOOT USING POWER BUTTON)
	  
	  Reboot and Enjoy!
	  
	  [ Generated Output Images ]
  |
  +-- pmos_boot.img ------------------------> Target: Internal /boot 
  |                                           (Mandatory ABL trigger for all methods)
  |
  +-- [ Raw Ext4 Images - For MicroSD Card Deployment ]
  |     |
  |     +-- ubuntu_beryllium_boot.img ------> Target: MicroSD Partition 1 (/dev/sdX1)
  |     |
  |     +-- ubuntu_beryllium_root.img ------> Target: MicroSD Partition 2 (/dev/sdX2)
  |
  +-- [ Sparse Images - For Internal Fastboot Hijack ]
        |
        +-- ubuntu_beryllium_boot_sparse.img -> Target: Internal system (fastboot flash system XXX_sparse.img)
        |
        +-- ubuntu_beryllium_root_sparse.img -> Target: Internal userdata (fastboot flash userdata XXX_sparse.img)# Ubuntu-Desktop-For-POCO-F1-beryllium
Welcome! Let's get a few things out of the way first.

The scripts you are about to use were AI Generated using Gemini Pro (Feb-Mar 2026) 
that was all that was generated, the firmware blobs are Qualcomm and Debian (so shoutout to them!)
pmbootstrap is used in this installer to generate both the kernel, and the boot image, as well as they
have a boot image that made debugging way easier,so massive shoutout to them as well!

i will not, nor EVER use ai in anything relating to generating executables and anything past basic bash scripts(unless we all somehow find a universal approval of using it)
for the sake of not getting in hot water for exploits, backdoors, RATS, etc. so we are gonna stick with human-readable for now!

should this project magically take off, im going human-first, make the system more polised that way!
(my thoughts and ideas may change as time goes on, so for now this is where i stand, and  this project
is under GPL 2.0 just like what Linus Torvald uses for the kernel, otherwise they fall under their
respective licenses!)

This was built under WSL on Ubuntu 24.04.1 LTS (Microslop store)

i reset the container numerous times during testing, as the intention is a paste and go script that does all the work 
(like pmbootstrap!) 

the intention was the ability to know what was installed, how it was done, and also the fact that its not some random persons prebuilt image,
because YOU built it, you can see the logs, you chose the UI and you installed the image no problem!

if you dont trust the scripts, then do a read-over here on github before you download it, and once your comfortable with it, run it!

THIS REQUIRE A LOT OF SPACE (50GB on the higher end) (looking into space optimizations down the road but we are about to generate like 6 images

YOU WILL NEED MOBIAN INSTALLED FOR FIRMWARE BLOBS (Unless you download the provided firmware blobs)

if that works for you, then lets begin!

STEP 1
	-install WSL or run on a Ubuntu Host/container (24.04 or later)*
	-grab the firmware provided OR flash Mobian Weekly SDM845 (Plasma-Mobile Recommended) and flash to your device: https://images.mobian.org/qcom/weekly/ 
	-enable SSH on mobian PASSWORD: 1234 (boot in, connect to wifi, run the following command: sudo apt update && sudo apt install openssh-server && sudo systemctl enable ssh) 
	-Open the AIO script in your browser, and copy all of it. when your ready, paste it into your Terminal.
STEP 2 
	-The AIO script will autorun the second you paste it, follow the commands until script 2
	-So we have a few rough quirks with booting kernels past 6.14 (blank screen and no boot image)
	 to fix, during the pmbootstrap setup, when the prompt asks for what channel (default is edge)
	 set it to v25.06 
	 doing this gives us an older kernel that doesnt have the quirk with the display (WILL BE ADRESSED IN THE FUTURE WHEN FIXED)
	-when we run pmbootstrap install, its going to ask for a user password, enter whatever, we wont need it, but thats a quirk of our script
	-if unsure about options other than the ones told to set, press enter.
STEP 3
	-i tried to make this as debuggable as possible, so there will be extra scripts
	Run them in the following order (skipping the Optional bits)
	[ The Build Scripts: Execution Order ]

  +-- deploy_workspace.sh
  |   (Run Once) The master generator. Run this first to spawn the script suite below.
  |
  +-- 1_preflight.sh
  |   (Step 1) Installs host PC dependencies and generates your build.env configuration.
  |
  +-- 2_pmos_setup.sh
  |   (Step 2) Initializes pmbootstrap, builds the mainline kernel, and clones the required UUIDs.
  |
  +-- 3_firmware_fetcher.sh
  |   (Step 3 - Optional) SSHs into a running Mobian phone to harvest proprietary audio/modem firmware.
  |
  +-- 4_the_transplant.sh
  |   (Step 4) Builds the base Ubuntu arm64 rootfs, injects the kernel/firmware, and installs the UI.
  |
  +-- 8_lomiri_hotfix.sh
  |   (Conditional) Run immediately AFTER Script 4 ONLY if you chose Lomiri and need to patch DBus/LightDM.
  |
  +-- 5_enter_chroot.sh
  |   (Optional Hacking Tool) Mounts and enters the unsealed Ubuntu folder as root for manual tweaking.
  |
  +-- 6_seal_rootfs.sh
  |   (Final Step) Packs the folder into the dual raw and sparse .img files for deployment.
  |
  +-- 7_kernel_menuconfig.sh
      (Optional Hacking Tool) Opens the kernel menuconfig or deviceinfo file to modify boot parameters.
	
	
[ Generated Output Images ]
  |
  +-- pmos_boot.img ------------------------> Target: Internal /boot 
  |                                           (Mandatory ABL trigger for all methods)
  |
  +-- [ Raw Ext4 Images - For MicroSD Card Deployment ]
  |     |
  |     +-- ubuntu_beryllium_boot.img ------> Target: MicroSD Partition 1 (/dev/sdX1)
  |     |
  |     +-- ubuntu_beryllium_root.img ------> Target: MicroSD Partition 2 (/dev/sdX2)
  |
  +-- [ Sparse Images - For Internal Fastboot Hijack ]
        |
        +-- ubuntu_beryllium_boot_sparse.img -> Target: Internal /system
        |
        +-- ubuntu_beryllium_root_sparse.img -> Target: Internal /userdata

	you can flash them with:
	fastboot flash boot pmos_boot.img
	fastboot flash system ubuntu_beryllium_boot_sparse.img
	fastboot flash userdata ubuntu_beryllium_root_sparse.img
	fastboot reboot <--(DO NOT PRESS THE POWER BUTTON, JUST WAIT! IT WILL TAKE A WHILE!)
	
	and Boom! you got a Ubuntu installed! i'm planning on building prebuilt images, but after i get the basics working!
