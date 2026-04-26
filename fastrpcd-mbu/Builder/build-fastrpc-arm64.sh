#!/bin/bash
# Mobuntu RC15 — build-fastrpc-arm64.sh
# Cross-compiles fastrpc for arm64 on an x86-64 WSL2 host.
# Produces: fastrpc-support_1.0.0-1_arm64.deb
#           libfastrpc1_1.0.0-1_arm64.deb
#           libfastrpc-dev_1.0.0-1_arm64.deb
#
# Prerequisites (this script installs them):
#   - fastrpc-1_0_0_tar.gz       (source: github.com/qualcomm/fastrpc v1.0.0)
#   - pkg-fastrpc-debian-latest_tar.gz  (debian packaging branch)
# Both should be in the same directory as this script.
#
# Usage:
#   chmod +x build-fastrpc-arm64.sh
#   ./build-fastrpc-arm64.sh
#
# Output: ./output/*.deb

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/fastrpc-build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
LOG_FILE="${BUILD_DIR}/build.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()   { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────

info "Mobuntu fastrpc arm64 build"
echo ""

[ -f "${SCRIPT_DIR}/fastrpc-1_0_0_tar.gz" ] || \
    die "Missing: fastrpc-1_0_0_tar.gz (put it next to this script)"
[ -f "${SCRIPT_DIR}/pkg-fastrpc-debian-latest_tar.gz" ] || \
    die "Missing: pkg-fastrpc-debian-latest_tar.gz (put it next to this script)"

if [ "$EUID" -ne 0 ]; then
    SUDO=sudo
else
    SUDO=""
fi

mkdir -p "${BUILD_DIR}" "${OUTPUT_DIR}"

# ── Install build dependencies ─────────────────────────────────────────────────

info "Installing build dependencies..."
$SUDO apt-get update -q
$SUDO apt-get install -y \
    gcc-aarch64-linux-gnu \
    libtool \
    autoconf \
    automake \
    debhelper \
    dh-autoreconf \
    pkgconf \
    cmake \
    wget \
    2>&1 | tee -a "${LOG_FILE}" | grep -E "^Setting up|^Processing" || true
ok "Build tools installed"

# ── Cross-compile libyaml for arm64 ───────────────────────────────────────────

info "Building libyaml 0.2.5 for arm64..."

LIBYAML_SRC="${BUILD_DIR}/libyaml-0.2.5"
LIBYAML_SYSROOT="/usr/aarch64-linux-gnu"

if [ ! -f "${LIBYAML_SYSROOT}/lib/libyaml.so" ]; then
    cd "${BUILD_DIR}"

    # Download from Ubuntu archive (doesn't need codeload.github.com)
    if [ ! -f libyaml-src.tar.gz ] || [ ! -s libyaml-src.tar.gz ]; then
        info "Downloading libyaml source..."
        wget -q "http://archive.ubuntu.com/ubuntu/pool/main/liby/libyaml/libyaml_0.2.5.orig.tar.gz" \
            -O libyaml-src.tar.gz || \
        wget -q "https://pyyaml.org/download/libyaml/yaml-0.2.5.tar.gz" \
            -O libyaml-src.tar.gz
    fi

    [ -s libyaml-src.tar.gz ] || die "Failed to download libyaml source"

    rm -rf "${LIBYAML_SRC}"
    tar -xzf libyaml-src.tar.gz
    [ -d "${LIBYAML_SRC}" ] || die "libyaml extraction failed — expected libyaml-0.2.5/"

    cd "${LIBYAML_SRC}"
    cmake -B build-arm64 \
        -DCMAKE_SYSTEM_NAME=Linux \
        -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
        -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
        -DCMAKE_INSTALL_PREFIX="${LIBYAML_SYSROOT}" \
        -DBUILD_SHARED_LIBS=ON \
        >> "${LOG_FILE}" 2>&1

    cmake --build build-arm64 -j"$(nproc)" >> "${LOG_FILE}" 2>&1
    $SUDO cmake --install build-arm64 >> "${LOG_FILE}" 2>&1

    ok "libyaml built: ${LIBYAML_SYSROOT}/lib/libyaml.so"
else
    ok "libyaml already present, skipping"
fi

# Write pkgconfig file (cmake install doesn't always create it)
$SUDO mkdir -p "${LIBYAML_SYSROOT}/lib/pkgconfig"
$SUDO tee "${LIBYAML_SYSROOT}/lib/pkgconfig/yaml-0.1.pc" > /dev/null << EOF
prefix=${LIBYAML_SYSROOT}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: yaml
Description: A YAML 1.1 parser and emitter library
Version: 0.2.5
Libs: -L\${libdir} -lyaml
Cflags: -I\${includedir}
EOF

# ── Extract sources ────────────────────────────────────────────────────────────

info "Extracting fastrpc sources..."

cd "${BUILD_DIR}"
rm -rf fastrpc-1.0.0 pkg-fastrpc-debian-latest

tar -xzf "${SCRIPT_DIR}/fastrpc-1_0_0_tar.gz"
tar -xzf "${SCRIPT_DIR}/pkg-fastrpc-debian-latest_tar.gz"

[ -d fastrpc-1.0.0 ]            || die "fastrpc source extraction failed"
[ -d pkg-fastrpc-debian-latest ] || die "debian packaging extraction failed"

# Merge debian/ and any newer source files from the debian branch
cp -r pkg-fastrpc-debian-latest/debian fastrpc-1.0.0/
# The debian/latest branch may have additional .c files not in v1.0.0 source
for f in fastrpc_config_parser.c; do
    [ -f "pkg-fastrpc-debian-latest/src/${f}" ] && \
        cp "pkg-fastrpc-debian-latest/src/${f}" "fastrpc-1.0.0/src/${f}" && \
        info "Copied newer: src/${f}"
done
for f in fastrpc_config_parser.h; do
    [ -f "pkg-fastrpc-debian-latest/inc/${f}" ] && \
        cp "pkg-fastrpc-debian-latest/inc/${f}" "fastrpc-1.0.0/inc/${f}"
done
if [ -d pkg-fastrpc-debian-latest/src/dspqueue ]; then
    mkdir -p fastrpc-1.0.0/src/dspqueue
    cp pkg-fastrpc-debian-latest/src/dspqueue/*.c fastrpc-1.0.0/src/dspqueue/ 2>/dev/null || true
fi

# Pin changelog to a clean version
cat > fastrpc-1.0.0/debian/changelog << 'CHANGELOG'
fastrpc (1.0.0-1) unstable; urgency=medium

  * Mobuntu build: cross-compiled for arm64 from fastrpc v1.0.0.

 -- Mobuntu Project <mobuntu@local>  Sat, 25 Apr 2026 22:00:00 +0000
CHANGELOG

ok "Sources merged"

# ── Build .deb packages ────────────────────────────────────────────────────────

info "Building arm64 .deb packages (this will take a minute)..."

cd "${BUILD_DIR}/fastrpc-1.0.0"

export PKG_CONFIG_PATH="${LIBYAML_SYSROOT}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${LIBYAML_SYSROOT}/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="${LIBYAML_SYSROOT}"
export CC=aarch64-linux-gnu-gcc
export DEB_BUILD_OPTIONS="nocheck notest"

dpkg-buildpackage \
    -a arm64 \
    -d \
    -b -uc -us \
    >> "${LOG_FILE}" 2>&1

ok "Build complete"

# ── Collect output ─────────────────────────────────────────────────────────────

info "Collecting .deb files..."
cp "${BUILD_DIR}"/*.deb "${OUTPUT_DIR}/" 2>/dev/null || true

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "Done. Output:"
ls -lh "${OUTPUT_DIR}"/*.deb 2>/dev/null || warn "No .deb files found — check ${LOG_FILE}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
info "Install on beryllium:"
echo "  scp ${OUTPUT_DIR}/*.deb mobian@10.0.0.3:~/"
echo "  ssh mobian@10.0.0.3 'sudo dpkg -i ~/fastrpc-support_*.deb ~/libfastrpc1_*.deb'"
