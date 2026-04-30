# Mobuntu Build System — CLI Reference

## build.sh

Entry point for all image builds. Loads device config, validates environment,
runs debos in two stages (rootfs → image).

```
./build.sh -d <device> [-s <suite>] [-i] [-h]
```

---

## Flags

### `-d <device>` — Device codename (required)

Selects which device to build for. Must match a directory under `devices/`.

```sh
./build.sh -d beryllium      # Xiaomi Poco F1
./build.sh -d fajita         # OnePlus 6T
```

Loads `devices/<device>/device.conf` for all build parameters.
Errors out immediately if no config exists.

---

### `-s <suite>` — Ubuntu suite override (optional)

Overrides the `DEVICE_SUITE` value in `device.conf`.
Useful for testing a different Ubuntu release without editing config files.

```sh
./build.sh -d beryllium -s plucky      # Ubuntu 25.04 (recommended)
./build.sh -d beryllium -s resolute    # Ubuntu 26.04 (experimental — triggers warning gate)
./build.sh -d beryllium -s noble       # Ubuntu 24.04 (unsupported — hexagonrpcd unavailable)
```

If `-s resolute` is passed (or `DEVICE_SUITE=resolute` in device.conf),
the build will pause and require two manual confirmations before proceeding:

```
Type YES to confirm resolute:
Type RESOLUTE to confirm again:
```

This gate exists because resolute has known SDM845 regressions affecting
WiFi, Bluetooth, and audio on most devices.

---

### `-i` — Image only (optional)

Skips Stage 1 (rootfs/debootstrap) and goes straight to Stage 2 (image creation).
Requires a rootfs tarball from a previous run to already exist.

```sh
./build.sh -d beryllium -i
```

Useful when:
- You changed overlays, scripts, or packages but not the base debootstrap
- Iterating on final.sh or fetch-firmware.sh without waiting for a full rootfs rebuild
- The rootfs stage succeeded but the image stage failed

The expected tarball name is `mobuntu-rootfs-<device>.tar.gz` in the working directory.

---

### `-h` — Help

Prints usage and lists all available devices with their model names.

```sh
./build.sh -h
```

---

## Combining flags

```sh
# Build Poco F1 on resolute, image only (rootfs already built)
./build.sh -d beryllium -s resolute -i

# Build OnePlus 6T forcing plucky instead of its default resolute
./build.sh -d fajita -s plucky
```

---

## Output files

| File | Description |
|---|---|
| `mobuntu-<device>-YYYYMMDD.img` | Full GPT image (10GB) |
| `root-mobuntu-<device>-YYYYMMDD.img` | Extracted, compacted ext4 rootfs — flash this |
| `mobuntu-rootfs-<device>.tar.gz` | Rootfs tarball (reused by `-i`) |

---

## Build stages

**Stage 1 — rootfs** (`rootfs.yaml`)
Runs debootstrap, installs base packages (qcom utils, hexagonrpcd, pipewire, etc.),
creates the mobuntu user, enables the mobian extrepo, packs a tarball.

**Stage 2 — image** (`image.yaml`)
Unpacks the tarball, applies common overlays, applies device overlays,
installs ubuntu-desktop, runs apt full-upgrade, fetches and installs
device firmware and kernel, runs final configuration, extracts the rootfs partition.

---

## device.conf reference

Located at `devices/<codename>/device.conf`.

```sh
DEVICE_CODENAME="beryllium"      # Must match directory name
DEVICE_BRAND="xiaomi"            # Used for display only
DEVICE_MODEL="Poco F1"           # Used for display only
DEVICE_SUITE="plucky"            # Default suite; overridden by -s

FW_ARCHIVE_URL="https://..."     # .tar.gz firmware archive
KERNEL_IMAGE_URL="https://..."   # linux-image .deb
KERNEL_HEADERS_URL="https://..." # linux-headers .deb
KERNEL_VERSION="7.1.0-rc1-sdm845"
```

All URL vars are required. Build will exit with an error if any are missing or empty.

---

## Suite compatibility

| Suite | Ubuntu | SDM845 status |
|---|---|---|
| `noble` | 24.04 LTS | Unsupported — hexagonrpcd 0.4.0 unavailable |
| `plucky` | 25.04 | Recommended — stable baseline |
| `resolute` | 26.04 | Experimental — WiFi/BT/audio regressions on SDM845 |

Build host must be Ubuntu 24.04. Do not build on 26.04 — QEMU arm64 chroot segfaults.
