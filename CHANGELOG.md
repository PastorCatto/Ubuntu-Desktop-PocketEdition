# Mobuntu — Changelog

> RC7–RC16 assisted by Claude Sonnet 4.6 (Anthropic)
> Previous builds were assisted by Gemini 3.1 Pro (up to RC6)
> Substantial progress and direction thanks to **arkadin91** — Ubuntu 26.04 Beta reference image, Kupfer lead, sdm845-mainline firmware discovery, OTA script logic, WirePlumber tuning config, and pmaports device file discovery.

---

## RC16 — "The Switch Update" (Current)

**Nintendo Switch Support**
- `l4t.yaml` overhauled — adds theofficialgman's `l4t-debs` apt repository (`https://theofficialgman.github.io/l4t-debs/`) and installs core L4T BSP packages (`nvidia-l4t-core`, `nvidia-l4t-init`, `nvidia-l4t-firmware`, `nvidia-l4t-kernel`, `nvidia-l4t-kernel-dtbs`, `nvidia-l4t-xusb-firmware`, `nvidia-l4t-libvulkan`)
- `switch-v1.yaml` updated — new `l4t_repo` kernel method, kernel installed via BSP packages rather than direct URL download
- All four Switch device configs (`nvidia-switch-v1/v2/lite/oled.conf`) — `KERNEL_METHOD` changed from `custom_url` to `l4t_repo`, `DEVICE_UBUNTU_OVERRIDE="noble"` added
- `DEVICE_UBUNTU_OVERRIDE` — new device config field that forces a specific Ubuntu release for a device, independent of the user's `UBUNTU_RELEASE` selection; Switch locks to `noble` because `l4t-debs` does not yet support `resolute` (26.04)
- `1_preflight.sh` — `EFFECTIVE_RELEASE` logic: uses `DEVICE_UBUNTU_OVERRIDE` when set, otherwise `UBUNTU_RELEASE`; base and device tarballs named accordingly (`base-noble.tar.gz` for Switch)
- `joycond` and `nvpmodel` services enabled in `l4t.yaml` when packages present

**fastrpc Integration**
- `install-fastrpc-device.sh` wired into `qcom.yaml` as action 4 (between firmware staging and Qualcomm packages)
- `install-fastrpc-device.sh` — falls back to sourcing `build.env` when `DEVICE_BRAND`/`DEVICE_CODENAME` are empty (debos template substitution does not always survive the `environment:` block)
- DSP binary bundle (`firmware/xiaomi-beryllium/dsp.tar.gz`) staged from MIUI 12 V12.0.3.0 `dsp.img` — 65 files, 9.2 MB compressed
- `packages/fastrpc/` — `fastrpc-support`, `libfastrpc1`, `libfastrpc-dev` arm64 `.deb` files cross-compiled from source on x86-64 WSL2

**Bug Fixes**
- `stage-firmware-git.sh` — replaced `BASH_SOURCE[0]`-based path resolution with `$ARTIFACTDIR`; debos copies scripts to a temp location before execution so `SCRIPT_DIR` previously resolved to the debos temp dir rather than the Mobuntu repo root, causing the local `firmware.tar.gz` bundle to never be found
- `stage-firmware-git.sh` — removed interactive `read -p` prompt; debos `chroot: false` scripts run without a TTY causing the prompt to hang or fall through silently; local bundle now always applied non-interactively when present
- `install-fastrpc-device.sh` — added `build.env` fallback for `DEVICE_BRAND`/`DEVICE_CODENAME`; debos template substitution in `environment:` blocks does not reliably survive to the script, causing the DSP firmware path to resolve as `firmware//-/dsp.tar.gz`

**Documentation**
- `MOBUNTU-DOCS.md` — comprehensive RC15/RC16 documentation covering all scripts, recipes, overlays, device configs, build.env reference, known issues, and new device guide
- `ROADMAP.md` — release roadmap RC15 through post-1.0 including Chroot Edition concept and A21s status
- `Package Info.MD` — fastrpc package contents, DSP binary sources, Mobuntu tree layout, install order
- `How to Build.MD` — reproducible build guide for fastrpc arm64 packages

---

## RC15.1 LTS — "The Firmware Fix"

**Firmware Directory Fix**
- `overlays/qcom/` directory created — `qcom.yaml` referenced this overlay but it was never committed, causing `Action recipe failed at stage Verify: stat .../overlays/qcom: no such file or directory`
- Contents: `usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf` (S16LE/48kHz tuning) and `usr/share/initramfs-tools/hooks/qcom-firmware` (bundles Qcom firmware blobs into initramfs)
- `overlays/beryllium/` renamed to `overlays/beryllium-hooks/` — `beryllium.yaml` references `overlays/beryllium-hooks`, not `overlays/beryllium`
- `firmware/xiaomi-beryllium/firmware.tar.gz` — pre-cloned `gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium` bundle; staged by `stage-firmware-git.sh` as local bundle when git clone fails or is unavailable in the build environment

**Build Pipeline Fixes**
- `run_build.sh` — `cd "${SCRIPT_DIR}"` added at top of generated script; debos with `none` backend resolves overlay/script paths relative to `$(pwd)`, causing failures when script is invoked from outside the repo root
- `1_preflight.sh` — `systemd-container` added to host dependencies (`apt-get install`); provides `systemd-nspawn` required by debos
- All scripts — `dos2unix` applied; CRLF line endings from Windows archive extraction caused `exit status 127` on script execution inside debos

**Kernel Package Name Fix**
- `KERNEL_SERIES` updated from `"sdm845"` to `"6.18-sdm845"` in all four SDM845 device configs — Mobian dropped the unversioned `linux-image-sdm845` metapackage; correct package is now `linux-image-6.18-sdm845`
- `KERNEL_VERSION_PIN` cleared in beryllium configs — old pin format incompatible with new versioned package naming

**Designation**
- RC15.1 designated as LTS — Nintendo Switch configs absent, Poco F1 pipeline confirmed building to tarball stage; suitable as a stable base for SDM845-only deployments

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

## RC13 

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


*Mobuntu — You don't realise how good it is, until its gone* 
