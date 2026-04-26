# How to Build fastrpc for Mobuntu

This guide explains how to reproduce the `fastrpc` arm64 `.deb` packages from source on an x86-64 Ubuntu host (WSL2 or native).

Everything here is open. No proprietary tools, no closed build systems. If you can run Ubuntu on x86-64, you can reproduce these packages exactly.

---

## What You Are Building

Three Debian packages cross-compiled for `arm64`:

| Package | What it contains |
|---------|-----------------|
| `libfastrpc1` | Shared libraries (`libadsprpc.so`, `libcdsprpc.so`, `libsdsprpc.so`, and default listeners) |
| `fastrpc-support` | Userspace daemons (`adsprpcd`, `cdsprpcd`, `sdsprpcd`) + systemd services + udev rules |
| `libfastrpc-dev` | Development headers and unversioned `.so` symlinks |

---

## Prerequisites

An x86-64 machine running Ubuntu 22.04, 24.04 (noble), or 26.04 (resolute). WSL2 on Windows works fine.

You need two source archives. Download them from their upstream locations:

```
fastrpc v1.0.0 source:
  https://github.com/qualcomm/fastrpc/archive/refs/tags/v1.0.0.tar.gz
  → save as: fastrpc-1_0_0_tar.gz

fastrpc Debian packaging (latest branch):
  https://github.com/qualcomm-linux/pkg-fastrpc/archive/refs/heads/debian/latest.tar.gz
  → save as: pkg-fastrpc-debian-latest_tar.gz
```

Place both files in the same directory as `build-fastrpc-arm64.sh`.

> **Note on GitHub downloads:** GitHub archive downloads redirect through `codeload.github.com`.
> If your environment blocks that domain, download the files on another machine and copy them over,
> or use a browser to download them manually.

---

## Build Steps

### 1. Get the build script

The script `build-fastrpc-arm64.sh` is included in the Mobuntu repository under the root directory (sibling of the `Mobuntu/` folder).

### 2. Make it executable

```bash
chmod +x build-fastrpc-arm64.sh
```

### 3. Run it

```bash
./build-fastrpc-arm64.sh
```

The script is fully automated. It will:

1. Install host build dependencies via `apt-get`:
   - `gcc-aarch64-linux-gnu` — ARM64 cross-compiler
   - `libtool`, `autoconf`, `automake`, `dh-autoreconf` — GNU build system
   - `debhelper` — Debian package build helper
   - `pkgconf`, `cmake` — used for libyaml cross-build

2. Cross-compile `libyaml 0.2.5` for arm64 from source  
   *(Source downloaded from `archive.ubuntu.com` — no GitHub redirect needed)*

3. Extract and merge the fastrpc source with the Debian packaging branch

4. Apply a `debian/rules` patch to skip `dh_shlibdeps`  
   *(See [Known Build Quirks](#known-build-quirks) below)*

5. Run `dpkg-buildpackage -a arm64 -d -b -uc -us`

6. Collect the output `.deb` files into `./output/`

---

## Expected Output

After a successful build, `./output/` will contain:

```
fastrpc-support_1.0.0-1_arm64.deb
fastrpc-support-dbgsym_1.0.0-1_arm64.ddeb
libfastrpc1_1.0.0-1_arm64.deb
libfastrpc1-dbgsym_1.0.0-1_arm64.ddeb
libfastrpc-dev_1.0.0-1_arm64.deb
fastrpc_1.0.0-1_arm64.buildinfo
fastrpc_1.0.0-1_arm64.changes
```

Build time is approximately 2–5 minutes depending on host speed.

---

## Staging into Mobuntu

Once built, copy the `.deb` files into the Mobuntu tree:

```bash
mkdir -p Mobuntu/packages/fastrpc
cp output/fastrpc-support_*.deb    Mobuntu/packages/fastrpc/
cp output/libfastrpc1_*.deb        Mobuntu/packages/fastrpc/
cp output/libfastrpc-dev_*.deb     Mobuntu/packages/fastrpc/
```

`install-fastrpc-device.sh` will pick them up from this location during the debos device build.

---

## Installing on Device (Manual)

If installing directly on a running Mobian/Mobuntu device over SSH:

```bash
scp output/*.deb mobian@<device-ip>:~/

ssh mobian@<device-ip>
sudo dpkg -i --force-depends ~/libfastrpc1_1.0.0-1_arm64.deb
sudo dpkg -i --force-depends ~/fastrpc-support_1.0.0-1_arm64.deb
```

`--force-depends` is needed because the `Depends:` field for libc6 is empty in the cross-built package. See [Known Build Quirks](#known-build-quirks).

---

## What the Script Does In Detail

### libyaml cross-build

`fastrpc` links against `libyaml` at build time (for config file parsing). The arm64 version of `libyaml-dev` is only available from `ports.ubuntu.com`, which requires manual apt source setup for arm64 multiarch on an `archive.ubuntu.com`-based install.

To avoid that complexity, the script downloads the `libyaml 0.2.5` source tarball directly from the Ubuntu archive pool and cross-compiles it using cmake:

```bash
cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
    -DCMAKE_INSTALL_PREFIX=/usr/aarch64-linux-gnu \
    -DBUILD_SHARED_LIBS=ON
```

The result is installed to `/usr/aarch64-linux-gnu/lib/` and a pkgconfig file is written to `/usr/aarch64-linux-gnu/lib/pkgconfig/yaml-0.1.pc` so that the fastrpc build system finds it.

### Source merge

The fastrpc upstream source (`v1.0.0`) does not include a `debian/` directory — that lives in the separate `pkg-fastrpc` packaging repository. The script merges them:

```bash
tar -xzf fastrpc-1_0_0_tar.gz           # → fastrpc-1.0.0/
tar -xzf pkg-fastrpc-debian-latest_tar.gz  # → pkg-fastrpc-debian-latest/
cp -r pkg-fastrpc-debian-latest/debian fastrpc-1.0.0/
```

Newer source files present in the packaging branch (e.g. `fastrpc_config_parser.c`) are also copied into the source tree.

The changelog is replaced with a clean Mobuntu-specific entry to pin the version at `1.0.0-1`.

### Cross-compilation environment

```bash
export CC=aarch64-linux-gnu-gcc
export PKG_CONFIG_PATH=/usr/aarch64-linux-gnu/lib/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/aarch64-linux-gnu/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu
export DEB_BUILD_OPTIONS="nocheck notest"

dpkg-buildpackage -a arm64 -d -b -uc -us
```

- `-a arm64` — sets the host (target) architecture
- `-d` — skips build-dependency checks (we satisfy them manually)
- `-b` — binary-only build (no source package)
- `-uc -us` — do not sign the package or source

---

## Known Build Quirks

### `dh_shlibdeps` and the `--force-depends` workaround

During packaging, `dh_shlibdeps` scans the compiled arm64 binaries and tries to resolve their shared library dependencies (e.g. `libc6`, `libm`) against the host's dpkg database.

On an `archive.ubuntu.com`-based x86-64 host, arm64 packages are not available — they live on `ports.ubuntu.com`, which requires adding a separate apt source entry and running `dpkg --add-architecture arm64`. This is possible but adds setup complexity.

To avoid it, the build script patches `debian/rules` before building:

```makefile
override_dh_shlibdeps:
	true
```

This skips the dependency scan entirely. The resulting `.deb` files have empty `Depends:` fields for shared library deps. This is safe for Mobuntu's use case: any Ubuntu arm64 rootfs already has `libc6` and `libm` installed, so `dpkg -i --force-depends` succeeds without issue.

**If you want fully correct `.deb` files** (with proper `Depends:` entries), set up arm64 multiarch on the host first and omit the patch:

```bash
sudo dpkg --add-architecture arm64

# Edit /etc/apt/sources.list to add:
# deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports noble main restricted universe

sudo apt update
sudo apt install libc6:arm64 libc6-dev:arm64

# Then run dpkg-buildpackage without the debian/rules patch
```

---

## Verifying the Output

Check that the binaries are genuinely arm64:

```bash
file output/fastrpc-support_1.0.0-1_arm64.deb
# Should show: Debian binary package (format 2.0)

dpkg-deb -c output/fastrpc-support_1.0.0-1_arm64.deb
# Lists: ./usr/sbin/adsprpcd  ./usr/sbin/cdsprpcd  ./usr/sbin/sdsprpcd

dpkg-deb -x output/fastrpc-support_1.0.0-1_arm64.deb /tmp/fastrpc-check
file /tmp/fastrpc-check/usr/sbin/adsprpcd
# Should show: ELF 64-bit LSB pie executable, ARM aarch64
```

---

## Reproducibility

This build is fully reproducible from the two source archives listed above plus a stock Ubuntu x86-64 install. No proprietary SDKs, no Qualcomm developer accounts, no closed toolchains.

The only non-reproducible element is timing — the build log timestamp and the changelog date are fixed at `2026-04-25` in the script. The binary content of the `.deb` files is deterministic given the same compiler version.

**Build environment used for the Mobuntu RC15 packages:**
- Host: Ubuntu 24.04 (Noble) x86-64, WSL2 (Windows 11)
- `gcc-aarch64-linux-gnu`: 13.3.0
- `debhelper`: 13.14.1
- `fastrpc`: v1.0.0 (`a7f3b2c` — check `.buildinfo` for exact hash)
- `libyaml`: 0.2.5

The `.buildinfo` file in `./output/` records the exact package versions of all build tools used and can be used to reproduce the build environment precisely.

---

## Sources and Licenses

| Component | Source | License |
|-----------|--------|---------|
| fastrpc | https://github.com/qualcomm/fastrpc | BSD-3-Clause |
| pkg-fastrpc (Debian packaging) | https://github.com/qualcomm-linux/pkg-fastrpc | BSD-3-Clause |
| libyaml | https://github.com/yaml/libyaml | MIT |
| build-fastrpc-arm64.sh | Mobuntu repo (this repo) | MIT |

The full license text for fastrpc is included in the installed package at `/usr/share/doc/libfastrpc1/copyright`.
