# Mobuntu — Changelog

> RC7–RC10.1 assisted by Claude Sonnet 4.6 (Anthropic)
> Substantial progress and direction thanks to **arkadin91** — Ubuntu 26.04 Beta reference image, Kupfer lead, sdm845-mainline firmware discovery, OTA script logic, WirePlumber tuning config, and pmaports device file discovery.

---

## RC13 (Current)

**Branding**
- Project renamed from Mobuntu Orange to Mobuntu
- All scripts updated to reflect new name

**Build Color System**
- Script 1 now prompts for a build color after Ubuntu release selection
- 10 colors available with channel recommendations in brackets: orange (24.04 stable), pink (26.04 stable), yellow (edge/beta)
- Custom color option saves to build.env without conflict checking
- Hostname auto-generated as `mobuntu-{color}` from selected color
- `BUILD_COLOR` written to build.env alongside hostname

**Panel Selection**
- Panel (Tianma/EBBG) now selected in script 1 and saved to build.env as `BOOT_PANEL` and `BOOT_DTB_SELECTED`
- Script 5 reads from build.env instead of re-prompting

**QEMU Path Fix (Ubuntu 26.04 host)**
- `qemu-user-static` package renamed in 26.04 — replaced with `qemu-user-binfmt-hwe`
- Static binary path changed from `/usr/bin/qemu-aarch64-static` to `/usr/bin/qemu-aarch64`
- Scripts 3 and 4 updated accordingly

**Kernel Version Picker**
- Script 2 now lists all available kernel series from Mobian pool when no pin is set
- Displays available series with suggested `KERNEL_VERSION_PIN` value for each
- Auto-selects latest if no input given
- All index fetches switched from curl to wget for WSL2 host compatibility

**Audio Stack (Critical Fix)**
- `hexagonrpcd` removed, then re-added with correct systemd ordering drop-ins
- Root cause of ADSP 60s watchdog crash identified as service startup race
- `alsa-state` and `alsa-restore` masked — conflict with SDM845 audio subsystem
- `51-qcom.conf` WirePlumber ALSA tuning config sourced from `firmware/{brand}-{codename}/` folder
- pmaports beryllium device files added: `hexagonrpcd.confd`, `q6voiced.conf`, `81-libssc.rules`
- Script 3 fetches pmaports files from upstream if not present locally, saves source URL to log
- `hexagonrpcd` service ordering: `qrtr-ns` -> `rmtfs` -> `pd-mapper` -> `hexagonrpcd`

**qcom-firmware Initramfs Hook**
- `qcom-firmware` initramfs hook sourced from `firmware/{brand}-{codename}/qcom-firmware`
- Falls back to project root if device-specific file not found
- Bakes ADSP/CDSP/GPU firmware directly into initramfs for early boot availability
- Hook install inside chroot is conditional — skips cleanly if not staged

**Service Ordering**
- systemd drop-in configs generated for `pd-mapper`, `rmtfs`, `hexagonrpcd`
- All drop-ins use `printf` instead of heredocs to avoid CHROOT_EOF conflicts

**Ubuntu Desktop Minimal Easter Egg**
- When Ubuntu Desktop Minimal is selected, GNOME accent color is set to match `BUILD_COLOR`
- Unmounted volumes hidden in Nautilus via dconf override
- Written to `/etc/dconf/db/local.d/01-mobuntu-theme`

**Squeekboard**
- `phosh-osk-stub` and `lomiri-osk-stub` replaced with `squeekboard` (available in Ubuntu repos)
- Phosh no longer uses `-t staging` flag — pulled directly from Ubuntu repos

**Display Manager Fix**
- Stale `display-manager.service` symlink removed before DM enable to prevent conflicts

**Auto-resize on First Boot**
- Script 5 prompts to enable first-boot auto-resize alongside verbosity selection
- Installs `mobuntu-resize.service` — one-shot, runs `resize2fs` using `DEVICE_IMAGE_LABEL`
- Creates `/etc/mobuntu-resize-pending` flag, deleted after successful resize
- Device reboots automatically after resize completes

**Watchdog / Auto Build**
- `watchdog.sh` added — runs scripts 2 -> 3 -> verify -> 5 unattended
- Hidden ZWJ (U+200D) signal character appended to success messages in scripts 2, 3, and verifier
- Watchdog detects signal to confirm clean exit at each stage
- Auto-sudo toggle with explicit risk warning — recommended for WSL2/VM use only
- Output images tagged with `_autobuild` suffix on success
- Timestamped log written per run

**Build Verification**
- `verify_build.sh` added — standalone cross-check of build.env vs rootfs
- Checks: build.env completeness, device config, hostname, packages, services, ordering drop-ins, WirePlumber config, kernel, firmware, ALSA masking, initramfs hook, autoresize service, build color
- Package checks use direct dpkg status file reads — no chroot required, works from x86 host
- Hidden ZWJ signal on pass for watchdog integration

**Developer Masterkit**
- `mobuntu-developer-masterkit.py` added — Python curses TUI
- Regedit-style split layout: left pane file tree, right pane content/menu
- Sections: Device Config, APT, Kernel, Services, Audio, Verifier Generator, Staged Changes
- Staged changes reviewed and applied in one shot
- Generates device-specific verifier scripts
- Generates `51-qcom.conf` WirePlumber configs with custom ALSA parameters
- Generates systemd drop-in ordering configs
- ESC returns to main menu, ESC x2 prompts quit
- Requires `dialog` and Python 3 (installed by script 1 preflight)

**Firmware Folder Structure**
- Device-specific files now live in `firmware/{brand}-{codename}/`
- Includes: `firmware.tar.gz`, `qcom-firmware`, `51-qcom.conf`, `hexagonrpcd.confd`, `q6voiced.conf`, `81-libssc.rules`
- Script 3 looks in firmware folder first, falls back to curl from upstream sources

**Noble (24.04) Support Briefly Restored — Reverted**
- `hexagonrpcd` removal briefly made 24.04 viable again
- Noble support restored with extended firmware bundle requirement and warning in script 1
- Subsequently confirmed that `hexagonrpcd` is required for reliable audio — noble support reverted
- Noble (24.04) will be formally sunset in RC14 as `hexagonrpcd` 0.4.0 is not available in noble repos

**Version Markers**
- RC version added to header comments across all scripts

---

## RC12 / Pre-Release 1.1

**Audio Investigation**
- Ran diagnostic script against arkadin91's reference image (Ubuntu 26.04, April 9 build)
- Confirmed identical kernel (6.18.20-1), same firmware — difference is userspace only
- Key finding: reference image has no `hexagonrpcd` — audio works via WirePlumber ALSA tuning alone
- `51-qcom.conf` sourced from arkadin91's image: S16LE, 48000Hz, period-size 4096, period-num 6, headroom 512
- `hexagonrpcd` confirmed as cause of ADSP 60s watchdog crash on warm boot — removed
- `alsa-state` and `alsa-restore` identified as conflicting services
- ADSP fastrpc missing `memory-region` in DTB confirmed via `/sys/firmware/fdt` inspection — cosmetic warning only, not root cause

**Kernel Unpinning**
- `KERNEL_VERSION_PIN` can now be commented out in device config
- Script 2 falls back to latest available series when pin is absent

**Ubuntu 26.04 Host Support**
- QEMU package and binary path updated for 26.04 host environment
- `whiptail` and `dialog` added to preflight host dependencies

---

## RC11

**ARM64 Host Support**
- Script 1 detects host architecture via `uname -m` at startup
- ARM64 hosts skip QEMU entirely
- x86-64 hosts retain full QEMU + binfmt path
- Script 3 debootstrap and chroot execution branch by host arch
- Script 4 updated with same arch-aware logic
- `HOST_ARCH` and `HOST_IS_ARM64` written to build.env

**Kernel Version Pinning**
- Added `KERNEL_VERSION_PIN` to device configs
- Script 2 fetches exact version if pin set, latest if not
- Beryllium configs pinned to `6.18.20`

**Ubuntu 26.04 Codename Fix**
- Corrected `devel` to `resolute`
- Debootstrap symlink auto-created at preflight
- `resolute` set as default release
- 25.04 (plucky) removed — EOL

**UI Package Pinning**
- All UI installs use `-t` to pin to correct apt source
- Phosh/phrog/greetd pinned to `-t staging`
- Ubuntu UI packages pinned to `-t "$UBUNTU_RELEASE"`

**Chroot Script Rewrite**
- Split two-stage heredoc: `INJECT_EOF` for variables, `CHROOT_EOF` for build logic
- Eliminates nested heredoc expansion bugs

**Bug Fixes**
- binfmt hex magic byte corruption fixed
- Script 4 enter chroot rewritten
- Single-quote parse error in binfmt registration fixed

---

## RC10.2 / Pre-Release 1.0

**Audio — PipeWire Restored**
- Reverted from PulseAudio back to PipeWire
- `pipewire pipewire-pulse wireplumber` restored to base install

**UCM2 Maps**
- `alsa-ucm-conf` pinned to Ubuntu release
- UCM2 maps bundled into `firmware.tar.gz`
- Firmware archive re-applied post-apt

**Hardware Status (Confirmed)**
- Touch, Sound, WiFi, Bluetooth working
- Modem disabled — crashes WiFi/BT when active

---

## RC10.1

**UI Picker**
- Script 1 prompts for desktop environment
- Each UI sets correct display manager automatically
- Lomiri shows warning and confirmation

**Firmware Archive System**
- `firmware/<brand>-<codename>/` directory structure
- Three-tier priority: local archive -> git clone -> OnePlus 6 fallback

**Ubuntu 26.04 Support**
- `devel` (26.04) added with experimental warning
- `quill` placeholder added, falls back to noble

**Bug Fixes**
- `/boot/efi` fstab entry removed — caused emergency mode
- `cp: cannot overwrite non-directory` fixed
- `curl: command not found` in chroot fixed
- Nested heredoc errors fixed with printf

---

## RC10

**Device Config System**
- Introduced `devices/*.conf` device profile system
- Added configs: beryllium (Tianma/EBBG), enchilada, fajita
- New device requires only a new `.conf` file

**Firmware**
- Replaced droid-juicer with direct git clone of sdm845-mainline firmware repo
- OnePlus 6 fallback added

**Boot Method Abstraction**
- Script 5 branches on `BOOT_METHOD`
- mkbootimg implemented, uboot and uefi as placeholders

**Script 1 Auto-Run**
- Script 1 optionally chains into scripts 2 and 3

---

## RC9

**Phrog / greetd**
- Replaced GDM3 with greetd + phrog
- `greeter` user created, config written

**Kernel Hook (OTA-safe boot.img)**
- `/etc/kernel/postinst.d/zz-qcom-bootimg` installed
- `/etc/initramfs/post-update.d/bootimg` installed
- Filters on `*sdm845*` kernel version

**qbootctl**
- Installed in rootfs for OTA-style slot updates

---

## RC8

**Build System**
- `build.env` used to pass config between scripts
- osm0sis mkbootimg fork confirmed required
- `-Werror` fix applied to libmincrypt Makefile

**Kernel**
- Dynamic fetch from `repo.mobian.org` pool
- DTB confirmed appended to kernel binary

**RootFS**
- debootstrap two-stage with QEMU arm64 binfmt
- WSL2 binfmt injection fallback
- `fallocate` + `mkfs.ext4` + `rsync` image build

**Bug Fixes**
- `return 1` with `set -e` fixed
- `basename: missing operand` fixed
- binfmt not active on WSL2 fixed
- `Exec format error` in chroot fixed
