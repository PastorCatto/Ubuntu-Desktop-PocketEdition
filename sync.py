#!/usr/bin/env python3
"""
mobuntu-devkit sync.py
Syncs upstream arkadin91/mobuntu-recipes into your fork.
Preserves: devices/, our script additions, overlays we own.
Updates:   upstream core files (build.sh, image.yaml, rootfs.yaml,
           scripts/*, overlays/*, packages/*, files/*) unless locally pinned.

Usage:
    python3 sync.py [--dry-run] [--fork-dir PATH]
"""

import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from datetime import datetime

UPSTREAM_URL  = "https://github.com/arkadin91/mobuntu-recipes.git"
UPSTREAM_REF  = "main"
STATE_FILE    = ".devkit-sync-state.json"
LOCK_FILE     = ".devkit-sync-lock"  # files listed here are never overwritten by sync

# Files/dirs we OWN — sync will never clobber these
OUR_PATHS = {
    "devices/",
    "scripts/fetch-firmware.sh",
    "overlays/etc/systemd/system/hexagonrpcd.service.d/",
    "overlays/usr/share/dbus-1/",
    "overlays/usr/share/polkit-1/",
    "build.sh",       # we heavily modified this — pinned
    "image.yaml",     # we heavily modified this — pinned
    "rootfs.yaml",    # we modified (suite templating) — pinned
}

# Keys we extract from upstream core files and map to device conf vars
# Upstream model: kernel via apt, firmware via files/*.deb -> /opt/*.deb
EXTRACTION_PATTERNS = [
    # (description, regex, group_index, device_conf_key)
    # Kernel package version from apt-get install line
    ("kernel version",
     r'apt-get install\s+-y\s+linux-image-([\d\.\-]+sdm845)',
     1, "KERNEL_VERSION"),
    # Ubuntu suite from rootfs.yaml debootstrap action
    ("ubuntu suite",
     r'suite:\s*([a-z]+)',
     1, "DEVICE_SUITE"),
    # UCM conf deb URL (audio fix — version may change upstream)
    ("alsa ucm conf url",
     r'wget\s+(https://[^\s]+alsa-ucm-conf[^\s]+\.deb)',
     1, "ALSA_UCM_URL"),
    # Kernel headers package (confirm it matches image)
    ("kernel headers version",
     r'linux-headers-([\d\.\-]+sdm845)',
     1, "KERNEL_HEADERS_VERSION"),
]

# Known device codename hints in upstream paths/URLs
DEVICE_HINTS = {
    "beryllium":   ["beryllium", "xiaomi", "poco", "PocoF1"],
    "fajita":      ["fajita", "oneplus6t", "OnePlus6T", "oneplus-6t"],
    "enchilada":   ["enchilada", "oneplus6", "OnePlus6"],
}


# ── Helpers ──────────────────────────────────────────────────────────────────

def run(cmd, cwd=None, check=True):
    result = subprocess.run(
        cmd, shell=True, cwd=cwd,
        capture_output=True, text=True
    )
    if check and result.returncode != 0:
        print(f"ERROR: {cmd}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def file_hash(path: Path) -> str:
    if not path.exists():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_pinned(rel_path: str, lock_set: set) -> bool:
    """Check if a path is owned by us or manually locked."""
    for p in OUR_PATHS | lock_set:
        if rel_path == p or rel_path.startswith(p):
            return True
    return False


def load_state(fork_dir: Path) -> dict:
    state_path = fork_dir / STATE_FILE
    if state_path.exists():
        return json.loads(state_path.read_text())
    return {"last_sync": None, "upstream_sha": None, "file_hashes": {}}


def save_state(fork_dir: Path, state: dict):
    (fork_dir / STATE_FILE).write_text(json.dumps(state, indent=2))


def load_lock(fork_dir: Path) -> set:
    lock_path = fork_dir / LOCK_FILE
    if not lock_path.exists():
        return set()
    return {l.strip() for l in lock_path.read_text().splitlines()
            if l.strip() and not l.startswith("#")}


# ── Upstream fetch ────────────────────────────────────────────────────────────

def fetch_upstream(tmp_dir: Path) -> tuple[Path, str]:
    """Clone upstream into tmp_dir, return (repo_path, HEAD_sha)."""
    repo_path = tmp_dir / "upstream"
    print(f"  Cloning {UPSTREAM_URL} ...")
    run(f"git clone --depth=1 --branch {UPSTREAM_REF} {UPSTREAM_URL} upstream",
        cwd=tmp_dir)
    sha = run("git rev-parse HEAD", cwd=repo_path)
    return repo_path, sha


# ── Extraction ────────────────────────────────────────────────────────────────

def extract_device_vars(upstream_path: Path) -> dict[str, dict]:
    """
    Scan upstream files for hardcoded device-specific values.
    Returns {device_codename: {VAR: value, ...}}
    """
    results: dict[str, dict] = {}

    scan_files = list(upstream_path.rglob("*.sh")) + \
                 list(upstream_path.rglob("*.yaml")) + \
                 list(upstream_path.rglob("*.yml"))

    for fpath in scan_files:
        try:
            text = fpath.read_text(errors="replace")
        except Exception:
            continue

        # Determine which device this file is for
        device = None
        for codename, hints in DEVICE_HINTS.items():
            if any(h.lower() in text.lower() or h.lower() in str(fpath).lower()
                   for h in hints):
                device = codename
                break
        if device is None:
            device = "beryllium"  # default — upstream is beryllium-focused

        if device not in results:
            results[device] = {}

        # Extract values
        for _, pattern, group_idx, key in EXTRACTION_PATTERNS:
            match = re.search(pattern, text)
            if match:
                val = match.group(group_idx).rstrip('",')
                if key not in results[device]:
                    results[device][key] = val

    return results


# ── Diff ─────────────────────────────────────────────────────────────────────

def diff_upstream(upstream_path: Path, fork_dir: Path,
                  lock_set: set) -> tuple[list, list, list]:
    """
    Compare upstream to fork.
    Returns (to_update, conflicts, skipped)
    Each item: (rel_path, upstream_file, fork_file)
    """
    to_update = []
    conflicts = []
    skipped   = []

    for up_file in upstream_path.rglob("*"):
        if up_file.is_dir():
            continue
        rel = str(up_file.relative_to(upstream_path))

        # Skip git internals
        if rel.startswith(".git"):
            continue

        fork_file = fork_dir / rel

        if is_pinned(rel, lock_set):
            skipped.append((rel, up_file, fork_file))
            continue

        if not fork_file.exists():
            to_update.append((rel, up_file, fork_file))
            continue

        up_hash   = file_hash(up_file)
        fork_hash = file_hash(fork_file)

        if up_hash != fork_hash:
            # Check if fork file was locally modified since last sync
            # (we track this via state hashes)
            to_update.append((rel, up_file, fork_file))

    return to_update, conflicts, skipped


# ── Apply ─────────────────────────────────────────────────────────────────────

def apply_updates(to_update: list, fork_dir: Path, dry_run: bool) -> list:
    applied = []
    for rel, up_file, fork_file in to_update:
        if dry_run:
            print(f"  [dry-run] would update: {rel}")
        else:
            fork_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(up_file, fork_file)
            print(f"  updated: {rel}")
        applied.append(rel)
    return applied


# ── Device conf update ────────────────────────────────────────────────────────

def update_device_confs(extracted: dict[str, dict],
                        fork_dir: Path, dry_run: bool):
    """
    Merge newly extracted upstream values into existing device.conf files.
    Only writes keys that are missing or have changed.
    Never removes existing keys.
    """
    devices_dir = fork_dir / "devices"
    if not devices_dir.exists():
        print("  [warn] no devices/ directory found — skipping conf update")
        return

    for device, vars_ in extracted.items():
        conf_path = devices_dir / device / "device.conf"
        if not conf_path.exists():
            print(f"  [skip] no device.conf for {device}")
            continue

        current = conf_path.read_text()
        updated = current
        changed = []

        for key, new_val in vars_.items():
            # Check if key exists with a different value
            pattern = rf'^({re.escape(key)}=")([^"]*)(")$'
            match = re.search(pattern, updated, re.MULTILINE)
            if match:
                old_val = match.group(2)
                if old_val != new_val:
                    updated = re.sub(pattern,
                                     rf'\g<1>{new_val}\g<3>',
                                     updated, flags=re.MULTILINE)
                    changed.append(f"  {key}: {old_val!r} → {new_val!r}")
            # If key is missing, append it with a TODO comment
            elif key not in updated:
                updated += f"\n# [sync] extracted from upstream\n{key}=\"{new_val}\"\n"
                changed.append(f"  {key}: (new) {new_val!r}")

        if changed:
            if dry_run:
                print(f"  [dry-run] would update devices/{device}/device.conf:")
                for c in changed:
                    print(f"    {c}")
            else:
                conf_path.write_text(updated)
                print(f"  updated devices/{device}/device.conf:")
                for c in changed:
                    print(f"    {c}")
        else:
            print(f"  devices/{device}/device.conf — no changes needed")


# ── Report ────────────────────────────────────────────────────────────────────

def print_report(to_update, skipped, applied, extracted, upstream_sha):
    print()
    print("═" * 60)
    print("  SYNC REPORT")
    print("═" * 60)
    print(f"  Upstream SHA : {upstream_sha[:12]}")
    print(f"  Timestamp    : {datetime.now().strftime('%Y-%m-%d %H:%M')}")
    print()
    print(f"  Files updated  : {len(applied)}")
    print(f"  Files pinned   : {len(skipped)}")
    print()

    if extracted:
        print("  Extracted device vars:")
        for device, vars_ in extracted.items():
            print(f"    [{device}]")
            for k, v in vars_.items():
                print(f"      {k} = {v}")
    print()

    if skipped:
        print("  Pinned (not touched):")
        for rel, _, _ in skipped[:10]:
            print(f"    {rel}")
        if len(skipped) > 10:
            print(f"    ... and {len(skipped) - 10} more")
    print("═" * 60)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Mobuntu upstream sync tool")
    parser.add_argument("--dry-run",  action="store_true",
                        help="Show what would change without writing")
    parser.add_argument("--fork-dir", default="Mobuntu",
                        help="Path to your fork (default: Mobuntu)")
    parser.add_argument("--extract-only", action="store_true",
                        help="Only show extracted device vars, don't sync files")
    args = parser.parse_args()

    fork_dir = Path(args.fork_dir).resolve()
    print(f"\nMobuntu Sync Engine")
    print(f"Fork : {fork_dir}")
    print(f"Mode : {'dry-run' if args.dry_run else 'live'}")
    print()

    lock_set = load_lock(fork_dir)
    state    = load_state(fork_dir)

    with tempfile.TemporaryDirectory(prefix="mobuntu-sync-") as tmp:
        tmp_path = Path(tmp)

        print("[ 1/4 ] Fetching upstream ...")
        upstream_path, upstream_sha = fetch_upstream(tmp_path)

        if state.get("upstream_sha") == upstream_sha:
            print(f"  Already at upstream {upstream_sha[:12]} — nothing to do.")
            print("  Use --dry-run to inspect anyway.")
            if not args.dry_run and not args.extract_only:
                return

        print()
        print("[ 2/4 ] Extracting hardcoded device vars from upstream ...")
        extracted = extract_device_vars(upstream_path)
        for device, vars_ in extracted.items():
            print(f"  {device}: {len(vars_)} vars found")

        if args.extract_only:
            print()
            for device, vars_ in extracted.items():
                print(f"[{device}]")
                for k, v in vars_.items():
                    print(f"  {k}={v!r}")
            return

        print()
        print("[ 3/4 ] Diffing upstream vs fork ...")
        to_update, conflicts, skipped = diff_upstream(
            upstream_path, fork_dir, lock_set)
        print(f"  {len(to_update)} files to update, "
              f"{len(skipped)} pinned, "
              f"{len(conflicts)} conflicts")

        print()
        print("[ 4/4 ] Applying updates ...")
        applied = apply_updates(to_update, fork_dir, args.dry_run)
        update_device_confs(extracted, fork_dir, args.dry_run)

        if not args.dry_run:
            state["last_sync"]    = datetime.now().isoformat()
            state["upstream_sha"] = upstream_sha
            save_state(fork_dir, state)

        print_report(to_update, skipped, applied, extracted, upstream_sha)


if __name__ == "__main__":
    main()
