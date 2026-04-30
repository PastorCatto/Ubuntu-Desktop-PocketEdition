# Mobuntu Changelog
## RC10.2.2 LTS → RC15
> LTS cycle: ~1 week
> RC10.2.2 is the stable LTS baseline. RC15 is the current development release.

---

## RC14 — "The Quirks Update"
> Incremental release between LTS and RC15

### New: DEVICE_QUIRKS system
- Introduced `DEVICE_QUIRKS` string in all device configs as the single
  source of truth for device-specific build behaviour
- `has_quirk()` helper function available on host (cooker) and inside chroot
- All Qualcomm-specific steps gated behind `qcom_services` quirk —
  Switch builds no longer attempt to install rmtfs, pd-mapper, etc.
- Defined quirk flags:
  - `dtb_append` — cat kernel + DTB before mkbootimg (SDM845 required)
  - `qcom_services` — install/enable Qualcomm userspace daemons
  - `firmware_source_local` — use local firmware.tar.gz bundle
  - `firmware_source_online` — pull firmware from apt, no local bundle
  - `l4t_bootfiles` — output kernel.lz4 + initrd.lz4 + DTB (Switch)

### New: Nintendo Switch support
- Four new device configs: V1 (icosa), V2 (hoag), Lite (vali), OLED (aula)
- New `BOOT_METHOD="l4t"` in `5_seal_rootfs.sh`:
  - lz4-compresses kernel and initrd
  - Copies DTB
  - Prints Hekate flash instructions
- `lz4` added to host dependencies in `1_preflight.sh`
- Switch uses `firmware_source_online` — no local bundle required
- `KERNEL_REPO` is a placeholder in all Switch configs pending switchroot
  L4T kernel .deb URL confirmation

### Fixed: xiaomi-beryllium-ebbg.conf copy-paste
- Was identical to Tianma config including DTB name
- Now correctly references `sdm845-xiaomi-beryllium-ebbg.dtb`

### Fixed: Phosh / greetd
- `squeekboard` install made non-fatal — falls back to `phosh-osk-stub`,
  then warns if neither is available
- greetd `command` changed from `"phosh"` to `"/usr/bin/phosh"` (full path)
- `greeter` user groups expanded: `video,render,input,audio`
  (was `video` only — caused input and audio failures on first login)
- Same fix applied to `*)` fallback case

### Fixed: QEMU binary name (RC10.2.2 backport)
- All `qemu-aarch64` → `qemu-aarch64-static` in `3_rootfs_cooker.sh`
  and `4_enter_chroot.sh` (Ubuntu 24.04 host compatibility)

### Fixed: LOCAL_FW_ARCHIVE deduplication (RC10.2.2 backport)
- Variable was defined twice in `3_rootfs_cooker.sh`
- Now defined once at top of Step 2 and referenced consistently

### Updated: Firmware staging priority order
1. Local bundle (base layer, prompted)
2. Git clone (overlay on top)
3. Git-fail fallback to local bundle
4. OnePlus 6 apt fallback (last resort, with warning)

### Updated: `verify_build.sh`
- `has_quirk()` helper added
- Steps 5–12 gated on `qcom_services` — Switch builds skip Qcom checks
- Kernel glob is device-family aware

### Updated: `mobuntu-developer-masterkit.py`
- Boot Chain section added (first in menu)
- `HIGHLIGHT_KEYS` — critical keys highlighted in `.conf` file previews
- Device family shown in services section (Qualcomm vs L4T)
- New device template wizard asks `qcom/l4t` and generates appropriate config
- Verifier generator is quirk-aware

### Updated: `1_preflight.sh`
- `BOOT_PANEL_PICKER` gate — panel picker only shown when device requires it
- `lz4` added to host dependencies

---

## RC15 — "The Debos Update"
> Current development release

### Breaking: Scripts 2 and 3 retired
- `2_kernel_prep.sh` — retired, replaced by debos `download` action
- `3_rootfs_cooker.sh` — retired, replaced by debos recipe pipeline
- These scripts are removed from the project root

### New: debos recipe pipeline
- Build system ported from bash heredocs to debos YAML recipes
- Recipe layout:
  ```
  recipes/
  ├── base.yaml           # debootstrap + common packages + UI
  ├── qcom.yaml           # Qualcomm services, firmware, hooks
  ├── l4t.yaml            # Switch / L4T boot handling
  └── devices/
      ├── beryllium.yaml
      ├── enchilada.yaml
      ├── fajita.yaml
      ├── switch-v1.yaml
      ├── switch-v2.yaml
      ├── switch-lite.yaml
      └── switch-oled.yaml
  ```
- `base.yaml` outputs `base-{release}.tar.gz` — built once, reused by all
  device overlays. Eliminates redundant debootstrap runs for multi-device builds.
- Device recipes `unpack` base tarball, apply device-specific overlay,
  output `{device}-{release}.tar.gz` consumed by `5_seal_rootfs.sh`

### New: `run_build.sh` (generated artifact)
- `1_preflight.sh` now generates `run_build.sh` instead of calling the
  build directly
- Contains the full debos invocation with all `-t` template vars sourced
  from the selected device `.conf`
- Reproducible: re-runnable without going through preflight again
- Inspectable: user can verify all vars before running
- `watchdog.sh` wraps `run_build.sh` instead of scripts 2+3

### New: fakemachine backend selection
- `1_preflight.sh` auto-detects best available backend:
  1. `/dev/kvm` accessible → `--fakemachine-backend=kvm` (~9 min)
  2. `/dev/kvm` inaccessible → warn, try `uml` (~18 min)
  3. UML not available → `--fakemachine-backend=qemu` (~2.5 hrs, warn user)
  4. `--disable-fakemachine` → explicit opt-in only, requires root
- x86-64 hosts building ARM64 supported via QEMU backend
- WSL2 users: select `none` at backend prompt

### New: Multi-device build speed
- Base rootfs cached as tarball after first build
- Subsequent device builds skip debootstrap + apt, start from unpack
- Estimated 40-60% faster for multi-device builds vs RC14 bash pipeline

### Fixed: Boot cmdline (arkadin91)
- Old cmdline: `root=UUID=... rw rootwait console=tty0 console=ttyMSM0,115200n8 earlycon=qcom_geni,0x00A90000 quiet splash`
- New cmdline: `root=UUID=... earlycon console=tty0 console=ttyMSM0,115200 init=/sbin/init ro loglevel=7`
- Changes:
  - `rw rootwait` → `ro` (cleaner, fsck can run properly)
  - `console=ttyMSM0,115200n8` → `115200` (no parity suffix)
  - `earlycon=qcom_geni,0x00A90000` → `earlycon` (kernel auto-detects)
  - `init=/sbin/init` added explicitly
  - `loglevel=7` replaces quiet/splash toggle
  - Boot verbosity prompt removed from `5_seal_rootfs.sh`
- Credited to arkadin91 (confirmed working on beryllium reference image)

### Updated: `1_preflight.sh`
- Generates `run_build.sh` instead of calling scripts directly
- fakemachine backend detection and selection
- debos + fakemachine deps added to host dependency install
- `.conf` remains source of truth — vars sourced and passed as `-t` flags

### Updated: `5_seal_rootfs.sh`
- Unpacks device tarball from debos output before building boot assets
- New cmdline applied
- Boot verbosity prompt removed
- Boot packaging logic (mkbootimg / L4T) unchanged
- rootfs image creation unchanged

### Updated: `verify_build.sh`
- Aware of debos output paths and tarball structure
- Unpacks tarball to temp dir for inspection, cleans up after
- Base cache verification added

### Updated: `watchdog.sh`
- Wraps `run_build.sh` (debos invocation) instead of scripts 2+3
- ZWJ clean-exit signal logic unchanged

### Updated: `mobuntu-developer-masterkit.py`
- Boot Chain section updated to reflect debos pipeline
- `run_build.sh` added to file tree
- `recipes/` directory added to file tree
- Base tarball cache section added
- `FAKEMACHINE_BACKEND` shown in status bar

---

## Known Issues (all versions)

### SLPI crash loop (cosmetic)
- **Affects:** All SDM845 devices (beryllium, enchilada, fajita)
- **Symptom:** `remoteproc2` crashes every 40s, `qcom_scm: Assign memory
  protection call failed -22` in dmesg
- **Cause:** `sensor_process` user PD stalls without a FastRPC host daemon.
  `hexagonrpcd` requires droid-juicer vendor extraction at
  `/var/lib/droid-juicer/sensors/` — not available in a clean Ubuntu build.
- **Impact:** Sensor hub (accelerometer, gyro, barometer) non-functional.
  Display, audio, WiFi, modem, camera unaffected.
- **Resolution:** Do not install `hexagonrpcd`. Crash loop is cosmetic.
  Will be resolved when a non-droid-juicer sensor file path is established.

### qcom-support-common -22 regression (Mobian upstream)
- **Affects:** Mobian weekly builds after ~March 2026
- **Not present in:** arkadin91 (Mobian 03/08/2026) or any Mobuntu build
  (we do not install `qcom-support-common`)
- **Cause:** `qcom-phone-utils 0.4.3` (Nov 18 2025) reworked the
  `qcom-firmware` initramfs hook `case` statement for per-model/SoC
  conditions. The rework introduced a path mismatch for beryllium under
  the new logic, causing TZ to reject the SCM memory reassignment on
  SLPI recovery.
- **Impact:** Mobian-only. Mobuntu is not affected.
- **Resolution:** Upstream Mobian issue. Do not install `qcom-support-common`
  or `sdm845-support` in Mobuntu builds.

### Switch KERNEL_REPO placeholder
- **Affects:** All four Switch device configs
- **Cause:** switchroot L4T kernel .deb URL not yet confirmed
- **Resolution:** Fill in `KERNEL_REPO` in all Switch configs before building.
  Verify DTB filenames against a working switchroot install.

### Modem crashes WiFi and BT
- **Affects:** Beryllium (and likely all SDM845 devices)
- **Cause:** Under investigation
- **Resolution:** Do not enable ModemManager or ofono on beryllium.
