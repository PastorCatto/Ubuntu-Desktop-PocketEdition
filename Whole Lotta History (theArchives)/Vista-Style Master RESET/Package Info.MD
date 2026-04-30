# Mobuntu — fastrpc Package Info

This document describes the Qualcomm FastRPC userspace package set built for Mobuntu RC15.
These packages are cross-compiled from source for `arm64` on an `x86-64` host (WSL2).

---

## What Is fastrpc?

FastRPC is Qualcomm's mechanism for the Linux application processor (AP) to offload compute to the DSP cores — ADSP (audio), CDSP (compute/AI), and SDSP (SLPI/sensors). It works by sending remote procedure calls from the kernel's `fastrpc` driver to userspace daemons, which relay them to the DSP via shared memory.

On SDM845 devices (Xiaomi Poco F1, OnePlus 6/6T), enabling fastrpc is the prerequisite for:
- Fixing the SLPI crash loop (sensor hub currently restarts every ~40 s)
- Future sensor support via CHRE
- CDSP compute offload (AI/ML inference)

---

## Sources

| Component | Version | Upstream | License |
|-----------|---------|----------|---------|
| fastrpc | 1.0.0 | https://github.com/qualcomm/fastrpc/releases/tag/v1.0.0 | BSD-3-Clause |
| debian packaging | latest (2026-03-18) | https://github.com/qualcomm-linux/pkg-fastrpc | BSD-3-Clause |
| libyaml | 0.2.5 | http://archive.ubuntu.com/ubuntu/pool/main/liby/libyaml/libyaml_0.2.5.orig.tar.gz | MIT |

**Debian package maintainer:** Robie Basak `<robie.basak@oss.qualcomm.com>` (Qualcomm / Canonical)  
**Mobuntu build maintainer:** Mobuntu Project  
**Debian NEW queue status:** `fastrpc` was submitted to Debian NEW in October 2025. `hexagon-dsp-binaries` (companion package) entered unstable February 2026. These packages are not yet in Ubuntu or Debian stable.

---

## Packages

### `libfastrpc1_1.0.0-1_arm64.deb` — Runtime Libraries

**Size:** ~186 KB  
**Required:** Yes — `fastrpc-support` depends on this

**Installs to rootfs:**

```
/usr/lib/aarch64-linux-gnu/
    libadsprpc.so.1.0.0      — ADSP RPC client library
    libadsprpc.so.1          → libadsprpc.so.1.0.0
    libcdsprpc.so.1.0.0      — CDSP RPC client library
    libcdsprpc.so.1          → libcdsprpc.so.1.0.0
    libsdsprpc.so.1.0.0      — SDSP/SLPI RPC client library
    libsdsprpc.so.1          → libsdsprpc.so.1.0.0
    libadsp_default_listener.so.1.0.0   — ADSP default listener
    libadsp_default_listener.so.1       → above
    libcdsp_default_listener.so.1.0.0   — CDSP default listener
    libcdsp_default_listener.so.1       → above
    libsdsp_default_listener.so.1.0.0   — SDSP default listener
    libsdsp_default_listener.so.1       → above
```

These libraries are used by applications that talk to the DSP (e.g. sensor daemons, CHRE, compute offload).

---

### `fastrpc-support_1.0.0-1_arm64.deb` — Daemons and System Integration

**Size:** ~6 KB  
**Required:** Yes — contains the daemons that bridge the kernel driver to DSP

**Installs to rootfs:**

```
/usr/sbin/
    adsprpcd     — ADSP relay daemon
    cdsprpcd     — CDSP relay daemon
    sdsprpcd     — SDSP/SLPI relay daemon

/usr/lib/systemd/system/
    adsprpcd.service
    cdsprpcd.service
    sdsprpcd.service

/usr/lib/udev/rules.d/
    60-fastrpc-support.rules   — sets permissions on /dev/fastrpc-* nodes
```

**What the daemons do:** Each daemon opens the corresponding `/dev/fastrpc-{adsp,cdsp,sdsp}` character device and manages the shared memory transport between the kernel's `fastrpc` driver and the DSP-side firmware. Without these running, any attempt to call a remote procedure on the DSP will fail with `ENODEV`.

**Note:** `install-fastrpc-device.sh` enables `adsprpcd` and `cdsprpcd` services. `sdsprpcd` is present but not enabled — SLPI support requires the SDSP fastrpc shell binary and a functioning sensor hub daemon (e.g. CHRE), which is a separate work item.

---

### `libfastrpc-dev_1.0.0-1_arm64.deb` — Development Headers

**Size:** ~21 KB  
**Required:** No — only needed if building software that calls into the DSP

**Installs to rootfs:**

```
/usr/include/
    fastrpc.h
    remote.h
    rpcmem.h
    (and other fastrpc API headers)

/usr/lib/aarch64-linux-gnu/
    libadsprpc.so    → libadsprpc.so.1  (unversioned symlink for -l flags)
    libcdsprpc.so    → libcdsprpc.so.1
    libsdsprpc.so    → libsdsprpc.so.1
    ...
```

You do not need this package on the device for runtime. It is only needed if you are compiling software that uses `#include <fastrpc.h>` or links against `-ladsprpc`.

---

### Debug Symbol Packages (`.ddeb`)

Not required for normal use. Keep them if you want `gdb` backtraces from fastrpc crashes.

| File | Contents |
|------|----------|
| `fastrpc-support-dbgsym_1.0.0-1_arm64.ddeb` | Debug symbols for adsprpcd/cdsprpcd/sdsprpcd |
| `libfastrpc1-dbgsym_1.0.0-1_arm64.ddeb` | Debug symbols for libadsprpc/libcdsprpc/libsdsprpc |

---

## DSP Binaries (Separate — Not in These .debs)

The `.deb` packages above provide the **AP-side** userspace. The DSP also needs its own userspace, which lives on the DSP-side flash and is loaded by the fastrpc shell mechanism.

These are shipped separately as `firmware/xiaomi-beryllium/dsp.tar.gz` in the Mobuntu tree:

```
usr/share/qcom/sdm845/Xiaomi/beryllium/
    adsp/
        fastrpc_shell_0              — ADSP-side fastrpc shell binary
        libsysmon_skel.so            — sysmon skeleton
        libsysmondomain_skel.so
        libstabilitydomain_skel.so
        map_adsp_aDSP.txt            — firmware manifest
        (audio codec .so files)
    cdsp/
        fastrpc_shell_3              — CDSP-side fastrpc shell binary
        libsysmon_skel.so
        libbenchmark_skel.so
        (video processing libs)
    sdsp/
        fastrpc_shell_2              — SDSP/SLPI-side fastrpc shell binary
        libchre_slpi_skel.so         — CHRE sensor hub skeleton
        libFastRPC_UTF_Forward_800s_sdm845_skel.so
        chre_drv_bt.so               — CHRE Bluetooth driver
        chre_drv_wifi.so             — CHRE WiFi driver
        chre_drv_loc.so              — CHRE location driver
        chre_drv_modem.so            — CHRE modem driver
```

**Source:** Extracted from MIUI 12 V12.0.3.0.QEJMIXM (`dsp.img`, ext4 partition).  
**Device:** Xiaomi Poco F1 (beryllium), SDM845.  
**File count:** 65 files, 9.2 MB compressed.

These are proprietary Qualcomm/Xiaomi binaries. They are redistributed under the same terms as other vendor firmware blobs used in mainline Linux — no explicit redistribution license; included because they are required for hardware function and have no open-source equivalent.

---

## Where Everything Goes in the Mobuntu Tree

```
Mobuntu/
├── firmware/
│   └── xiaomi-beryllium/
│       ├── dsp.tar.gz          ← DSP-side binaries (sdsp/adsp/cdsp shells + skels)
│       ├── rfsa.tar.gz         ← rfsa/adsp skel libs from vendor partition (optional)
│       └── firmware.tar.gz     ← Main firmware blobs (git-cloned by stage-firmware-git.sh)
│
└── packages/
    └── fastrpc/
        ├── fastrpc-support_1.0.0-1_arm64.deb   ← daemons
        ├── libfastrpc1_1.0.0-1_arm64.deb        ← runtime libs
        └── libfastrpc-dev_1.0.0-1_arm64.deb     ← dev headers (optional)
```

`install-fastrpc-device.sh` reads from both of these locations during the debos device build.

---

## Install Order

Install in this order on the device (`--force-depends` is needed because `dh_shlibdeps` was skipped during cross-compilation — see Build Notes):

```bash
sudo dpkg -i --force-depends libfastrpc1_1.0.0-1_arm64.deb
sudo dpkg -i --force-depends fastrpc-support_1.0.0-1_arm64.deb
# Optional:
sudo dpkg -i --force-depends libfastrpc-dev_1.0.0-1_arm64.deb
```

Or copy all `.deb` files to the device and let `install-fastrpc-device.sh` handle it during the debos build.

---

## Build Notes

**Built with:** `dpkg-buildpackage -a arm64 -d -b -uc -us`  
**Host:** Ubuntu 24.04 (Noble) x86-64 (WSL2)  
**Cross-compiler:** `gcc-aarch64-linux-gnu` 13.3.0  
**libyaml:** Cross-compiled from source (v0.2.5) via cmake — `ports.ubuntu.com` (which serves `libyaml-dev:arm64`) is not accessible from `archive.ubuntu.com` without manual apt source surgery.  

**`dh_shlibdeps` bypass:** The `debian/rules` file has an `override_dh_shlibdeps: true` override applied before packaging. This skips automatic `Depends:` generation for shared library dependencies (`libc6`, `libm`). These dependencies exist on any functional Ubuntu arm64 rootfs and do not need to be declared for Mobuntu's use case. The override does not affect the correctness of the built binaries.

**Reproduce this build:**

```bash
# Requires: fastrpc-1_0_0_tar.gz + pkg-fastrpc-debian-latest_tar.gz
# in the same directory as the script.

chmod +x build-fastrpc-arm64.sh
./build-fastrpc-arm64.sh
```

Build script: `build-fastrpc-arm64.sh` (included in Mobuntu repo)

---

## Integration Status (RC15)

| Component | Status |
|-----------|--------|
| `libfastrpc1` in rootfs | ✅ Via `install-fastrpc-device.sh` |
| `fastrpc-support` in rootfs | ✅ Via `install-fastrpc-device.sh` |
| `adsprpcd` service enabled | ✅ |
| `cdsprpcd` service enabled | ✅ |
| `sdsprpcd` service enabled | ⏳ Pending SLPI investigation |
| DSP binaries staged (`dsp.tar.gz`) | ✅ |
| `rfsa.tar.gz` skel libs | ⏳ Optional, from live vendor partition |
| `install-fastrpc-device.sh` wired into `qcom.yaml` | ⏳ Pending RC16 |
| SLPI crash loop resolved | ❌ Ongoing — needs CHRE daemon + sdsp shell |

---

## References

- fastrpc upstream: https://github.com/qualcomm/fastrpc
- Debian packaging: https://github.com/qualcomm-linux/pkg-fastrpc
- hexagon-dsp-binaries (companion, Debian unstable): https://tracker.debian.org/pkg/hexagon-dsp-binaries
- Debian NEW tracker: https://ftp-master.debian.org/new/fastrpc_1.0.0-1.html
- SDM845 mainline firmware: https://gitlab.com/sdm845-mainline/firmware-xiaomi-beryllium
- Mobuntu Discord: https://discord.gg/RZV2HveyBg
