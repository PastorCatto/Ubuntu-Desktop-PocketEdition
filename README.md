# Mobuntu Recipes

Multi-device Ubuntu ARM64 image builder for SDM845 phones.
Built on top of [arkadin91/mobuntu-recipes](https://github.com/arkadin91/mobuntu-recipes),
with multi-device scaffolding and Mobuntu Orange customizations.

## Requirements

- Ubuntu 24.04 host (build host — do NOT use 26.04, QEMU arm64 chroot regression)
- `debos` installed
- Network access during build (firmware + kernel fetched at build time)

## Usage

```sh
# Build for Xiaomi Poco F1 (beryllium) — confirmed working baseline
./build.sh -d beryllium

# Build for OnePlus 6T (fajita)
./build.sh -d fajita

# Skip rootfs stage, reuse existing tarball
./build.sh -d beryllium -i

# Override suite (e.g. force plucky on fajita)
./build.sh -d fajita -s plucky

# List available devices
./build.sh -h
```

## Device Support

| Codename   | Device         | Suite    | Status              |
|------------|----------------|----------|---------------------|
| beryllium  | Xiaomi Poco F1 | plucky   | ✅ Confirmed working |
| fajita     | OnePlus 6T     | resolute | ⚠️  Suite warning   |

## Adding a New Device

1. Create `devices/<codename>/device.conf` — see existing configs for schema
2. Create `devices/<codename>/overlays/` — add any device-specific udev rules,
   systemd units, or config files that should overlay on top of common overlays
3. Run `./build.sh -d <codename>`

## Suite Notes

- **plucky (25.04)** — recommended for all SDM845 devices
- **resolute (26.04)** — known regressions: WiFi, Bluetooth, audio on SDM845;
  build.sh requires double confirmation before proceeding

## Structure

```
build.sh                    # Entry point — loads device.conf, calls debos
rootfs.yaml                 # Stage 1: debootstrap + base packages
image.yaml                  # Stage 2: image creation, overlays, firmware, final config
packages/
  packages-base.yaml        # Base package list (hexagonrpcd, qcom utils, pipewire, etc.)
  packages-ubuntu-desktop.yaml
overlays/                   # Common overlays applied to all devices
  etc/systemd/system/
    hexagonrpcd.service.d/
      mobuntu-ordering.conf # Ensures After=multi-user.target
scripts/
  setup-user.sh             # User creation (upstream verbatim)
  update-apt.sh             # apt update + full-upgrade (upstream verbatim)
  fetch-firmware.sh         # Device-aware firmware + kernel download/install
  final.sh                  # Post-image config: alsa, extensions, grow-rootfs
devices/
  beryllium/
    device.conf             # Firmware URLs, kernel version, suite
    overlays/               # beryllium-specific udev rules
  fajita/
    device.conf             # Upstream hardcoded values, migrated here
    overlays/
```
