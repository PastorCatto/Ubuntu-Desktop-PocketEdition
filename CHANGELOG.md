# Mobuntu — Changelog

> RC7–RC10.1 assisted by Claude Sonnet 4.6 (Anthropic)
> Substantial progress and direction thanks to **arkadin91** — Ubuntu 26.04 Beta reference image, Kupfer lead, sdm845-mainline firmware discovery, OTA script logic, WirePlumber tuning config, pmaports device file discovery, and boot cmdline tuning.

---

## RC15 — "The Debos Update" (Current)

**Build System Overhaul**
- `2_kernel_prep.sh` and `3_rootfs_cooker.sh` retired — replaced by debos YAML recipe pipeline
- debos handles debootstrap, apt, overlays, chroot scripts, and packing in a reproducible VM
- `1_preflight.sh` now generates `run_build.sh` (debos invocation with all `-t` flags) instead of calling scripts directly
- `run_build.sh` is inspectable and re-runnable without going through preflight again
- `watchdog.sh` updated to wrap `run_build.sh` instead of scripts 2+3

**Recipe Architecture**
- `recipes/base.yaml` — debootstrap + apt + UI + user → `base-{release}.tar.gz` (cached)
- `recipes/qcom.yaml` — included by SDM845 device recipes: Qcom packages, firmware, services, hooks
- `recipes/l4t.yaml` — included by Switch device recipes: minimal L4T setup
- `recipes/devices/{codename}.yaml` — per-device: unpack base → overlay → kernel → pack
- `recipes/scripts/` — shell scripts called by debos `run:` actions
- `recipes/overlays/` — files copied verbatim into rootfs (51-qcom.conf, qcom-firmware hook, beryllium kernel hooks)

**Base Tarball Caching**
- Base tarball built once per release, reused by all device recipes
- Device builds skip debootstrap + apt entirely — 40-60% faster for multi-device builds
- Stale check: base rebuilds if `base.yaml` is newer than the tarball

**fakemachine Backend Detection**
- Auto-detects KVM → UML → QEMU in that order
- WSL2: select `none` for `--disable-fakemachine` (requires sudo, works correctly in WSL2)
- `qemu-system-x86` needed for QEMU backend on x86-64 hosts

**Boot Cmdline Fix (arkadin91)**
- New: `root=UUID=... earlycon console=tty0 console=ttyMSM0,115200 init=/sbin/init ro loglevel=7`
- `rw rootwait` → `ro`, `115200n8` → `115200`, `earlycon=qcom_geni,0x00A90000` → `earlycon`
- `init=/sbin/init` added, `loglevel=7` replaces quiet/splash toggle
- Boot verbosity prompt removed from `5_seal_rootfs.sh`

**verify_build.sh**
- Now unpacks device tarball to temp dir for inspection, cleans up after
- Base cache status check added

**Developer Masterkit**
- Boot Chain section updated for debos pipeline
- `run_build.sh` and `recipes/` added to file tree
- Base tarball cache management section added
- `FAKEMACHINE_BACKEND` shown in status bar

---

## RC14 — "The Quirks Update"

**DEVICE_QUIRKS System**
- `DEVICE_QUIRKS` string added to all device configs as source of truth for device-specific build behaviour
- `has_quirk()` helper available on host and inside chroot
- All Qualcomm-specific build steps gated behind `qcom_services` quirk
- Quirk flags: `dtb_append`, `qcom_services`, `firmware_source_local`, `firmware_source_online`, `l4t_bootfiles`

**Nintendo Switch Support**
- Four new device configs: V1 (icosa/T210), V2 (hoag/T210B01), Lite (vali), OLED (aula)
- New `BOOT_METHOD="l4t"` in `5_seal_rootfs.sh`: outputs kernel.lz4 + initrd.lz4 + DTB
- `lz4` added to host dependencies
- `KERNEL_REPO` placeholder — fill in switchroot L4T kernel .deb URL before building

**Bug Fixes**
- `xiaomi-beryllium-ebbg.conf` was copy-paste of Tianma — now correctly references EBBG DTB
- Phosh: `squeekboard` install non-fatal, falls back to `phosh-osk-stub`
- greetd `command` changed to full path `/usr/bin/phosh`
- `greeter` user groups expanded to `video,render,input,audio`
- `BOOT_PANEL_PICKER` gate — panel picker only shown when device requires it

**Verified Fixes (RC10.2.2 backport)**
- All `qemu-aarch64` → `qemu-aarch64-static` for Ubuntu 24.04 host compatibility
- `LOCAL_FW_ARCHIVE` deduplicated in `3_rootfs_cooker.sh`

**Developer Masterkit**
- Boot Chain section added (first in menu)
- `HIGHLIGHT_KEYS` — critical keys highlighted in `.conf` file previews
- Device family shown in services section
- New device wizard asks `qcom/l4t` and generates appropriate config
- Verifier generator is quirk-aware

---

## RC13 (Current Stable)

**Branding**
- Project renamed from Mobuntu Orange to Mobuntu
- All scripts updated to reflect new name

**Build Color System**
- Script 1 prompts for build color after Ubuntu release selection
- 10 colors with channel recommendations: orange (24.04 stable), pink (26.04 stable), yellow (edge/beta)
- Custom color option saves to build.env
- Hostname auto-generated as `mobuntu-{color}`
- `BUILD_COLOR` written to build.env

**Panel Selection**
- Panel (Tianma/EBBG) selected in script 1, saved to build.env as `BOOT_PANEL` and `BOOT_DTB_SELECTED`
- Script 5 reads from build.env instead of re-prompting

**QEMU Path Fix (Ubuntu 26.04 host)**
- `qemu-user-static` renamed in 26.04 — replaced with `qemu-user-binfmt-hwe`
- Static binary path updated in scripts 3 and 4

**Kernel Version Picker**
- Script 2 lists all available kernel series from Mobian pool when no pin set
- Auto-selects latest if no input given
- All index fetches switched from curl to wget for WSL2 compatibility

**Audio Stack (Critical Fix)**
- `hexagonrpcd` removed — confirmed cause of ADSP 60s watchdog crash on warm boot
- `alsa-state` and `alsa-restore` masked — conflict with SDM845 audio subsystem
- `51-qcom.conf` WirePlumber ALSA tuning sourced from `firmware/{brand}-{codename}/`
- pmaports beryllium device files added: `hexagonrpcd.confd`, `q6voiced.conf`, `81-libssc.rules`
- Script 3 fetches pmaports files from upstream if not present locally

**qcom-firmware Initramfs Hook**
- Sourced from `firmware/{brand}-{codename}/qcom-firmware`, falls back to project root
- Bakes ADSP/CDSP/GPU firmware into initramfs for early boot availability

**Service Ordering**
- systemd drop-in configs generated for `pd-mapper`, `rmtfs`, `hexagonrpcd`
- All drop-ins use `printf` to avoid CHROOT_EOF conflicts

**Ubuntu Desktop Minimal Easter Egg**
- GNOME accent color set to match `BUILD_COLOR` when Ubuntu Desktop Minimal selected
- Unmounted volumes hidden in Nautilus via dconf override

**Squeekboard**
- Replaced `phosh-osk-stub` and `lomiri-osk-stub` with `squeekboard`

**Display Manager Fix**
- Stale `display-manager.service` symlink removed before DM enable

**Auto-resize on First Boot**
- `mobuntu-resize.service` installed — one-shot `resize2fs` on first boot
- `/etc/mobuntu-resize-pending` flag removed after successful resize, device reboots

**Watchdog / Auto Build**
- `watchdog.sh` added — runs scripts 2 → 3 → verify → 5 unattended
- ZWJ (U+200D) signal character for clean-exit detection
- Auto-sudo toggle with explicit risk warning
- Timestamped log written per run

**Build Verification**
- `verify_build.sh` added — cross-checks build.env vs rootfs
- ZWJ signal on pass for watchdog integration

**Developer Masterkit**
- `mobuntu-developer-masterkit.py` added — Python curses TUI
- Regedit-style split layout: left pane file tree, right pane content/menu
- Sections: Device Config, APT, Kernel, Services, Audio, Verifier Generator, Staged Changes

---

## RC12 / Pre-Release 1.1

**Audio Investigation**
- Ran diagnostic against arkadin91 reference image (Ubuntu 26.04, April 9 build)
- Confirmed: no `hexagonrpcd` in reference — audio works via WirePlumber ALSA tuning alone
- `51-qcom.conf` sourced from arkadin91: S16LE, 48000Hz, period-size 4096, period-num 6, headroom 512
- `hexagonrpcd` confirmed as cause of ADSP 60s watchdog crash — removed
- `alsa-state` and `alsa-restore` identified as conflicting services

**Kernel Unpinning**
- `KERNEL_VERSION_PIN` can now be commented out — falls back to latest available

**Ubuntu 26.04 Host Support**
- QEMU package and binary path updated for 26.04 host environment
- `whiptail` and `dialog` added to preflight host dependencies

---

## RC11

**ARM64 Host Support**
- Script 1 detects host architecture via `uname -m`
- ARM64 hosts skip QEMU entirely
- `HOST_ARCH` and `HOST_IS_ARM64` written to build.env

**Kernel Version Pinning**
- `KERNEL_VERSION_PIN` added to device configs
- Beryllium configs pinned to `6.18.20`

**Ubuntu 26.04 Codename Fix**
- `devel` corrected to `resolute`
- Debootstrap symlink auto-created at preflight
- `resolute` set as default release
- 25.04 (plucky) removed — EOL

**UI Package Pinning**
- All UI installs use `-t` to pin to correct apt source

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
- Three-tier priority: local archive → git clone → OnePlus 6 fallback

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
