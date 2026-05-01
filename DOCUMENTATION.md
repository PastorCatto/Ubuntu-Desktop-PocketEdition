# Mobuntu Orange — Developer Documentation
**Grand Developer Kit Reset — May 1, 2026**

---

## Repository Layout

```
PastorCatto/Mobuntu/
├── devkit.py                  # TUI control panel — run from here
├── sync.py                    # Upstream sync engine
├── CHANGELOG.md
├── DOCUMENTATION.md
│
└── Mobuntu/                   # Build root
    ├── build.sh               # Multi-device build entrypoint
    ├── image.yaml             # debos image recipe (modified)
    ├── rootfs.yaml            # debos rootfs recipe (modified)
    ├── devices/               # Per-device configuration
    │   ├── beryllium/
    │   │   ├── device.conf
    │   │   └── overlays/
    │   ├── fajita/
    │   │   ├── device.conf
    │   │   └── overlays/
    │   └── enchilada/
    │       ├── device.conf
    │       └── overlays/
    ├── scripts/
    │   ├── fetch-firmware.sh  # Download-based fw/kernel install
    │   ├── final.sh           # Post-image system configuration
    │   ├── setup-user.sh      # User account setup
    │   └── update-apt.sh      # APT update + cleanup
    ├── files/                 # Firmware debs + GNOME extensions
    ├── overlays/              # System config overlays
    └── packages/              # debos package lists
```

---

## build.sh

Full multi-device build entrypoint. Requires root (re-execs via sudo automatically).

### Usage

```bash
sudo bash Mobuntu/build.sh -d <device> [options]

# Examples
sudo bash Mobuntu/build.sh -d beryllium
sudo bash Mobuntu/build.sh -d beryllium -s plucky
sudo bash Mobuntu/build.sh -d fajita -i
sudo bash Mobuntu/build.sh -h
```

### Flags

| Flag | Description |
|------|-------------|
| `-d <device>` | Device codename — required. One of: `beryllium`, `fajita`, `enchilada` |
| `-s <suite>` | Ubuntu suite override. Defaults to `DEVICE_SUITE` from device.conf |
| `-i` | Image only — skip rootfs debootstrap, reuse existing tarball |
| `-h` | Print usage and list available devices |

### Suite Gate

If the resolved suite is `resolute` (Ubuntu 26.04), build.sh requires double confirmation before proceeding due to known SDM845 regressions:

```
Type YES to confirm resolute: YES
Type RESOLUTE to confirm again: RESOLUTE
```

This applies whether resolute is set in device.conf or passed via `-s`.

### Device Discovery

Running `build.sh -h` auto-discovers all devices with a valid `device.conf`:

```
Available devices:
  beryllium — Poco F1 (xiaomi)
  enchilada — OnePlus 6 (oneplus)
  fajita    — OnePlus 6T (oneplus)
```

### Variable Validation

build.sh validates required device conf fields before launching debos. If any are missing it exits with a clear error rather than letting debos fail silently:

```bash
: "${FW_ARCHIVE_URL:?device.conf missing FW_ARCHIVE_URL}"
: "${KERNEL_IMAGE_URL:?device.conf missing KERNEL_IMAGE_URL}"
: "${KERNEL_VERSION:?device.conf missing KERNEL_VERSION}"
```

### Build Stages

```
── Stage 1: rootfs ──   debos rootfs.yaml  (debootstrap + packages)
── Stage 2: image ──    debos image.yaml   (overlay + firmware + kernel + seal)
```

Output files written to `Mobuntu/`:
- `mobuntu-<device>-<YYYYMMDD>.img` — full GPT image
- `root-mobuntu-<device>-<YYYYMMDD>.img` — bare ext4 rootfs partition

---

## sync.py

Pulls latest upstream from arkadin91/mobuntu-recipes, extracts device vars, and updates your fork.

### Usage

```bash
# From repo root
python3 sync.py                     # full sync
python3 sync.py --dry-run           # show changes without writing
python3 sync.py --extract-only      # show extracted upstream vars only
python3 sync.py --fork-dir PATH     # override fork directory
```

### Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--fork-dir` | `Mobuntu/` | Path to your fork relative to cwd |
| `--dry-run` | off | Show all changes without writing anything |
| `--extract-only` | off | Print extracted device vars and exit |

### Sync Stages

```
[ 1/4 ] Fetching upstream       git clone --depth=1 into temp dir
[ 2/4 ] Extracting device vars  scans upstream scripts for hardcoded values
[ 3/4 ] Diffing upstream        compares upstream files to your fork
[ 4/4 ] Applying updates        copies changed files, updates device confs
```

### State Tracking

Sync state is written to `Mobuntu/.devkit-sync-state.json`:

```json
{
  "last_sync": "2026-05-01T14:23:00",
  "upstream_sha": "3f09ce7e9da5...",
  "file_hashes": {}
}
```

If the upstream SHA matches the last known SHA, sync exits early with no changes.

### Pinned Files

These paths are never overwritten by sync regardless of upstream changes:

```
build.sh
image.yaml
rootfs.yaml
devices/
scripts/fetch-firmware.sh
overlays/etc/systemd/system/hexagonrpcd.service.d/
overlays/usr/share/dbus-1/
overlays/usr/share/polkit-1/
```

### Custom Lock File

Add additional paths to `Mobuntu/.devkit-sync-lock` to protect them from sync:

```
# .devkit-sync-lock
scripts/my-custom-script.sh
overlays/etc/my-config
```

One path per line. Lines starting with `#` are ignored.

### Extracted Variables

sync.py scans upstream scripts and YAML for these hardcoded values and merges them into `devices/*/device.conf`:

| Upstream Source | Extracted As |
|----------------|--------------|
| `apt-get install linux-image-X-sdm845` | `KERNEL_VERSION` |
| `linux-headers-X-sdm845` | `KERNEL_HEADERS_VERSION` |
| `suite: resolute` in rootfs.yaml | `DEVICE_SUITE` |
| `wget https://...alsa-ucm-conf...deb` | `ALSA_UCM_URL` |

Existing device.conf values are only updated if the upstream value has changed. No keys are ever removed.

### Headless Download Mode

sync.py is not involved in downloads directly, but devkit.py exposes a headless download mode:

```bash
python3 devkit.py --download <url> <dest>
```

Streams the file with live progress to stdout. Requires `pip install requests`.

---

## devkit.py

Split-pane curses TUI. Run from repo root:

```bash
python3 devkit.py
```

### Layout

```
┌─ Navigation ──────────┐ ┌─ Content ─────────────────────────────────────────┐
│  nav tree             │ │  context-sensitive pane                            │
└───────────────────────┘ └────────────────────────────────────────────────────┘
┌─ Status / Progress ───────────────────────────────────────────────────────────┐
│  [bar] pct% message                                      keybind hints        │
└───────────────────────────────────────────────────────────────────────────────┘
```

### Keybindings

| Key | Context | Action |
|-----|---------|--------|
| `↑` `↓` | Nav pane | Move through tree |
| `Enter` | Nav pane — node with children | Expand / collapse |
| `Enter` | Nav pane — leaf node | Jump to content pane |
| `Tab` | Anywhere | Toggle focus between nav and content pane |
| `↑` `↓` | Content pane — device view | Move between action buttons |
| `Enter` | Content pane — device view | Execute selected action |
| `S` | Content pane — sync view | Run sync now |
| `D` | Content pane — sync view | Dry run sync |
| `r` | Anywhere | Refresh device tree from filesystem |
| `q` | Anywhere | Quit |

### Nav Tree

```
⟳  Sync
⊞  Devices
   ▾ beryllium
   ▾ enchilada
   ▾ fajita
⚙  Build
?  About
```

Devices are auto-discovered from `Mobuntu/devices/*/device.conf` at startup. Press `r` to re-scan after adding a new device.

### Sync Pane

Shows upstream URL, fork path, last sync timestamp, and upstream SHA. Background thread — UI stays responsive during sync. Output from the last sync operation is shown inline.

### Device Pane

Shows full device conf fields including display variants and DTB paths. Radio-button actions:

```
( ) Build image for this device
( ) Edit device.conf
```

**Build** — runs `sudo bash Mobuntu/build.sh -d <device>` in a background thread. Progress shown in status bar. Output captured and shown in sync pane after completion.

**Edit** — suspends the TUI, opens `device.conf` in `$EDITOR` (fallback: `nano`), resumes TUI on exit.

### Progress Bar

Live streaming progress for downloads via `requests`. Requires:

```bash
pip install requests
```

If `requests` is not installed the bar still renders but download operations fall back to a static message.

### Window Resize

devkit.py detects terminal resize and recreates all curses windows automatically. No restart needed.

### Paths devkit.py Resolves

| Variable | Value |
|----------|-------|
| `SCRIPT_DIR` | Directory containing `devkit.py` |
| `FORK_DIR` | `SCRIPT_DIR / "Mobuntu"` |
| `DEVICES_DIR` | `FORK_DIR / "devices"` |
| `SYNC_SCRIPT` | `SCRIPT_DIR / "sync.py"` |

---

## Device Configuration

### device.conf Format

```bash
# devices/<codename>/device.conf

DEVICE_CODENAME="beryllium"
DEVICE_BRAND="xiaomi"
DEVICE_MODEL="Poco F1"
DEVICE_SOC="sdm845"

DEVICE_SUITE="plucky"

KERNEL_APT_NAME="linux-image-6.18-sdm845"
KERNEL_HEADERS_APT_NAME="linux-headers-6.18-sdm845"
KERNEL_VERSION="6.18-sdm845"
KERNEL_IMAGE_URL="https://..."      # download-based fallback
KERNEL_HEADERS_URL="https://..."

FW_DEB="linux-firmware-xiaomi-beryllium-sdm845.deb"
FW_ARCHIVE_URL="https://..."        # download-based fallback

ALSA_UCM_URL="https://repo.mobian.org/..."
DEVICE_MASKED_SERVICES="alsa-state alsa-restore"

DEVICE_DISPLAYS="tianma ebbg"
DEVICE_DEFAULT_DISPLAY="tianma"
DEVICE_DTB_TIANMA="sdm845-xiaomi-beryllium-tianma.dtb"
DEVICE_DTB_EBBG="sdm845-xiaomi-beryllium-ebbg.dtb"

DEVICE_PACKAGES="abootimg zstd hexagonrpcd libqrtr-glib0"
DEVICE_SERVICES="hexagonrpcd grow-rootfs"
HEXAGONRPCD_AFTER="multi-user.target"
```

### All Fields Reference

| Field | Required | Description |
|-------|----------|-------------|
| `DEVICE_CODENAME` | ✅ | Codename — must match directory name |
| `DEVICE_BRAND` | ✅ | Manufacturer lowercase |
| `DEVICE_MODEL` | ✅ | Human-readable model |
| `DEVICE_SOC` | ✅ | SoC identifier |
| `DEVICE_SUITE` | ✅ | Default Ubuntu suite |
| `KERNEL_APT_NAME` | ✅ | Kernel apt package name |
| `KERNEL_HEADERS_APT_NAME` | ✅ | Headers apt package name |
| `KERNEL_VERSION` | ✅ | Version string (validated by build.sh) |
| `KERNEL_IMAGE_URL` | — | Download URL for kernel deb |
| `KERNEL_HEADERS_URL` | — | Download URL for headers deb |
| `FW_DEB` | ✅ | Firmware deb filename in `files/` |
| `FW_ARCHIVE_URL` | — | Download URL for firmware archive |
| `ALSA_UCM_URL` | — | Mobian alsa-ucm-conf deb URL |
| `DEVICE_MASKED_SERVICES` | — | Space-separated services to mask |
| `DEVICE_DISPLAYS` | — | Space-separated display variants |
| `DEVICE_DEFAULT_DISPLAY` | — | Default display variant name |
| `DEVICE_DTB_<VARIANT>` | — | DTB filename per variant (uppercase) |
| `DEVICE_PACKAGES` | — | Extra packages for this device |
| `DEVICE_SERVICES` | — | Services to enable |
| `HEXAGONRPCD_AFTER` | — | systemd After= for hexagonrpcd |

### Adding a New Device

1. Create `Mobuntu/devices/<codename>/device.conf` with all required fields
2. Create `Mobuntu/devices/<codename>/overlays/` for device-specific files
3. Place firmware deb in `Mobuntu/files/`
4. Press `r` in devkit to refresh, or restart devkit
5. Build with `sudo bash Mobuntu/build.sh -d <codename>`

---

## SDM845 Platform Notes

### hexagonrpcd

Must use systemd ordering `After=multi-user.target`. Do **not** use udev remoteproc gating — this causes a 60-second fastrpc thrash loop on SDM845. The ordering drop-in lives at:

```
overlays/etc/systemd/system/hexagonrpcd.service.d/mobuntu-ordering.conf
```

```ini
[Unit]
After=multi-user.target
```

### Audio

UCM2 maps from Mobian are required. The Mobian `alsa-ucm-conf` package must be installed and `alsa-state` / `alsa-restore` masked. This is handled by `final.sh` using `ALSA_UCM_URL` from device.conf.

### Suite Recommendations

| Suite | Ubuntu | SDM845 |
|-------|--------|--------|
| `plucky` | 25.04 | ✅ Recommended |
| `resolute` | 26.04 | ⚠️ Known WiFi/BT/audio regressions |

### Build Host

Ubuntu 24.04 required. Ubuntu 26.04 host has a QEMU segfault regression affecting arm64 chroots. Build inside WSL2 on Ubuntu 24.04.

---

## debos Notes

### Variable Passthrough

debos template variables are passed from `build.sh` via `-t key:value` flags and expanded in YAML using Go template syntax `{{ $varname }}`. This is the only reliable way to pass values into recipes.

The `environment:` block in debos `run` actions **only works with `command:`**, not `script:`. Using `script:` + `environment:` silently drops all env vars.

Correct pattern:

```yaml
- action: overlay
  source: scripts
  destination: /usr/local/sbin/

- action: run
  chroot: true
  command: DEVICE="{{ $device }}" bash /usr/local/sbin/fetch-firmware.sh
```

### Scratchsize

debos is invoked with `--scratchsize=10G`. Reduce if disk space is tight, increase for larger rootfs builds.

### fakemachine

debos fakemachine is disabled via `--disable-fakemachine`. Required for WSL2 compatibility.

---

## Firmware and Kernel Install Modes

The stack supports two install modes. Mode is determined by which fields are populated in device.conf:

**APT mode (upstream default):**
Kernel installed via `apt-get install $KERNEL_APT_NAME` from the Mobian repo. Firmware installed from `files/$FW_DEB` via `/opt/*.deb`. This is what arkadin91's upstream uses.

**Download mode (our addition):**
Kernel and firmware downloaded at build time from `$KERNEL_IMAGE_URL`, `$KERNEL_HEADERS_URL`, `$FW_ARCHIVE_URL` via `scripts/fetch-firmware.sh`. Used when bundling debs in `files/` is not practical.

Both modes coexist in device.conf. `final.sh` currently uses APT mode. `fetch-firmware.sh` implements download mode.
