# Mobuntu Orange — Changelog
**Grand Developer Kit Reset — May 1, 2026**

---

## Summary

Mobuntu Orange has transitioned from a standalone RC-numbered build pipeline to a wrapper layer built directly on top of **arkadin91/mobuntu-recipes**. This is the foundation for all future development.

---

## Architecture Shift

The legacy RC pipeline (RC1–RC17) is retired as a development baseline. All future versions build on top of upstream `arkadin91/mobuntu-recipes`, with Mobuntu Orange customizations applied as a clean layer on top.

| Before | After |
|--------|-------|
| Standalone 5-script bash pipeline | Wrapper on arkadin91/mobuntu-recipes |
| Manual upstream tracking | `sync.py` auto-pulls and merges upstream |
| Hardcoded device values in scripts | Per-device `device.conf` files |
| RC-versioned release branches | Continuous integration on upstream HEAD |

**Build performance:** arkadin91's debos pipeline is approximately 50% faster with a 60% reduction in total build time versus the legacy RC pipeline.

---

## What's New

### Multi-Device Support
- `devices/beryllium/` — Xiaomi Poco F1, plucky, confirmed booting
- `devices/fajita/` — OnePlus 6T, resolute, confirmed booting
- `devices/enchilada/` — OnePlus 6, stubbed, pending validation

### `build.sh` — Multi-Device Entrypoint
Replaces upstream's minimal single-device script with full argument parsing, device conf loading, suite override support, resolute double-confirmation gate, and debos variable passthrough.

### `sync.py` — Upstream Sync Engine
Pulls latest upstream, extracts hardcoded device vars, updates device confs, and tracks sync state via SHA comparison. Pinned files are never overwritten.

### `devkit.py` — TUI Control Panel
Split-pane curses interface for managing devices, triggering syncs, and launching builds. Includes live download progress bar via streaming.

### Bug Fix — debos environment passthrough
debos silently ignores environment blocks on script actions. Fixed by overlaying scripts into the rootfs and calling them via command with template-expanded inline variables.

---

## Upstream Baseline

- **Upstream:** arkadin91/mobuntu-recipes — main branch
- **Kernel:** linux-image-6.18-sdm845 via Mobian apt repo
- **Firmware:** bundled debs in files/ installed via /opt/*.deb
- **Audio fix:** Mobian alsa-ucm-conf + mask alsa-state, alsa-restore
- **Suite:** upstream defaults to resolute — Mobuntu Orange defaults to plucky for SDM845 stability
