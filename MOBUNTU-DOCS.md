# Mobuntu RC15 Documentation

**RC16 "The Switch Update"** | RC15.1 LTS "The Firmware Fix"  
Ubuntu Linux for SDM845 phones and Nintendo Switch  
Discord: https://discord.gg/RZV2HveyBg

---

## Table of Contents

1. [Overview](#overview)
2. [Supported Devices](#supported-devices)
3. [Build Pipeline](#build-pipeline)
4. [Quick Start](#quick-start)
5. [Scripts](#scripts)
   - [1_preflight.sh](#1_preflightsh)
   - [watchdog.sh](#watchdogsh)
   - [verify_build.sh](#verify_buildsh)
   - [5_seal_rootfs.sh](#5_seal_rootfssh)
   - [4_enter_chroot.sh](#4_enter_chrootsh)
6. [Debos Recipes](#debos-recipes)
   - [base.yaml](#baseyaml)
   - [qcom.yaml](#qcomyaml)
   - [l4t.yaml](#l4tyaml)
   - [devices/beryllium.yaml](#devicesberylliumyaml)
   - [devices/switch-v1.yaml](#devicesswitch-v1yaml)
7. [Recipe Scripts](#recipe-scripts)
   - [stage-firmware-git.sh](#stage-firmware-gitsh)
   - [install-fastrpc-device.sh](#install-fastrpc-devicesh)
8. [Overlays](#overlays)
   - [zz-qcom-bootimg](#zz-qcom-bootimg)
   - [bootimg](#bootimg)
   - [51-qcom.conf](#51-qcomconf)
9. [Device Configs](#device-configs)
   - [Config Schema](#config-schema)
   - [xiaomi-beryllium-tianma.conf](#xiaomi-beryllium-tianmaconf)
   - [xiaomi-beryllium-ebbg.conf](#xiaomi-beryllium-ebbgconf)
   - [oneplus-enchilada.conf](#oneplus-enchiladadconf)
   - [nvidia-switch-v1.conf](#nvidia-switch-v1conf)
10. [build.env Reference](#buildenv-reference)
11. [Known Issues](#known-issues)
12. [Adding a New Device](#adding-a-new-device)

---

## Overview

Mobuntu is a pure-debootstrap Ubuntu image builder for ARM64 devices. It uses [debos](https://github.com/go-debos/debos) to construct rootfs tarballs inside a sandboxed environment, then seals them into flashable images on the host.

The design has one hard rule: **Ubuntu packages are resolved before Mobian packages are introduced.**

**Current releases:** RC16 "The Switch Update" (Nintendo Switch configs, fastrpc integration, firmware staging fixes). RC15.1 LTS "The Firmware Fix" is the stable SDM845-only base — recommended for Poco F1 builds until RC16 confirms Switch booting. This prevents the Mobian staging repository from conflicting with Ubuntu's UI packages — a regression observed with `qcom-support-common` and GTK3 in early 2026 that broke `ubuntu-desktop-minimal` builds.

There is no postmarketOS, pmbootstrap, or any other intermediate distribution. The chain is:

```
debootstrap  →  debos base recipe  →  debos device recipe  →  raw ext4 image
```

---

## Supported Devices

| Device | Config | SoC | Boot method | Status |
|--------|--------|-----|-------------|--------|
| Xiaomi Poco F1 (Tianma) | `xiaomi-beryllium-tianma.conf` | SDM845 | mkbootimg | ✅ Working |
| Xiaomi Poco F1 (EBBG) | `xiaomi-beryllium-ebbg.conf` | SDM845 | mkbootimg | ✅ Working |
| OnePlus 6 | `oneplus-enchilada.conf` | SDM845 | mkbootimg | 🧪 Untested |
| OnePlus 6T | `oneplus-fajita.conf` | SDM845 | mkbootimg | 🧪 Untested |
| Switch V1 (Erista) | `nvidia-switch-v1.conf` | T210 | L4T | 🧪 RC16 — l4t_repo method, noble base |
| Switch V2 (Mariko) | `nvidia-switch-v2.conf` | T210B01 | L4T | 🧪 RC16 — l4t_repo method, noble base |
| Switch Lite | `nvidia-switch-lite.conf` | T210 | L4T | 🧪 RC16 — l4t_repo method, noble base |
| Switch OLED | `nvidia-switch-oled.conf` | T210B01 | L4T | 🧪 RC16 — l4t_repo method, noble base |

**Beryllium hardware status:**

| Component | Status | Notes |
|-----------|--------|-------|
| CPU / GPU | ✅ | Adreno 630, firmware fetched from kernel.org |
| Touch | ✅ | |
| WiFi / BT | ✅ | |
| Audio | ✅ | PipeWire + WirePlumber, UCM profiles from alsa-ucm-conf |
| Display | ✅ | Tianma and EBBG panels, separate DTBs |
| Sensors (SLPI) | ⚠️ | Crash-loops every ~40 s — cosmetic, see [Known Issues](#known-issues) |
| Cellular | ❌ | Crashes WiFi+BT when enabled — do not enable ModemManager |
| Camera | ❌ | Out of scope |

---

## Build Pipeline

```
1_preflight.sh
    │
    ├─ Detects host arch + fakemachine backend
    ├─ Installs host dependencies (debos, mkbootimg, debootstrap)
    ├─ Prompts: device, release, UI, username, image size
    ├─ Writes build.env
    └─ Generates run_build.sh
           │
           ▼
    run_build.sh  (or watchdog.sh for unattended)
           │
           ├─ [if stale] debos base.yaml
           │       debootstrap → Ubuntu repos → UI → user → pack base-<release>.tar.gz
           │
           └─ debos devices/<codename>.yaml
                   unpack base-<release>.tar.gz
                   recipe: qcom.yaml  (SDM845) or  l4t.yaml  (Switch)
                       ├─ Add Mobian repo
                       ├─ Overlay qcom configs
                       ├─ stage-firmware-git.sh  (chroot: false)
                       ├─ Install Qcom packages + services
                       └─ Mask ALSA, set service ordering
                   Overlay beryllium hooks
                   Install kernel (mobian or custom_url)
                   Build mkbootimg natively (ARM64 in-chroot)
                   update-initramfs
                   Set hostname
                   apt-get clean
                   pack <label>-<release>.tar.gz
                           │
                           ▼
                    verify_build.sh
                           │
                           ▼
                    5_seal_rootfs.sh
                           │
                           ├─ Unpack device tarball
                           ├─ Generate UUID, write /etc/fstab + /etc/kernel/cmdline
                           ├─ Optionally install autoresize service
                           ├─ [mkbootimg] Regenerate initramfs, run mkbootimg
                           ├─ [l4t] Compress kernel + initrd as lz4
                           ├─ fallocate + mkfs.ext4 + rsync rootfs
                           ├─ img2simg sparse conversion
                           └─ Print fastboot flash commands
```

The base tarball is **cached** — `run_build.sh` only rebuilds it if `base.yaml` is newer than the existing tarball. Device builds always run fresh.

---

## Quick Start

```bash
# 1. Clone repo, enter directory
git clone <repo> && cd <repo>

# 2. Run preflight (installs deps, generates run_build.sh)
bash 1_preflight.sh

# 3. Build (or use watchdog for unattended)
bash run_build.sh

# 4. Verify output tarball
bash verify_build.sh

# 5. Seal into flashable image
bash 5_seal_rootfs.sh

# 6. Flash (beryllium example)
fastboot flash boot   mobuntu-beryllium_resolute_boot.img
fastboot flash system mobuntu-beryllium_resolute_root_sparse.img
fastboot reboot
```

For unattended builds, answer Yes to "Enable watchdog?" in preflight, then:

```bash
bash watchdog.sh
```

---

## Scripts

### 1_preflight.sh

**Purpose:** Interactive setup wizard. Detects the host environment, installs build dependencies, collects build configuration, and generates `run_build.sh`.

**Must be run first.** Every other script reads `build.env` which this script produces.

#### Steps

**Step 1 — Host architecture detection**

Sets `HOST_ARCH` (`x86_64` or `aarch64`) and `HOST_IS_ARM64`. This is passed into `build.env` and used by `5_seal_rootfs.sh` to decide whether to use QEMU for initramfs regeneration.

**Step 2 — Fakemachine backend detection**

Debos uses [fakemachine](https://github.com/go-debos/fakemachine) to sandbox builds. Three backends are tried in priority order:

| Backend | Detection | Build time | Notes |
|---------|-----------|------------|-------|
| `kvm` | `/dev/kvm` readable+writable | ~9 min | Fastest. WSL2 with KVM enabled. |
| `uml` | `linux` binary in PATH | ~18 min | User Mode Linux. `apt install user-mode-linux`. |
| `qemu` | fallback | ~2.5 h | Software emulation. Avoid if possible. |
| `none` | manual override | varies | `--disable-fakemachine`. Requires root. Not sandboxed. |

The user can override the detected backend at the prompt.

**Step 3 — Host dependency installation**

Installs via `apt-get`:
- `debootstrap`, `e2fsprogs`, `curl`, `wget`, `git`, `rsync`
- `dosfstools`, `uuid-runtime`, `android-sdk-libsparse-utils`
- `lz4`, `qemu-system-aarch64`, `qemu-user-static`, `binfmt-support`
- `golang`, `libglib2.0-dev`, `libostree-dev` (for debos build)

Builds **debos from source** via `go install` if not present. The binary is installed to `/usr/local/bin/debos`.

Builds **mkbootimg from source** (osm0sis fork) if not present. The `-Werror` flag is patched out before compilation to avoid compiler version failures. Binary installed to `/usr/local/bin/mkbootimg`.

Creates the debootstrap symlink for Ubuntu 26.04:
```bash
ln -sf /usr/share/debootstrap/scripts/gutsy /usr/share/debootstrap/scripts/resolute
```
This is required because debootstrap does not ship a `resolute` script natively.

**Step 4 — Device selection**

Reads all `devices/*.conf` files, sources each to get `DEVICE_NAME`, and presents a numbered menu. The selected conf is sourced into the current shell so all device variables are available for subsequent steps.

**Step 5 — Build configuration prompts**

| Prompt | Variable | Default | Notes |
|--------|----------|---------|-------|
| Username | `USERNAME` | `phone` | Created in rootfs with `NOPASSWD` sudo |
| Password | `PASSWORD` | `1234` | Set via `chpasswd` |
| Ubuntu release | `UBUNTU_RELEASE` | `resolute` | noble/oracular/resolute |
| Build color | `BUILD_COLOR` | `yellow` | Sets `DEVICE_HOSTNAME=mobuntu-<color>`, used for GNOME accent |
| Panel picker | `BOOT_PANEL`, `BOOT_DTB_SELECTED` | `tianma` | Only shown if `BOOT_PANEL_PICKER=true` in device conf |
| Image size | `IMAGE_SIZE` | `12` | Minimum 8 GB, enforced |
| Extra packages | `EXTRA_PKG` | _(empty)_ | Space-separated, installed in base recipe |
| UI | `UI_NAME`, `UI_DM` | `phosh`/`greetd` | See table below |
| Watchdog | `WATCHDOG_ENABLED` | `false` | See [watchdog.sh](#watchdogsh) |
| Auto-sudo | `AUTO_SUDO` | `false` | Only offered if watchdog enabled |

UI options:

| Choice | `UI_NAME` | `UI_DM` |
|--------|-----------|---------|
| Phosh (default) | `phosh` | `greetd` |
| Ubuntu Desktop | `ubuntu-desktop-minimal` | `gdm3` |
| Unity | `unity` | `lightdm` |
| Plasma Desktop | `plasma-desktop` | `sddm` |
| Plasma Mobile | `plasma-mobile` | `sddm` |
| Lomiri | `lomiri` | `greetd` |

**Step 6 — build.env**

Writes all collected and sourced variables to `build.env` in the working directory. All subsequent scripts source this file. Do not edit it manually; re-run `1_preflight.sh` to regenerate.

**Step 6b — EFFECTIVE_RELEASE**

If the sourced device config declares `DEVICE_UBUNTU_OVERRIDE` (e.g. Switch devices set `"noble"` because `l4t-debs` does not yet support `resolute`), preflight uses that value as `EFFECTIVE_RELEASE` instead of `UBUNTU_RELEASE`. Base and device tarball names are derived from `EFFECTIVE_RELEASE`, so a Switch build on a `resolute` host will look for `base-noble.tar.gz` and produce `mobuntu-icosa-noble.tar.gz`.

**Step 7 — Recipe path resolution**

Computes:
- `BASE_TARBALL=base-<UBUNTU_RELEASE>.tar.gz`
- `DEVICE_TARBALL=<DEVICE_IMAGE_LABEL>-<UBUNTU_RELEASE>.tar.gz`
- `RECIPE_DEVICE=recipes/devices/<DEVICE_CODENAME>.yaml`

Warns if no device recipe exists for the selected device.

**Step 8 — run_build.sh generation**

Generates `run_build.sh` containing hardcoded `debos` invocations with all `-t KEY:VALUE` template flags. The base step is wrapped in a staleness check (skipped if `base-<release>.tar.gz` is newer than `base.yaml`). The ZWJ character (U+200D) is appended to the final echo line — this serves as the clean-exit signal read by `watchdog.sh`.

**Step 9 — Watchdog option**

If enabled, appends `WATCHDOG_ENABLED=true` and optionally `AUTO_SUDO=true` to `build.env`. See [watchdog.sh](#watchdogsh) for how these are consumed.

**Step 10 — Optional auto-run**

Offers to run `run_build.sh` immediately after setup.

---

### watchdog.sh

**Purpose:** Unattended build runner. Wraps `run_build.sh` with retry logic, a clean-exit signal detector, and automatic chaining to `verify_build.sh` → `5_seal_rootfs.sh`.

**Requires:** `WATCHDOG_ENABLED=true` in `build.env` (set by `1_preflight.sh`).

#### Clean-exit Signal

`run_build.sh` ends its final `echo` with a Zero Width Joiner (U+200D, `\xe2\x80\x8d`). `watchdog.sh` searches the tee'd log for this byte sequence using `grep -q`. A process that exits 0 but lacks the ZWJ is treated as a failure and retried — this catches debos exits that succeed at the shell level but short-circuit early (e.g. stale tarball skip without a full build).

#### Auto-sudo Keepalive

When `AUTO_SUDO=true`, a background subshell runs `sudo -v` every 50 seconds to prevent the sudo timestamp from expiring during long builds. The subshell PID is tracked and killed via `trap ... EXIT`.

#### Retry Logic

| Variable | Value | Notes |
|----------|-------|-------|
| `MAX_RETRIES` | 3 | Hardcoded |
| Retry delay | 10 s | Between attempts |

On each attempt, `run_build.sh` is run and its output tee'd to `watchdog-<timestamp>.log`. If the build exits 0 and the ZWJ signal is found, verification and sealing run automatically. If either fails, the watchdog exits 1 without retrying.

#### Log File

Named `watchdog-YYYYMMDD-HHMMSS.log` in the script directory. Contains the full output of all build, verify, and seal steps.

---

### verify_build.sh

**Purpose:** Validates the debos output tarball before sealing. Runs automatically via `watchdog.sh`, or manually after `run_build.sh`.

**Requires:** `build.env` in the current directory and the device tarball produced by `run_build.sh`.

#### Output

Each check emits one of:
- `[PASS]` — increments `PASS` counter
- `[FAIL]` — increments `FAIL` counter, non-zero exit at end
- `[WARN]` — increments `WARN` counter, does not fail

Exit code is 0 only if `FAIL == 0`.

#### Check Categories

**build.env validation**

All of the following variables must be non-empty: `UBUNTU_RELEASE`, `DEVICE_NAME`, `DEVICE_CODENAME`, `DEVICE_IMAGE_LABEL`, `DEVICE_HOSTNAME`, `BUILD_COLOR`, `USERNAME`, `KERNEL_METHOD`, `BOOT_METHOD`, `FIRMWARE_METHOD`, `UI_NAME`, `UI_DM`, `FAKEMACHINE_BACKEND`.

**Tarball presence and size**

- Base tarball: warn if absent (device build can proceed without it if already unpacked)
- Device tarball: fail if absent
- Size sanity: warn if device tarball is smaller than 200 MB (indicates a truncated or failed build)

**Rootfs inspection**

The tarball is unpacked to a temporary directory under `/tmp/mobuntu-verify-XXXX`. All subsequent checks inspect this unpacked tree. The temp directory is deleted on exit.

**Hostname** — `WARN` if `DEVICE_HOSTNAME` does not match `/etc/hostname`.

**Qualcomm checks** (only if `DEVICE_QUIRKS` contains `qcom_services`):

| Check | Pass condition |
|-------|---------------|
| Packages | `qrtr-tools`, `rmtfs`, `pd-mapper`, `tqftpserv`, `pipewire`, `wireplumber`, `alsa-ucm-conf` present in dpkg status |
| hexagonrpcd absent | Package must NOT appear in dpkg status |
| Services enabled | Symlinks in `multi-user.target.wants/` for `qrtr-ns`, `rmtfs`, `pd-mapper`, `tqftpserv` |
| Service ordering | Drop-in files at `etc/systemd/system/pd-mapper.service.d/ordering.conf` and `rmtfs.service.d/ordering.conf` |
| WirePlumber config | `usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf` present |
| ALSA masking | `alsa-state.service` and `alsa-restore.service` symlinked to `/dev/null` |
| initramfs hook | `usr/share/initramfs-tools/hooks/qcom-firmware` present and executable |
| Firmware blobs | `adsp.mbn`, `cdsp.mbn`, `venus.mbn` found anywhere under `lib/firmware` |

**Kernel** — Searches for `vmlinuz-*sdm845*` (Qcom) or `vmlinuz-*` (Switch). Fails if absent. Checks initrd exists.

**Autoresize** — Warns if `mobuntu-resize.service` is absent or if the pending flag file is missing.

**Build artifacts** — Warns if `run_build.sh` or `build.env` are missing from the working directory.

---

### 5_seal_rootfs.sh

**Purpose:** Converts the debos device tarball into a flashable image. Assigns a UUID, builds boot assets, creates and populates an ext4 image, converts to sparse format, and prints flash instructions.

**Requires:** `build.env` and the device tarball. Run after `verify_build.sh` passes.

#### Steps

**Step 0 — Unpack tarball**

Unpacks `<DEVICE_IMAGE_LABEL>-<UBUNTU_RELEASE>.tar.gz` into `mobuntu-<codename>-<release>-seal/`. This directory is the working rootfs for all subsequent steps and is deleted at the end.

**Step 1 — UUID generation**

Generates a random UUID with `uuidgen`. Written to `build.env` as `ROOTFS_UUID`. Used as the ext4 filesystem UUID, the `root=UUID=...` kernel parameter, and the fstab entry — all three must match for the system to boot.

**Step 2 — DTB selection**

For devices with `BOOT_PANEL_PICKER=true` (no current device uses this; it was used in an earlier EBBG/Tianma dual-config design), re-prompts for panel choice. Otherwise uses `BOOT_DTB_SELECTED` from `build.env` which was set during preflight. The selected DTB name is written to `<rootfs>/etc/kernel/boot_dtb` for the OTA hook to read later.

**Step 3 — Autoresize prompt**

Offers to install a first-boot resize service. Defaults to yes. When enabled:
- Writes `<rootfs>/etc/systemd/system/mobuntu-resize.service` — a oneshot that runs `resize2fs` on the partition with label `DEVICE_IMAGE_LABEL`, removes the pending flag, and reboots
- Creates the symlink in `multi-user.target.wants/`
- Creates `/etc/mobuntu-resize-pending` as the trigger flag

**Step 4 — cmdline and fstab**

Writes to the rootfs:

```
/etc/kernel/cmdline:
root=UUID=<uuid> earlycon console=tty0 console=ttyMSM0,115200 init=/sbin/init ro loglevel=7

/etc/fstab:
UUID=<uuid>  /  ext4  errors=remount-ro  0  1
```

These are the only references to the UUID in the rootfs. The UUID in the ext4 superblock (set at `mkfs.ext4` time) must match.

**Step 5 — Boot image (method-specific)**

*mkbootimg path (SDM845):*

1. Regenerates initramfs via `update-initramfs -u -k all`. On an x86-64 host this runs under `qemu-aarch64-static` inside the chroot.
2. Checks initrd for critical firmware blobs (`a630_sqe.fw`, `a630_gmu.bin`, `adsp.mbn`, `cdsp.mbn`) and warns if absent — non-fatal.
3. Locates `vmlinuz-*sdm845*`, `initrd.img-*sdm845*`, and the selected DTB.
4. If `BOOT_DTB_APPEND=true`, concatenates the kernel and DTB into a temp file before passing to mkbootimg. This is required for SDM845 — the bootloader reads the appended DTB.
5. Calls `mkbootimg` with the exact offsets from `build.env`:
   - `--pagesize 4096`
   - `--base 0x00000000`
   - `--kernel_offset 0x00008000`
   - `--ramdisk_offset 0x01000000`
   - `--tags_offset 0x00000100`
6. Output: `<DEVICE_IMAGE_LABEL>_<UBUNTU_RELEASE>_boot.img`

*L4T path (Switch):*

1. Compresses kernel with `lz4 -B6 --content-size`.
2. Compresses initrd with `lz4 -B6 --content-size`.
3. Copies the selected DTB.
4. Output: `kernel.lz4`, `initrd.lz4`, `<dtb>.dtb` — all prefixed with the image label.

**Step 6 — RootFS image**

```bash
fallocate -l <IMAGE_SIZE>G <ROOT_IMG>
mkfs.ext4 -U <BUILD_UUID> -L <DEVICE_IMAGE_LABEL> <ROOT_IMG>
mount -o loop <ROOT_IMG> <loop_mnt>
rsync -aHAXx --exclude='/proc/*' --exclude='/sys/*' \
    --exclude='/dev/*' --exclude='/run/*' --exclude='/tmp/*' \
    <rootfs>/ <loop_mnt>/
umount <loop_mnt>
```

The `-aHAXx` flags preserve hardlinks, ACLs, extended attributes, and exclude synthetic filesystems. The UUID and label set at `mkfs.ext4` time must match the cmdline and fstab — they all use `BUILD_UUID`.

**Step 7 — Sparse conversion**

If `img2simg` is present (from `android-sdk-libsparse-utils`), the raw image is converted to Android sparse format. Sparse images transfer faster over fastboot and are accepted by `fastboot flash system`. If `img2simg` is absent, the raw image is used directly.

**Flash instructions**

Prints device-appropriate instructions:

- **mkbootimg devices:** `fastboot flash boot <boot.img>` + `fastboot flash system <sparse.img>`
- **L4T (Switch):** Copy lz4 files to SD card at `switchroot/ubuntu/`, flash rootfs via Hekate UMS or `dd`

---

### 4_enter_chroot.sh

**Purpose:** Developer tool for interactive inspection of the rootfs. Sources `build.env` and drops into a shell inside the rootfs directory. Not part of the normal build pipeline.

**Note:** The script header says RC13 — it has not been updated since RC13 and is unchanged.

**Requires:** `build.env` and `ROOTFS_DIR` pointing to an unpacked rootfs (the directory `mobuntu-<codename>-<release>`). This directory is created by `5_seal_rootfs.sh` during unpacking and deleted at the end of sealing. To use `4_enter_chroot.sh`, either interrupt sealing or unpack the tarball manually:

```bash
mkdir -p mobuntu-beryllium-resolute
sudo tar -xzf mobuntu-beryllium-resolute.tar.gz -C mobuntu-beryllium-resolute/
```

#### Architecture Handling

On an **ARM64 host** (e.g. another phone, a Raspberry Pi): Direct chroot, no QEMU needed. `resolv.conf` is copied from the host.

On an **x86-64 host in WSL2**: Injects the QEMU ARM64 binfmt handler into the kernel via `/proc/sys/fs/binfmt_misc/register` and copies `qemu-aarch64-static` into the rootfs. On other x86-64 hosts, relies on pre-registered binfmt via `binfmt-support`.

#### Mount / Unmount

Mounts `dev`, `dev/pts`, `proc`, `sys`, `run` via `--bind` before entering. Uses `mountpoint -q` to avoid double-mounting. On exit, unmounts all five in reverse order with `umount -l` (lazy unmount to handle busy mounts).

---

## Debos Recipes

### base.yaml

**Purpose:** Builds the Ubuntu base rootfs tarball. Contains only Ubuntu-sourced packages. The Mobian repository is deliberately excluded here.

**Required `-t` flags:** `UBUNTU_RELEASE`, `USERNAME`, `PASSWORD`, `UI_NAME`, `UI_DM`, `BUILD_COLOR`, `EXTRA_PKG`

**Output:** `base-<UBUNTU_RELEASE>.tar.gz`

#### Action Sequence

| # | Action | Description |
|---|--------|-------------|
| 1 | `debootstrap` | Bootstraps Ubuntu `<UBUNTU_RELEASE>` from `ports.ubuntu.com`. Components: main, restricted, universe, multiverse. |
| 2 | `run` (chroot) | Overwrites `/etc/apt/sources.list` with the three Ubuntu suites (release, updates, security). Runs `apt-get update && upgrade`. |
| 3 | `apt` | Installs base packages: `curl`, `ca-certificates`, `gnupg`, `initramfs-tools`, `sudo`, `network-manager`, `modemmanager`, `linux-firmware`, `bluez`, `pipewire`, `pipewire-pulse`, `wireplumber`, `openssh-server`, `locales`, `tzdata`. |
| 4 | `run` (chroot) | Installs the selected UI and display manager. See below. |
| 5 | `run` (chroot) | Installs `EXTRA_PKG` if non-empty. Skipped via `{{ if .EXTRA_PKG }}` guard. |
| 6 | `run` (chroot) | Creates user account with `sudo`, `video`, `audio`, `netdev`, `dialout` groups. Writes `NOPASSWD` sudoers entry. |
| 7 | `run` (chroot) | Writes stub `mobuntu` hostname. Overridden by device recipe. |
| 8 | `run` (chroot) | `apt-get clean` |
| 9 | `pack` | Produces `base-<UBUNTU_RELEASE>.tar.gz` |

#### UI Installation Detail

The UI install runs as a single `run` action (not a separate script) so that the UI and DM are resolved entirely against Ubuntu repos before `qcom.yaml` adds the Mobian repo.

| UI | Packages installed | DM enabled |
|----|-------------------|------------|
| `phosh` | `phosh`, `greetd`, `squeekboard` (or `phosh-osk-stub` fallback) | `greetd` |
| `ubuntu-desktop-minimal` | `ubuntu-desktop-minimal` | `gdm3` |
| `unity` | `ubuntu-unity-desktop` | `lightdm` |
| `plasma-desktop` | `kde-plasma-desktop` | `sddm` |
| `plasma-mobile` | `plasma-mobile`, `maliit-keyboard` | `sddm` |
| `lomiri` | `lomiri`, `squeekboard`, `greetd` | `greetd` |

For `phosh` and `lomiri`, a `greeter` system user is created and added to `video`, `render`, `input`, `audio` groups. The `greetd` config is written to `/etc/greetd/config.toml`.

For `ubuntu-desktop-minimal`, GNOME accent color is set to `BUILD_COLOR` via a dconf override at `/etc/dconf/db/local.d/01-mobuntu-theme`.

All display managers other than the selected one are disabled via `systemctl disable`.

#### Critical Design Note

`modemmanager` is installed here. On SDM845, enabling it crashes WiFi and BT — but it is included because removing it would break NetworkManager on devices where cellular works (OnePlus 6T dual-SIM). The beryllium device config does not list ModemManager in `DEVICE_SERVICES`, so it is installed but not activated.

---

### qcom.yaml

**Purpose:** SDM845-specific configuration layer. Added after the UI is installed in `base.yaml` to prevent Mobian package conflicts. Included via `recipe:` action from device recipes, not run standalone.

**Required variables (from recipe: action):** `DEVICE_CODENAME`, `DEVICE_BRAND`, `DEVICE_PACKAGES`, `DEVICE_SERVICES`, `DEVICE_QUIRKS`, `FIRMWARE_METHOD`, `FIRMWARE_REPO`

#### Action Sequence

| # | Action | Description |
|---|--------|-------------|
| 1 | `run` (chroot) | Adds Mobian repo: fetches GPG key from `repo.mobian.org`, writes `mobian.list`. Runs `apt-get update`. |
| 2 | `overlay` | Applies `overlays/qcom/` into the rootfs root. Contains WirePlumber config and the qcom-firmware initramfs hook. |
| 3 | `run` (chroot: **false**) | Runs `stage-firmware-git.sh` on the host. Only executed if `FIRMWARE_METHOD == "git"`. |
| 4 | `run` (chroot) | Installs `alsa-ucm-conf`, then `DEVICE_PACKAGES`. Fetches Adreno 630 firmware from kernel.org (`a630_sqe.fw`, `a630_gmu.bin`). Also fetches `a630_zap.mbn` if not using git firmware. Sets up Qualcomm service ordering drop-ins. Enables services. Masks ALSA state services. Makes hooks executable. |

#### Qualcomm Service Ordering

The drop-ins enforce this startup sequence:

```
qrtr-ns → rmtfs → pd-mapper → tqftpserv
```

Written as:
```ini
# /etc/systemd/system/pd-mapper.service.d/ordering.conf
[Unit]
After=qrtr-ns.service
Requires=qrtr-ns.service

# /etc/systemd/system/rmtfs.service.d/ordering.conf
[Unit]
After=qrtr-ns.service
Requires=qrtr-ns.service
```

#### ALSA Masking

`alsa-state.service` and `alsa-restore.service` are masked (symlinked to `/dev/null`) because they conflict with PipeWire on SDM845. If unmasked, ALSA attempts to save/restore card state and interferes with the UCM profiles.

#### Packages Never Installed

- `hexagonrpcd` — not installed. See [Known Issues](#known-issues).
- `qcom-support-common` — not installed. Mobian regression post March 2026 causes dependency conflicts.

---

### l4t.yaml

**Purpose:** Nintendo Switch configuration layer. Adds theofficialgman's `l4t-debs` apt repository and installs the NVIDIA Tegra L4T BSP packages required to boot the Switch.

**Required variables:** `DEVICE_CODENAME`, `DEVICE_PACKAGES`, `DEVICE_SERVICES`

**Note:** Always targets `noble` (24.04) — theofficialgman's `l4t-debs` does not yet support `resolute` (26.04). Switch device configs set `DEVICE_UBUNTU_OVERRIDE="noble"` to enforce this regardless of the user's `UBUNTU_RELEASE` selection.

#### Action Sequence

| # | Action | Description |
|---|--------|-------------|
| 1 | `run` (chroot) | Adds theofficialgman's `l4t-debs` repo GPG key and apt source (`dists/noble/`). Runs `apt-get update`. |
| 2 | `run` (chroot) | Installs core L4T BSP packages: `nvidia-l4t-core`, `nvidia-l4t-init`, `nvidia-l4t-firmware`, `nvidia-l4t-kernel`, `nvidia-l4t-kernel-dtbs`, `nvidia-l4t-xusb-firmware`, `nvidia-l4t-libvulkan`. Installs `DEVICE_PACKAGES` if non-empty. |
| 3 | `run` (chroot) | Enables each service in `DEVICE_SERVICES`. |
| 4 | `run` (chroot) | `mkdir -p /boot/efi`. Enables `joycond` and `nvpmodel` if present. |

**TODO:** Exact `nvidia-l4t-*` package names need verification against the live `l4t-debs` packages index before a Switch build is attempted. Fetch the index to confirm: `curl https://theofficialgman.github.io/l4t-debs/dists/noble/main/binary-arm64/Packages | grep "^Package:"`

---

### devices/beryllium.yaml

**Purpose:** Full device build recipe for the Xiaomi Poco F1 (both Tianma and EBBG panels share this recipe). Orchestrates the complete SDM845 build from base tarball to device tarball.

**Required `-t` flags:** All standard flags plus `KERNEL_METHOD`, `KERNEL_REPO`, `KERNEL_SERIES`, `KERNEL_VERSION_PIN`, `BOOT_DTB`, `BOOT_DTB_APPEND`, `DEVICE_HOSTNAME`

**Output:** `<DEVICE_IMAGE_LABEL>-<UBUNTU_RELEASE>.tar.gz`

#### Action Sequence

| # | Action | Description |
|---|--------|-------------|
| 1 | `unpack` | Unpacks `base-<UBUNTU_RELEASE>.tar.gz` into the fakemachine rootfs. |
| 2 | `recipe` | Executes `qcom.yaml` with device variables forwarded. |
| 3 | `overlay` | Applies `overlays/beryllium-hooks/` — the OTA kernel and initramfs rebuild hooks. |
| 4 | `run` (chroot) | Installs kernel. Builds mkbootimg natively (ARM64, in-chroot). Runs `update-initramfs -c -k all`. |
| 5 | `run` (chroot) | Makes OTA hooks executable. Creates `/boot/efi`. |
| 6 | `run` (chroot) | Writes `/etc/hostname` and `/etc/hosts`. |
| 7 | `run` (chroot) | `apt-get clean` |
| 8 | `pack` | Produces `<DEVICE_IMAGE_LABEL>-<UBUNTU_RELEASE>.tar.gz` |

#### Kernel Installation

Two methods are supported:

**`mobian`** (default for beryllium): Installs `linux-image-sdm845` from the Mobian repo. If `KERNEL_VERSION_PIN` is set, tries the pinned version first with two suffix patterns (`<pin>-1` then `<pin>`), falling back to the unpinned package if both fail.

```bash
apt-get install -y "linux-image-sdm845=6.18.20-1" 2>/dev/null ||
apt-get install -y "linux-image-sdm845=6.18.20"   2>/dev/null ||
apt-get install -y "linux-image-sdm845"
```

**`custom_url`**: Downloads a `.deb` from `KERNEL_REPO` URL, installs with `dpkg -i`, runs `apt-get install -f` to resolve dependencies.

#### mkbootimg Native Build

mkbootimg is compiled natively inside the ARM64 chroot during the device build. This ensures the binary matches the target architecture for the OTA hook (`zz-qcom-bootimg`) which runs on-device after kernel upgrades.

The `-Werror` flag is patched out of both `Makefile` and `libmincrypt/Makefile` before compilation. Both `mkbootimg` and `unpackbootimg` are installed to `/usr/local/bin/`.

---

### devices/switch-v1.yaml

**Purpose:** Device build recipe for the Nintendo Switch V1. Structurally identical to `beryllium.yaml` but uses `l4t.yaml` instead of `qcom.yaml` and does not build mkbootimg.

**Status:** RC16 — `l4t_repo` kernel method implemented. Kernel is installed by `l4t.yaml` BSP packages; `switch-v1.yaml` only runs `update-initramfs` after. Packs tarball as `mobuntu-icosa-noble.tar.gz` (noble, not resolute).

#### Key Differences from beryllium.yaml

- Uses `recipe: ../l4t.yaml` instead of `../qcom.yaml`
- No mkbootimg build step — L4T uses lz4-compressed kernel + initrd placed on the SD FAT32 partition
- No firmware staging script — Switch firmware from `linux-firmware` apt package and L4T BSP
- No device-specific overlays
- `l4t_repo` kernel method: kernel installed via `l4t.yaml` BSP packages, no separate URL needed
- Output tarball uses `DEVICE_UBUNTU_OVERRIDE` (noble) not `UBUNTU_RELEASE`

---

## Recipe Scripts

### stage-firmware-git.sh

**Location:** `recipes/scripts/stage-firmware-git.sh`  
**Runs:** Host-side (`chroot: false`). Called from `qcom.yaml`.  
**Environment:** `FIRMWARE_REPO`, `DEVICE_CODENAME`, `DEVICE_BRAND`, `ROOTDIR` (set by debos)

**Purpose:** Stages firmware blobs into the debos rootfs from a combination of a local bundle and a git clone.

#### Logic Flow

```
1. Check for local bundle at:
   recipes/scripts/../../firmware/<DEVICE_BRAND>-<DEVICE_CODENAME>/firmware.tar.gz

2. If local bundle exists → prompt user
   Y (default): extract to $ROOTDIR/  (base layer)
   N: skip local bundle

3. If FIRMWARE_REPO is non-empty → git clone --depth=1 into temp dir
   Success: copy lib/ and usr/ into $ROOTDIR/
   Failure: if nothing staged yet and local bundle exists → use local bundle

4. OnePlus 6 fallback (last resort):
   If nothing staged → copy blobs from host's /usr/lib/firmware/qcom/sdm845/oneplus6/
   Warns these are not officially signed for the target device

5. If local bundle exists and git clone succeeded:
   Re-apply local bundle over git (local bundle wins)
```

The double-application of the local bundle (steps 2 and 5) ensures that device-specific overrides in the local bundle always take precedence over the git HEAD, regardless of what the git repo changed.

#### Path Resolution — ARTIFACTDIR

The script uses `$ARTIFACTDIR` (set by debos to the working directory debos was invoked from) to locate the local firmware bundle — **not** `BASH_SOURCE[0]`. Debos copies scripts to a temp location before execution, so `BASH_SOURCE[0]`-based path resolution always fails. Since `run_build.sh` does `cd "${SCRIPT_DIR}"` before invoking debos, `ARTIFACTDIR` reliably points to the Mobuntu repo root.

#### Local Bundle Path

```
Mobuntu/
└── firmware/
    └── <DEVICE_BRAND>-<DEVICE_CODENAME>/
        └── firmware.tar.gz       ← this file
```

For beryllium: `firmware/xiaomi-beryllium/firmware.tar.gz`

The local bundle is always applied non-interactively when present (the earlier interactive `read -p` prompt was removed — debos `chroot: false` scripts run without a TTY). The git clone runs after and overlays on top. The local bundle is then re-applied a second time so it wins over any git changes.

The DSP bundle (`dsp.tar.gz`) lives alongside this and is handled by `install-fastrpc-device.sh`, not this script.

#### OnePlus 6 Fallback

A list of specific firmware filenames is copied from the host's `linux-firmware` package location for oneplus6 to the beryllium path in the rootfs. This is a last-resort fallback and produces a warning. The blobs are not signed for beryllium's secure boot chain, but GPU, WiFi, and BT generally work.

---

### install-fastrpc-device.sh

**Location:** `recipes/scripts/install-fastrpc-device.sh`  
**Runs:** Host-side (`chroot: false`). Intended to be called from `qcom.yaml` (not yet wired in as of RC15).  
**Environment:** `DEVICE_BRAND`, `DEVICE_CODENAME`, `ROOTDIR`

**Purpose:** Stages DSP userspace binaries and installs fastrpc daemon packages into the rootfs.

#### Actions

**DSP binaries** (`firmware/<brand>-<codename>/dsp.tar.gz`):

Extracts the tarball into `$ROOTDIR/`. Contents land at:
```
usr/share/qcom/sdm845/Xiaomi/beryllium/
    adsp/   fastrpc_shell_0, audio codec libs, sysmon skels
    cdsp/   fastrpc_shell_3, VPP libs
    sdsp/   fastrpc_shell_2, libchre_slpi_skel.so, CHRE drivers
```
This path is the fastrpc-support daemon's search path for DSP-side binaries.

**rfsa skel libs** (`firmware/<brand>-<codename>/rfsa.tar.gz`, optional):

Extracts to `$ROOTDIR/usr/lib/rfsa/adsp/`. These are vendor-partition skel libraries for the FastRPC UTF forwarding layer.

**fastrpc .deb packages** (`packages/fastrpc/*.deb`):

Copies `.deb` files into `$ROOTDIR/tmp/fastrpc-debs/`, then installs them inside the chroot in dependency order:
1. `libfastrpc1_*.deb`
2. `fastrpc-support_*.deb`

**udev rules fallback**: If the fastrpc-support deb did not install its udev rules (e.g. because the deb is absent), writes fallback rules at `usr/lib/udev/rules.d/60-fastrpc-support.rules` granting group `fastrpc` access to `/dev/fastrpc-*` and `/dev/adsprpc-smd`.

**Service enablement**: Creates symlinks in `multi-user.target.wants/` for `adsprpcd.service` and `cdsprpcd.service` if the service files are present.

#### RC16 Integration Status

The script is wired into `qcom.yaml` as action 4 (between firmware staging and Qualcomm packages). The `environment:` block passes `DEVICE_BRAND` and `DEVICE_CODENAME`, but debos template substitution does not always survive this block — the script falls back to sourcing `build.env` from `ARTIFACTDIR` if either variable is empty.

The action in `qcom.yaml`:

```yaml
- action: run
  chroot: false
  script: scripts/install-fastrpc-device.sh
  environment:
    DEVICE_BRAND: "{{ .DEVICE_BRAND }}"
    DEVICE_CODENAME: "{{ .DEVICE_CODENAME }}"
```

---

## Overlays

Overlays are applied with debos `overlay:` actions, which merge the directory tree into the rootfs root.

### zz-qcom-bootimg

**Location:** `recipes/overlays/beryllium/etc/kernel/postinst.d/zz-qcom-bootimg`  
**Installed at:** `/etc/kernel/postinst.d/zz-qcom-bootimg` (in rootfs)  
**Runs:** On the device, after every kernel package install or upgrade.

**Purpose:** Rebuilds `boot.img` when a new kernel is installed via apt. This is the OTA hook that keeps the boot partition in sync with the installed kernel.

#### Invocation

Called by dpkg's postinst machinery with the kernel version string as `$1`. The `zz-` prefix ensures it runs last among all postinst hooks.

#### Logic

1. Exits immediately if the kernel version does not contain `sdm845` — ignores non-SDM845 kernel installs.
2. Reads DTB name from `/etc/kernel/boot_dtb` (written by `5_seal_rootfs.sh`). Falls back to `sdm845-xiaomi-beryllium-tianma.dtb` if the file is absent.
3. Searches `/usr/lib/linux-image-<version>/qcom/` and `/boot/` for the DTB file.
4. Exits with a warning if the DTB is not found (non-fatal).
5. Reads cmdline from `/etc/kernel/cmdline`.
6. Concatenates kernel + DTB (always — SDM845 requires appended DTB).
7. Calls `mkbootimg` with hardcoded SDM845 offsets (same as `5_seal_rootfs.sh`).
8. Output: `/boot/boot.img`

The hardcoded offsets are:
```
--pagesize 4096  --base 0x00000000
--kernel_offset 0x00008000  --ramdisk_offset 0x01000000  --tags_offset 0x00000100
```

These match all known SDM845 Xiaomi and OnePlus devices.

---

### bootimg

**Location:** `recipes/overlays/beryllium/etc/initramfs/post-update.d/bootimg`  
**Installed at:** `/etc/initramfs/post-update.d/bootimg` (in rootfs)  
**Runs:** On the device, after every `update-initramfs` call.

**Purpose:** Triggers a boot.img rebuild after the initrd is updated. Delegates entirely to `zz-qcom-bootimg`:

```sh
#!/bin/sh
/etc/kernel/postinst.d/zz-qcom-bootimg "$1"
```

`$1` is the kernel version string passed by `update-initramfs`. This ensures that both kernel upgrades (via postinst) and initrd updates (via post-update) result in a fresh `boot.img`.

---

### 51-qcom.conf

**Location:** `recipes/overlays/enchilada/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf`  
**Installed at:** `/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf` (in rootfs)  
**Applied to:** OnePlus 6/6T (enchilada/fajita). Beryllium gets this via the `overlays/qcom/` overlay.

**Purpose:** Forces WirePlumber's ALSA monitor to use 16-bit signed little-endian samples at 48 kHz for all audio nodes. This prevents the default rate negotiation from selecting formats that the SDM845 audio subsystem cannot handle.

```
audio.format = "S16LE"
audio.rate   = 48000
```

Note: `api.alsa.period-size` is deliberately omitted. The upstream `qcom-phone-utils` 0.4.1 fix found that auto-selection works better than a fixed period size on enchilada/fajita.

---

## Device Configs

Device configs are `bash`-sourceable files in `devices/`. Each defines a standard set of variables consumed by `1_preflight.sh` and the debos recipes.

### Config Schema

| Variable | Type | Description |
|----------|------|-------------|
| `DEVICE_NAME` | string | Human-readable name shown in device picker |
| `DEVICE_CODENAME` | string | Short codename. Must match `recipes/devices/<codename>.yaml` |
| `DEVICE_BRAND` | string | Vendor prefix. Used for firmware path: `firmware/<brand>-<codename>/` |
| `DEVICE_ARCH` | string | Always `arm64` currently |
| `DEVICE_SIM_SLOTS` | int | Number of SIM slots (informational) |
| `KERNEL_METHOD` | `mobian` \| `custom_url` | How to install the kernel |
| `KERNEL_REPO` | URL | Mobian pool URL or direct `.deb` URL |
| `KERNEL_SERIES` | string | Package name suffix: `linux-image-<series>` |
| `KERNEL_VERSION_PIN` | string | Version to pin (e.g. `6.18.20`). Empty = latest |
| `BOOT_METHOD` | `mkbootimg` \| `l4t` \| `uboot` \| `uefi` | Boot image format |
| `MKBOOTIMG_PAGESIZE` | hex int | Page size for mkbootimg |
| `MKBOOTIMG_BASE` | hex | Base address |
| `MKBOOTIMG_KERNEL_OFFSET` | hex | Kernel load offset |
| `MKBOOTIMG_RAMDISK_OFFSET` | hex | Ramdisk load offset |
| `MKBOOTIMG_TAGS_OFFSET` | hex | ATAGs/DTB tags offset |
| `BOOT_DTB_APPEND` | `true`\|`false` | Concatenate DTB to kernel before mkbootimg |
| `BOOT_DTB` | filename | Default DTB filename |
| `BOOT_PANEL_PICKER` | `true`\|`false` | Prompt user to select panel at build time |
| `FIRMWARE_METHOD` | `git` \| `apt` | Firmware source |
| `FIRMWARE_REPO` | URL | Git repo URL (if method=git) |
| `FIRMWARE_INSTALL_PATH` | string | Install root (currently always `/`) |
| `DEVICE_PACKAGES` | space-separated | Extra apt packages installed in qcom.yaml |
| `DEVICE_SERVICES` | space-separated | systemd services to enable |
| `DEVICE_QUIRKS` | space-separated | Feature flags read by scripts |
| `DEVICE_HOSTNAME` | string | Overrides the color-based hostname if set |
| `DEVICE_IMAGE_LABEL` | string | Filename prefix and ext4 volume label |

#### DEVICE_QUIRKS flags

| Quirk | Read by | Effect |
|-------|---------|--------|
| `dtb_append` | `5_seal_rootfs.sh` | Concatenate DTB to kernel in mkbootimg |
| `qcom_services` | `verify_build.sh` | Enable Qualcomm-specific verification checks |
| `firmware_source_local` | `stage-firmware-git.sh` | Prompt to apply local firmware bundle |
| `l4t_bootfiles` | `5_seal_rootfs.sh` | Output lz4 bootfiles instead of boot.img |
| `firmware_source_online` | Informational | Firmware from apt/online, no local bundle |

---

### xiaomi-beryllium-tianma.conf

Xiaomi Poco F1 with Tianma display panel.

```
DEVICE_CODENAME:    beryllium
KERNEL_METHOD:      mobian
KERNEL_SERIES:      sdm845
KERNEL_VERSION_PIN: 6.18.20        ← update to 6.18.23
BOOT_METHOD:        mkbootimg
BOOT_DTB_APPEND:    true
BOOT_DTB:           sdm845-xiaomi-beryllium-tianma.dtb
BOOT_PANEL_PICKER:  false
FIRMWARE_METHOD:    git
FIRMWARE_REPO:      https://gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium
DEVICE_PACKAGES:    qrtr-tools rmtfs tqftpserv protection-domain-mapper qbootctl
DEVICE_SERVICES:    qrtr-ns rmtfs pd-mapper tqftpserv
DEVICE_QUIRKS:      dtb_append qcom_services firmware_source_local
```

**Pending:** `KERNEL_VERSION_PIN` should be updated from `6.18.20` to `6.18.23`.

---

### xiaomi-beryllium-ebbg.conf

Xiaomi Poco F1 with EBBG display panel. Identical to the Tianma config except:

```
DEVICE_NAME: "Xiaomi Poco F1 (EBBG)"
BOOT_DTB:    sdm845-xiaomi-beryllium-ebbg.dtb
```

Both panel variants use the same `beryllium.yaml` recipe and produce the same `mobuntu-beryllium` image label. The only runtime difference is the DTB.

---

### oneplus-enchilada.conf

OnePlus 6. Key differences from beryllium:

```
DEVICE_CODENAME:  enchilada
DEVICE_BRAND:     oneplus
FIRMWARE_METHOD:  apt           ← no git clone, blobs from linux-firmware
FIRMWARE_REPO:    (empty)
BOOT_DTB:         sdm845-oneplus-enchilada.dtb
DEVICE_QUIRKS:    dtb_append qcom_services   ← no firmware_source_local
```

OnePlus 6 blobs ship in the upstream `linux-firmware` apt package, so no git firmware clone is needed. The `firmware_source_local` quirk is absent, so `stage-firmware-git.sh` will not prompt for a local bundle.

The WirePlumber overlay is at `overlays/enchilada/` (not `overlays/qcom/`) — check that the enchilada device recipe applies the correct overlay path.

---

### nvidia-switch-v1.conf

Nintendo Switch V1 (Erista, T210/icosa). Key fields:

```
DEVICE_CODENAME:         icosa
DEVICE_BRAND:            nvidia
KERNEL_METHOD:           l4t_repo
KERNEL_REPO:             (empty — not used with l4t_repo)
KERNEL_SERIES:           tegra210
BOOT_METHOD:             l4t
BOOT_DTB:                tegra210-icosa.dtb
BOOT_DTB_APPEND:         false
FIRMWARE_METHOD:         apt
DEVICE_PACKAGES:         (empty)
DEVICE_SERVICES:         (empty)
DEVICE_QUIRKS:           l4t_bootfiles firmware_source_online
DEVICE_UBUNTU_OVERRIDE:  noble
```

`KERNEL_METHOD` is now `l4t_repo` — the kernel is installed by `l4t.yaml` via the `l4t-debs` BSP packages. `KERNEL_REPO` is unused and left empty. `DEVICE_UBUNTU_OVERRIDE="noble"` forces the noble base tarball regardless of the user's release selection.

---

## build.env Reference

`build.env` is written by `1_preflight.sh` and sourced by all other scripts. Do not edit manually.

| Variable | Set by | Example value |
|----------|--------|---------------|
| `HOST_ARCH` | preflight | `x86_64` |
| `HOST_IS_ARM64` | preflight | `false` |
| `FAKEMACHINE_BACKEND` | preflight | `kvm` |
| `USERNAME` | preflight | `phone` |
| `PASSWORD` | preflight | `1234` |
| `UBUNTU_RELEASE` | preflight | `resolute` |
| `ROOTFS_DIR` | preflight | `mobuntu-beryllium-resolute` |
| `IMAGE_SIZE` | preflight | `12` |
| `EXTRA_PKG` | preflight | _(empty)_ |
| `DEVICE_CONF` | preflight | `devices/xiaomi-beryllium-tianma.conf` |
| `DEVICE_NAME` | device conf | `Xiaomi Poco F1 (Tianma)` |
| `DEVICE_CODENAME` | device conf | `beryllium` |
| `DEVICE_BRAND` | device conf | `xiaomi` |
| `DEVICE_ARCH` | device conf | `arm64` |
| `DEVICE_HOSTNAME` | preflight (color) | `mobuntu-yellow` |
| `BUILD_COLOR` | preflight | `yellow` |
| `BOOT_PANEL` | preflight | `default` |
| `BOOT_DTB_SELECTED` | preflight | `sdm845-xiaomi-beryllium-tianma.dtb` |
| `DEVICE_IMAGE_LABEL` | device conf | `mobuntu-beryllium` |
| `DEVICE_PACKAGES` | device conf | `qrtr-tools rmtfs tqftpserv ...` |
| `DEVICE_SERVICES` | device conf | `qrtr-ns rmtfs pd-mapper tqftpserv` |
| `DEVICE_QUIRKS` | device conf | `dtb_append qcom_services firmware_source_local` |
| `UI_NAME` | preflight | `phosh` |
| `UI_DM` | preflight | `greetd` |
| `KERNEL_METHOD` | device conf | `mobian` |
| `KERNEL_REPO` | device conf | `https://repo.mobian.org/pool/main/l/` |
| `KERNEL_SERIES` | device conf | `sdm845` |
| `KERNEL_VERSION_PIN` | device conf | `6.18.20` |
| `BOOT_METHOD` | device conf | `mkbootimg` |
| `MKBOOTIMG_PAGESIZE` | device conf | `4096` |
| `MKBOOTIMG_BASE` | device conf | `0x00000000` |
| `MKBOOTIMG_KERNEL_OFFSET` | device conf | `0x00008000` |
| `MKBOOTIMG_RAMDISK_OFFSET` | device conf | `0x01000000` |
| `MKBOOTIMG_TAGS_OFFSET` | device conf | `0x00000100` |
| `BOOT_DTB_APPEND` | device conf | `true` |
| `BOOT_DTB` | device conf | `sdm845-xiaomi-beryllium-tianma.dtb` |
| `BOOT_PANEL_PICKER` | device conf | `false` |
| `FIRMWARE_METHOD` | device conf | `git` |
| `FIRMWARE_REPO` | device conf | `https://gitlab.com/sdm845-mainline/...` |
| `FIRMWARE_INSTALL_PATH` | device conf | `/` |
| `WATCHDOG_ENABLED` | preflight | `false` |
| `AUTO_SUDO` | preflight | `false` |
| `DEVICE_UBUNTU_OVERRIDE` | device conf (Switch only) | `noble` |
| `ROOTFS_UUID` | 5_seal_rootfs.sh | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

---

## Known Issues

### SLPI crash loop (beryllium)

`remoteproc2` (SLPI — Sensor Low Power Island) crash-loops approximately every 40 seconds. Journald shows `qcom_scm` returning `-22` (EINVAL) and the SLPI being restarted by remoteproc. This is cosmetic: display, audio, WiFi, BT, and touch are unaffected.

**Root cause:** The SLPI userspace daemon (`hexagonrpcd`) requires device-specific DSP binaries that are not available from the firmware git repository. The `droid-juicer` extraction pipeline (used by some postmarketOS devices) would populate `/var/lib/droid-juicer/sensors/`, but Mobuntu does not use `droid-juicer`. The fastrpc daemon stack (`adsprpcd`/`cdsprpcd`) addresses this for ADSP and CDSP; SLPI support requires the `sdsp` fastrpc shell binary which is included in the DSP bundle but the daemon integration is not yet complete.

**Do not install `hexagonrpcd`** — the crash loop continues with or without it because the droid-juicer path does not exist in a clean build.

### Modem crashes WiFi and BT

Enabling `ModemManager` or `ofono` with a SIM inserted causes the WiFi and BT subsystems to crash. This is a known SDM845 mainline limitation. `ModemManager` is installed (required by NetworkManager) but not enabled. Do not add it to `DEVICE_SERVICES`.

### KERNEL_VERSION_PIN stale on beryllium

Both beryllium configs pin to `6.18.20`. The current Mobian SDM845 kernel is `6.18.23`. Update both confs:

```bash
sed -i 's/KERNEL_VERSION_PIN="6.18.20"/KERNEL_VERSION_PIN="6.18.23"/' \
    devices/xiaomi-beryllium-tianma.conf \
    devices/xiaomi-beryllium-ebbg.conf
```

### Switch l4t-debs package names unverified

RC16 switches all Switch builds to `l4t_repo` method using theofficialgman's `l4t-debs` apt repository. The `nvidia-l4t-*` package names in `l4t.yaml` follow the expected naming convention but have not been verified against the live packages index. Before attempting a Switch build, confirm with:
```bash
curl https://theofficialgman.github.io/l4t-debs/dists/noble/main/binary-arm64/Packages | grep "^Package:"
```

### resolute debootstrap symlink

Ubuntu 26.04 (resolute) is not in debootstrap's script list. `1_preflight.sh` creates the symlink automatically, but if you skip preflight and run debos directly, create it first:

```bash
sudo ln -sf /usr/share/debootstrap/scripts/gutsy \
    /usr/share/debootstrap/scripts/resolute
```

### qcom-support-common

Do not install `qcom-support-common`. As of March 2026, this Mobian package introduces dependency conflicts that break `ubuntu-desktop-minimal` builds on noble and later. It is not listed in any device config.

---

## Adding a New Device

### 1. Create the device config

Copy the closest existing config and edit:

```bash
cp devices/xiaomi-beryllium-tianma.conf devices/vendor-codename.conf
```

Set at minimum:
- `DEVICE_NAME`, `DEVICE_CODENAME`, `DEVICE_BRAND`
- `KERNEL_METHOD`, `KERNEL_SERIES`, `KERNEL_VERSION_PIN`
- `BOOT_METHOD`, `BOOT_DTB`, `BOOT_DTB_APPEND`
- `MKBOOTIMG_*` offsets (if `BOOT_METHOD=mkbootimg`)
- `FIRMWARE_METHOD`, `FIRMWARE_REPO`
- `DEVICE_PACKAGES`, `DEVICE_SERVICES`, `DEVICE_QUIRKS`
- `DEVICE_IMAGE_LABEL` (used as tarball prefix and ext4 label)

### 2. Create the device recipe

For SDM845 devices:

```bash
cp recipes/devices/beryllium.yaml recipes/devices/codename.yaml
```

The recipe is almost always identical for SDM845 — the differences are in the device config, not the recipe. Edit only if the device needs different build steps.

For Switch devices:

```bash
cp recipes/devices/switch-v1.yaml recipes/devices/codename.yaml
```

### 3. Add firmware

For `FIRMWARE_METHOD=git`: point `FIRMWARE_REPO` at the firmware git repository. No local files needed for a baseline build.

For `FIRMWARE_METHOD=apt`: blobs ship in the `linux-firmware` Ubuntu package. Nothing extra needed.

For a local firmware bundle (`firmware_source_local` quirk):
```
firmware/<DEVICE_BRAND>-<DEVICE_CODENAME>/firmware.tar.gz
```

### 4. Add WirePlumber overlay (SDM845)

Copy the enchilada overlay and verify the `S16LE`/`48000` settings are correct for the new device:

```bash
mkdir -p recipes/overlays/codename/usr/share/wireplumber/wireplumber.conf.d/
cp recipes/overlays/enchilada/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf \
   recipes/overlays/codename/usr/share/wireplumber/wireplumber.conf.d/
```

Reference the overlay in the device recipe or in `qcom.yaml` if the overlay path changes.

### 5. Test

```bash
bash 1_preflight.sh   # select new device
bash run_build.sh
bash verify_build.sh
bash 5_seal_rootfs.sh
```

Check `verify_build.sh` output — all `[FAIL]` items must be resolved before flashing.
