#!/bin/bash
# =============================================================================
# mbu — Mobuntu Bundle Updater
# Updates and repacks firmware/xiaomi-beryllium/firmware.tar.gz
# from upstream sources. DSP bundle is handled separately.
#
# Usage:
#   ./mbu [--device <codename>] [--dry-run] [--force] [--verbose]
#
# Options:
#   --device   Device codename (default: autodetected from build.env)
#   --dry-run  Show what would change without modifying anything
#   --force    Rebuild bundle even if nothing changed
#   --verbose  Show full git log and curl output
#
# Sources:
#   sdm845-mainline/firmware-xiaomi-beryllium (gitlab.com)
#   linux-firmware GPU blobs (kernel.org)
#   alsa-ucm-conf (repo.mobian.org apt)
#
# Output:
#   firmware/<brand>-<codename>/firmware.tar.gz  — updated bundle
#   firmware/<brand>-<codename>/firmware.lock    — commit/version lockfile
#   firmware/<brand>-<codename>/firmware-manifest.json — full blob manifest
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colour output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[mbu]${NC} $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
changed() { echo -e "${CYAN}[NEW ]${NC} $*"; }
die()     { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
dry()     { echo -e "${YELLOW}[DRY ]${NC} $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
DEVICE_CODENAME=""
DEVICE_BRAND=""
DRY_RUN=false
FORCE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)  DEVICE_CODENAME="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true;         shift   ;;
        --force)   FORCE=true;           shift   ;;
        --verbose) VERBOSE=true;         shift   ;;
        --help|-h)
            sed -n '3,20p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Load build.env for device info if not specified ───────────────────────────
if [ -z "$DEVICE_CODENAME" ]; then
    [ -f "$SCRIPT_DIR/build.env" ] || die "No --device specified and no build.env found."
    source "$SCRIPT_DIR/build.env"
fi
[ -n "$DEVICE_CODENAME" ] || die "DEVICE_CODENAME not set."
[ -n "$DEVICE_BRAND"    ] || die "DEVICE_BRAND not set."

# ── Load device config for FIRMWARE_REPO ─────────────────────────────────────
DEVICE_CONF="$SCRIPT_DIR/devices/${DEVICE_BRAND}-${DEVICE_CODENAME}.conf"
[ -f "$DEVICE_CONF" ] || {
    # Try searching for any conf matching the codename
    DEVICE_CONF=$(find "$SCRIPT_DIR/devices" -name "*${DEVICE_CODENAME}*.conf" | head -1)
    [ -f "$DEVICE_CONF" ] || die "No device config found for $DEVICE_CODENAME"
}
source "$DEVICE_CONF"

# ── Paths ─────────────────────────────────────────────────────────────────────
FW_DIR="${SCRIPT_DIR}/firmware/${DEVICE_BRAND}-${DEVICE_CODENAME}"
FW_BUNDLE="${FW_DIR}/firmware.tar.gz"
FW_LOCK="${FW_DIR}/firmware.lock"
FW_MANIFEST="${FW_DIR}/firmware-manifest.json"
FW_STAGE=$(mktemp -d /tmp/mbu-stage-XXXX)
FW_PREV=$(mktemp -d /tmp/mbu-prev-XXXX)

trap 'rm -rf "$FW_STAGE" "$FW_PREV"' EXIT

mkdir -p "$FW_DIR"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  mbu — Mobuntu Bundle Updater${NC}"
echo -e "  Device:  ${CYAN}${DEVICE_NAME:-$DEVICE_CODENAME}${NC}"
echo -e "  Target:  ${CYAN}${FW_BUNDLE}${NC}"
[ "$DRY_RUN" = true ] && echo -e "  Mode:    ${YELLOW}DRY RUN — no files will be modified${NC}"
[ "$FORCE"   = true ] && echo -e "  Mode:    ${YELLOW}FORCE — rebuilding regardless of changes${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ── Read existing lockfile ────────────────────────────────────────────────────
PREV_GIT_COMMIT=""
PREV_FW_DATE=""
if [ -f "$FW_LOCK" ]; then
    PREV_GIT_COMMIT=$(grep "^git_commit=" "$FW_LOCK" | cut -d= -f2)
    PREV_FW_DATE=$(grep "^bundle_date=" "$FW_LOCK" | cut -d= -f2)
    info "Existing bundle: commit ${PREV_GIT_COMMIT:0:12}  built ${PREV_FW_DATE}"
else
    info "No existing lockfile — fresh bundle will be created."
fi

# ── Extract previous bundle for diffing ──────────────────────────────────────
if [ -f "$FW_BUNDLE" ]; then
    tar -xzf "$FW_BUNDLE" -C "$FW_PREV/" 2>/dev/null || true
fi

# ── Track changes ─────────────────────────────────────────────────────────────
CHANGES=()
UNCHANGED=()
NEW_FILES=()
REMOVED_FILES=()

# ── Step 1: Git firmware repo ─────────────────────────────────────────────────
GIT_COMMIT=""
GIT_COMMIT_DATE=""
GIT_COMMIT_MSG=""

if [ -n "${FIRMWARE_REPO:-}" ]; then
    info "Fetching firmware git repo..."
    GIT_TMP=$(mktemp -d /tmp/mbu-git-XXXX)
    trap 'rm -rf "$FW_STAGE" "$FW_PREV" "$GIT_TMP"' EXIT

    if [ "$VERBOSE" = true ]; then
        git clone --depth=1 "$FIRMWARE_REPO" "$GIT_TMP/fw"
    else
        git clone --depth=1 --quiet "$FIRMWARE_REPO" "$GIT_TMP/fw" 2>&1 | \
            grep -v "^$" || true
    fi

    GIT_COMMIT=$(git -C "$GIT_TMP/fw" rev-parse HEAD)
    GIT_COMMIT_DATE=$(git -C "$GIT_TMP/fw" log -1 --format="%ci" HEAD)
    GIT_COMMIT_MSG=$(git -C "$GIT_TMP/fw" log -1 --format="%s" HEAD)

    info "Latest commit: ${GIT_COMMIT:0:12}  ${GIT_COMMIT_DATE}"
    info "Message: $GIT_COMMIT_MSG"

    if [ "$GIT_COMMIT" = "$PREV_GIT_COMMIT" ] && [ "$FORCE" = false ]; then
        info "Git repo unchanged since last bundle — skipping git layer."
    else
        [ "$GIT_COMMIT" != "$PREV_GIT_COMMIT" ] && \
            CHANGES+=("git: ${PREV_GIT_COMMIT:0:12} → ${GIT_COMMIT:0:12}")
        # Copy lib/ and usr/ from git repo into staging
        [ -d "$GIT_TMP/fw/lib" ] && cp -r "$GIT_TMP/fw/lib/." "$FW_STAGE/"
        [ -d "$GIT_TMP/fw/usr" ] && cp -r "$GIT_TMP/fw/usr/." "$FW_STAGE/"
        ok "Git firmware staged ($(find $GIT_TMP/fw -name "*.mbn" -o -name "*.jsn" | wc -l) blobs)"
    fi
else
    warn "FIRMWARE_REPO not set in device config — skipping git layer."
fi

# ── Step 2: GPU firmware from kernel.org ──────────────────────────────────────
KERNEL_ORG="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain"

# Only fetch unsigned GPU blobs from kernel.org — these are not device-specific
# and not included in the sdm845-mainline firmware repo.
# a630_zap.mbn IS device-specific and comes from the git repo above — do not fetch here.
GPU_BLOBS=(
    "qcom/a630_sqe.fw"
    "qcom/a630_gmu.bin"
)

info "Fetching GPU firmware from kernel.org..."
mkdir -p "$FW_STAGE/lib/firmware/qcom/sdm845/${DEVICE_CODENAME}"
mkdir -p "$FW_STAGE/lib/firmware/qcom"

for blob in "${GPU_BLOBS[@]}"; do
    dest_dir="$FW_STAGE/lib/firmware/$(dirname $blob)"
    dest_file="$FW_STAGE/lib/firmware/${blob}"
    mkdir -p "$dest_dir"

    if [ "$VERBOSE" = true ]; then
        curl -fsSL -o "$dest_file" "${KERNEL_ORG}/${blob}" && true || {
            warn "  Not found on kernel.org: $blob (non-fatal)"
            continue
        }
    else
        curl -fsSL --silent -o "$dest_file" "${KERNEL_ORG}/${blob}" && true || {
            warn "  Not found on kernel.org: $blob (non-fatal)"
            continue
        }
    fi

    # Check if blob changed
    prev_file="$FW_PREV/lib/firmware/${blob}"
    if [ -f "$prev_file" ]; then
        new_hash=$(sha256sum "$dest_file" | cut -d' ' -f1)
        old_hash=$(sha256sum "$prev_file" | cut -d' ' -f1)
        if [ "$new_hash" != "$old_hash" ]; then
            CHANGES+=("gpu: $(basename $blob) updated")
            changed "  $(basename $blob) — updated"
        else
            UNCHANGED+=("$(basename $blob)")
            [ "$VERBOSE" = true ] && ok "  $(basename $blob) — unchanged"
        fi
    else
        NEW_FILES+=("$(basename $blob)")
        changed "  $(basename $blob) — new"
    fi
done

# ── Step 3: alsa-ucm-conf from Mobian ────────────────────────────────────────
if echo "${DEVICE_QUIRKS:-}" | grep -q "qcom_services"; then
    info "Fetching alsa-ucm-conf from Mobian staging..."

    UCM_DEB=$(mktemp /tmp/mbu-ucm-XXXX.deb)
    UCM_EXTRACT=$(mktemp -d /tmp/mbu-ucm-extract-XXXX)
    trap 'rm -rf "$FW_STAGE" "$FW_PREV" "${GIT_TMP:-}" "$UCM_DEB" "$UCM_EXTRACT"' EXIT

    # Find latest alsa-ucm-conf arm64 deb from Mobian
    UCM_URL=$(curl -fsSL "http://repo.mobian.org/dists/staging/main/binary-arm64/Packages" \
        2>/dev/null | grep -A5 "^Package: alsa-ucm-conf" | grep "^Filename:" | \
        head -1 | awk '{print "http://repo.mobian.org/"$2}')

    if [ -n "$UCM_URL" ]; then
        curl -fsSL --silent -o "$UCM_DEB" "$UCM_URL" && \
            dpkg-deb -x "$UCM_DEB" "$UCM_EXTRACT" 2>/dev/null && \
            [ -d "$UCM_EXTRACT/usr/share/alsa" ] && {
                mkdir -p "$FW_STAGE/usr/share"
                cp -r "$UCM_EXTRACT/usr/share/alsa" "$FW_STAGE/usr/share/"

                # Check if UCM changed
                prev_ucm="$FW_PREV/usr/share/alsa"
                if [ -d "$prev_ucm" ]; then
                    new_ucm_hash=$(find "$FW_STAGE/usr/share/alsa" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
                    old_ucm_hash=$(find "$prev_ucm" -type f -exec sha256sum {} \; | sort | sha256sum | cut -d' ' -f1)
                    if [ "$new_ucm_hash" != "$old_ucm_hash" ]; then
                        CHANGES+=("ucm: alsa-ucm-conf updated")
                        changed "  alsa-ucm-conf — updated"
                    else
                        [ "$VERBOSE" = true ] && ok "  alsa-ucm-conf — unchanged"
                    fi
                else
                    NEW_FILES+=("alsa-ucm-conf")
                    changed "  alsa-ucm-conf — new"
                fi
                ok "alsa-ucm-conf staged"
            } || warn "Failed to extract alsa-ucm-conf (non-fatal)"
    else
        warn "Could not find alsa-ucm-conf in Mobian staging (non-fatal)"
    fi
fi

# ── Diff: detect removed files ────────────────────────────────────────────────
if [ -d "$FW_PREV/lib" ]; then
    while IFS= read -r prev_file; do
        rel="${prev_file#$FW_PREV/}"
        if [ ! -f "$FW_STAGE/$rel" ]; then
            REMOVED_FILES+=("$rel")
            warn "  Removed: $rel"
        fi
    done < <(find "$FW_PREV" -type f 2>/dev/null)
fi

# ── Summary of changes ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}── Change Summary ───────────────────────────────────${NC}"
if [ ${#CHANGES[@]} -eq 0 ] && [ ${#NEW_FILES[@]} -eq 0 ] && [ ${#REMOVED_FILES[@]} -eq 0 ]; then
    ok "No changes detected."
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo ""
        info "Bundle is up to date. Use --force to rebuild anyway."
        exit 0
    fi
else
    for c in "${CHANGES[@]}";  do changed "$c"; done
    for n in "${NEW_FILES[@]}"; do changed "new:     $n"; done
    for r in "${REMOVED_FILES[@]}"; do warn "removed: $r"; done
fi
echo ""

# ── Dry run exits here ────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
    dry "Dry run complete — no files modified."
    dry "Bundle would be written to: $FW_BUNDLE"
    dry "Manifest would be written to: $FW_MANIFEST"
    exit 0
fi

# ── Check staging dir has content ─────────────────────────────────────────────
STAGED_COUNT=$(find "$FW_STAGE" -type f | wc -l)
[ "$STAGED_COUNT" -gt 0 ] || die "Nothing was staged — aborting bundle creation."

# ── Build firmware.tar.gz ─────────────────────────────────────────────────────
info "Packing firmware bundle..."
BUNDLE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
tar -czf "$FW_BUNDLE" -C "$FW_STAGE" .
BUNDLE_SIZE=$(du -sh "$FW_BUNDLE" | cut -f1)
ok "Bundle: $FW_BUNDLE ($BUNDLE_SIZE, $STAGED_COUNT files)"

# ── Write lockfile ────────────────────────────────────────────────────────────
cat > "$FW_LOCK" << LOCK
# mbu lockfile — do not edit manually
bundle_date=${BUNDLE_DATE}
git_commit=${GIT_COMMIT:-none}
git_commit_date=${GIT_COMMIT_DATE:-unknown}
git_commit_msg=${GIT_COMMIT_MSG:-unknown}
git_repo=${FIRMWARE_REPO:-none}
device_codename=${DEVICE_CODENAME}
device_brand=${DEVICE_BRAND}
bundle_size=${BUNDLE_SIZE}
file_count=${STAGED_COUNT}
LOCK
ok "Lockfile: $FW_LOCK"

# ── Build manifest JSON ───────────────────────────────────────────────────────
info "Building firmware manifest..."

MANIFEST_BLOBS="[]"
while IFS= read -r f; do
    rel="${f#$FW_STAGE/}"
    hash=$(sha256sum "$f" | cut -d' ' -f1)
    size=$(stat -c%s "$f")
    # Check if this file changed vs previous bundle
    prev="$FW_PREV/$rel"
    if [ ! -f "$prev" ]; then
        status="new"
    else
        old_hash=$(sha256sum "$prev" | cut -d' ' -f1)
        [ "$hash" = "$old_hash" ] && status="unchanged" || status="updated"
    fi
    MANIFEST_BLOBS=$(echo "$MANIFEST_BLOBS" | python3 -c "
import sys, json
blobs = json.load(sys.stdin)
blobs.append({
    'path': '${rel}',
    'sha256': '${hash}',
    'size_bytes': ${size},
    'status': '${status}'
})
print(json.dumps(blobs))
")
done < <(find "$FW_STAGE" -type f | sort)

python3 - << PYEOF
import json
from datetime import datetime

manifest = {
    "mbu_version": "1.0",
    "generated": "${BUNDLE_DATE}",
    "device": {
        "codename": "${DEVICE_CODENAME}",
        "brand": "${DEVICE_BRAND}",
        "name": "${DEVICE_NAME:-unknown}"
    },
    "sources": {
        "git_repo": "${FIRMWARE_REPO:-none}",
        "git_commit": "${GIT_COMMIT:-none}",
        "git_commit_date": "${GIT_COMMIT_DATE:-unknown}",
        "git_commit_message": "${GIT_COMMIT_MSG:-unknown}",
        "gpu_blobs": "kernel.org linux-firmware",
        "ucm": "repo.mobian.org staging"
    },
    "bundle": {
        "size": "${BUNDLE_SIZE}",
        "file_count": ${STAGED_COUNT},
        "changes": $(printf '%s\n' "${CHANGES[@]+"${CHANGES[@]}"}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
        "new_files": $(printf '%s\n' "${NEW_FILES[@]+"${NEW_FILES[@]}"}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))"),
        "removed_files": $(printf '%s\n' "${REMOVED_FILES[@]+"${REMOVED_FILES[@]}"}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip(]))")
    },
    "blobs": ${MANIFEST_BLOBS}
}

with open("${FW_MANIFEST}", "w") as f:
    json.dump(manifest, f, indent=2)
print("Manifest written: ${FW_MANIFEST}")
PYEOF

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
ok "mbu complete."
echo ""
echo -e "  Bundle:   ${CYAN}$FW_BUNDLE${NC} (${BUNDLE_SIZE})"
echo -e "  Manifest: ${CYAN}$FW_MANIFEST${NC}"
echo -e "  Lock:     ${CYAN}$FW_LOCK${NC}"
echo -e "  Commit:   ${CYAN}${GIT_COMMIT:0:12}${NC}  ${GIT_COMMIT_DATE}"
echo ""
if [ ${#CHANGES[@]} -gt 0 ] || [ ${#NEW_FILES[@]} -gt 0 ]; then
    echo -e "  ${YELLOW}${#CHANGES[@]} change(s), ${#NEW_FILES[@]} new file(s)${NC}"
else
    echo -e "  ${GREEN}No changes from previous bundle${NC}"
fi
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
