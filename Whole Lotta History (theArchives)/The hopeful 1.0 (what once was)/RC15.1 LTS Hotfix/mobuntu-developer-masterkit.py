#!/usr/bin/env python3
"""
Mobuntu Developer Masterkit — RC15
Regedit-style TUI: left tree pane + right content/menu pane
Navigation: arrow keys, Enter, Esc, Tab to switch panes
"""

import curses
import os
import sys
import subprocess
import shutil
from pathlib import Path

VERSION = "RC15"
SCRIPT_DIR = Path(__file__).parent.resolve()
DEVICES_DIR = SCRIPT_DIR / "devices"
RECIPES_DIR = SCRIPT_DIR / "recipes"
STAGED = []

C_NORMAL = 1; C_SELECTED = 2; C_HEADER = 3; C_TITLE = 4
C_STAGED = 5; C_OK = 6;       C_WARN = 7;   C_BORDER = 8

HIGHLIGHT_KEYS = {
    "DEVICE_QUIRKS", "KERNEL_METHOD", "BOOT_METHOD",
    "FIRMWARE_METHOD", "DEVICE_SERVICES", "KERNEL_VERSION_PIN",
    "KERNEL_REPO", "FIRMWARE_REPO",
}

# ============================================================
# Tree
# ============================================================

class Node:
    def __init__(self, label, path=None, children=None):
        self.label    = label
        self.path     = path
        self.children = children or []
        self.expanded = True


def build_tree():
    root = []

    # Scripts
    scripts = Node("Scripts", children=[])
    for name in sorted(["1_preflight.sh", "run_build.sh",
                         "5_seal_rootfs.sh", "verify_build.sh",
                         "4_enter_chroot.sh", "watchdog.sh",
                         "mobuntu-developer-masterkit.py"]):
        p = SCRIPT_DIR / name
        scripts.children.append(Node(name, path=p if p.exists() else None))
    root.append(scripts)

    # Recipes
    recipes = Node("recipes/", children=[])
    for name in ["base.yaml", "qcom.yaml", "l4t.yaml"]:
        p = RECIPES_DIR / name
        recipes.children.append(Node(name, path=p if p.exists() else None))
    dev_recipes = Node("devices/", children=[])
    dev_path = RECIPES_DIR / "devices"
    if dev_path.exists():
        for f in sorted(dev_path.glob("*.yaml")):
            dev_recipes.children.append(Node(f.name, path=f))
    if not dev_recipes.children:
        dev_recipes.children.append(Node("(empty)"))
    recipes.children.append(dev_recipes)
    root.append(recipes)

    # Device configs
    devices = Node("devices/", children=[])
    if DEVICES_DIR.exists():
        for f in sorted(DEVICES_DIR.glob("*.conf")):
            devices.children.append(Node(f.name, path=f))
    if not devices.children:
        devices.children.append(Node("(empty)"))
    root.append(devices)

    # Firmware
    fw = Node("firmware/", children=[])
    fw_dir = SCRIPT_DIR / "firmware"
    if fw_dir.exists():
        for d in sorted(fw_dir.iterdir()):
            if d.is_dir():
                sub = Node(d.name + "/", path=d, children=[])
                for f in sorted(d.iterdir()):
                    if f.is_file():
                        sub.children.append(Node(f.name, path=f))
                fw.children.append(sub)
    if not fw.children:
        fw.children.append(Node("(empty)"))
    root.append(fw)

    # build.env
    benv = SCRIPT_DIR / "build.env"
    root.append(Node("build.env" + (" [OK]" if benv.exists() else " [NOT GENERATED]"),
                     path=benv if benv.exists() else None))

    # run_build.sh
    rb = SCRIPT_DIR / "run_build.sh"
    root.append(Node("run_build.sh" + (" [OK]" if rb.exists() else " [NOT GENERATED]"),
                     path=rb if rb.exists() else None))

    return root


def flatten_tree(nodes, depth=0):
    result = []
    for node in nodes:
        result.append((depth, node))
        if node.expanded and node.children:
            result.extend(flatten_tree(node.children, depth + 1))
    return result


# ============================================================
# Right pane
# ============================================================

MENU_SECTIONS = [
    ("[>] Boot Chain",        "bootchain"),
    ("[D] Device Config",     "device"),
    ("[A] APT & Packages",    "apt"),
    ("[K] Kernel",            "kernel"),
    ("[S] Service Ordering",  "services"),
    ("[~] Audio Config",      "audio"),
    ("[V] Verifier Generator","verifier"),
    ("[B] Base Cache",        "basecache"),
    ("[*] Staged Changes",    "staged"),
    ("[X] Exit",              "exit"),
]


def get_build_env():
    env = {}
    benv = SCRIPT_DIR / "build.env"
    if benv.exists():
        for line in benv.read_text().splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip().strip('"')
    return env


def get_file_preview(path):
    try:
        p = Path(path)
        if not p.exists():  return ["(file not found)"]
        if p.stat().st_size > 100000: return ["(file too large to preview)"]
        return p.read_text(errors="replace").splitlines()[:200]
    except Exception as e:
        return [f"(error: {e})"]


def get_right_content(section, selected_node):
    lines = []

    if selected_node and selected_node.path and \
       Path(str(selected_node.path)).is_file():
        lines.append(f"=== {selected_node.label} ===")
        lines.append("")
        lines.extend(get_file_preview(selected_node.path))
        return lines

    env = get_build_env()

    if section == "main":
        lines.append("=== Mobuntu Developer Masterkit ===")
        lines.append(f"    Version: {VERSION}")
        lines.append("")
        lines.append("Navigation:")
        lines.append("  Arrow keys  - navigate")
        lines.append("  Tab         - switch panes")
        lines.append("  Enter       - select/expand")
        lines.append("  Esc         - back / main menu")
        lines.append("  Esc x2      - quit")
        lines.append("")
        lines.append("=== Build Status ===")
        if env:
            for k in ["DEVICE_NAME","UBUNTU_RELEASE","BUILD_COLOR",
                      "DEVICE_HOSTNAME","FAKEMACHINE_BACKEND"]:
                if k in env:
                    lines.append(f"  {k}: {env[k]}")
        else:
            lines.append("  build.env not generated.")
            lines.append("  Run 1_preflight.sh first.")
        lines.append("")
        lines.append(f"  Staged changes: {len(STAGED)}")

    elif section == "bootchain":
        lines.append("=== Mobuntu RC15 Build Chain ===")
        lines.append("")
        lines.append("  [1] 1_preflight.sh")
        lines.append("      Device selection, host deps, backend")
        lines.append("      detection. Generates build.env and")
        lines.append("      run_build.sh. Does NOT build.")
        lines.append("")
        lines.append("  [2] run_build.sh  (generated)")
        lines.append("      Calls debos for base tarball (cached)")
        lines.append("      then device tarball. Handles -t flags.")
        lines.append("")
        lines.append("      Base tarball rebuild triggers if:")
        lines.append("        - base-{release}.tar.gz missing")
        lines.append("        - recipes/base.yaml newer than tarball")
        lines.append("")
        lines.append("  [3] verify_build.sh  (recommended)")
        lines.append("      Unpacks device tarball to temp dir,")
        lines.append("      runs all integrity checks, cleans up.")
        lines.append("")
        lines.append("  [4] 5_seal_rootfs.sh")
        lines.append("      Unpacks device tarball, writes UUID,")
        lines.append("      cmdline, fstab, autoresize service.")
        lines.append("")
        lines.append("      SDM845 (mkbootimg):")
        lines.append("        -> boot.img + root.img")
        lines.append("        -> fastboot flash boot / system")
        lines.append("")
        lines.append("      Switch (l4t):")
        lines.append("        -> kernel.lz4 + initrd.lz4 + DTB")
        lines.append("        -> root.img (dd to Linux partition)")
        lines.append("")
        lines.append("  --- Fakemachine backends ---")
        lines.append("")
        lines.append("  kvm   ~9 min   (requires /dev/kvm access)")
        lines.append("  uml   ~18 min  (requires user-mode-linux)")
        lines.append("  qemu  ~2.5 hr  (always available, slow)")
        lines.append("")
        lines.append("  --- Recipe structure ---")
        lines.append("")
        lines.append("  base.yaml")
        lines.append("    debootstrap -> apt -> UI -> user -> pack")
        lines.append("    Output: base-{release}.tar.gz (cached)")
        lines.append("")
        lines.append("  devices/{codename}.yaml")
        lines.append("    unpack base -> recipe: qcom.yaml or l4t.yaml")
        lines.append("    -> kernel -> hostname -> pack")
        lines.append("    Output: {label}-{release}.tar.gz")
        lines.append("")
        lines.append("  --- Dev / Automation tools ---")
        lines.append("")
        lines.append("  [DEV]  4_enter_chroot.sh")
        lines.append("         Interactive chroot (manual inspection)")
        lines.append("")
        lines.append("  [AUTO] watchdog.sh")
        lines.append("         Unattended: run_build -> verify -> seal")
        lines.append("         ZWJ (U+200D) clean-exit detection")

    elif section == "device":
        lines.append("=== Device Config ===")
        lines.append("")
        lines.append("  [1] Load existing config")
        lines.append("  [2] Create new config")
        lines.append("  [3] Edit loaded config")
        lines.append("")
        lines.append("Available configs:")
        if DEVICES_DIR.exists():
            for f in sorted(DEVICES_DIR.glob("*.conf")):
                lines.append(f"  - {f.name}")
        else:
            lines.append("  devices/ not found")

    elif section == "apt":
        lines.append("=== APT & Packages ===")
        lines.append("")
        lines.append("  [1] Add custom repo")
        lines.append("  [2] Pin package version")
        lines.append("  [3] Add extra packages")
        lines.append("")
        if "DEVICE_PACKAGES" in env:
            lines.append("Current device packages:")
            for p in env["DEVICE_PACKAGES"].split():
                lines.append(f"  - {p}")

    elif section == "kernel":
        lines.append("=== Kernel Config ===")
        lines.append("")
        lines.append("  [1] Edit kernel cmdline")
        lines.append("  [2] Edit version pin")
        lines.append("")
        for k in ["KERNEL_METHOD","KERNEL_REPO",
                  "KERNEL_VERSION_PIN","KERNEL_SERIES"]:
            if k in env:
                lines.append(f"  {k}: {env[k]}")

    elif section == "services":
        lines.append("=== Service Ordering ===")
        lines.append("")
        lines.append("  [1] Edit service order")
        lines.append("  [2] Generate drop-in config")
        lines.append("  [3] Enable/disable services")
        lines.append("")
        quirks = env.get("DEVICE_QUIRKS", "")
        if "qcom_services" in quirks:
            lines.append("Device family: Qualcomm SDM845")
            lines.append("Required order:")
            for s in ["qrtr-ns","rmtfs","pd-mapper","tqftpserv"]:
                lines.append(f"  -> {s}")
            lines.append("")
            lines.append("Note: hexagonrpcd intentionally absent.")
            lines.append("SLPI crash loop is cosmetic (sensors only).")
        elif "l4t_bootfiles" in quirks:
            lines.append("Device family: NVIDIA Tegra (L4T)")
            lines.append("No Qualcomm services required.")
        else:
            lines.append("Device family: unknown (check DEVICE_QUIRKS)")
        if "DEVICE_SERVICES" in env:
            lines.append(f"\nConfigured: {env['DEVICE_SERVICES']}")

    elif section == "audio":
        lines.append("=== Audio Config ===")
        lines.append("")
        lines.append("  [1] Generate 51-qcom.conf")
        lines.append("  [2] Edit existing config")
        lines.append("")
        lines.append("SDM845 (beryllium) — with period-size tuning:")
        lines.append("  audio.format         = S16LE")
        lines.append("  audio.rate           = 48000")
        lines.append("  api.alsa.period-size = 4096")
        lines.append("  api.alsa.period-num  = 6")
        lines.append("  api.alsa.headroom    = 512")
        lines.append("")
        lines.append("OnePlus 6/6T (enchilada/fajita) — no period-size")
        lines.append("  (auto-selection works better per upstream fix)")
        lines.append("")
        if "DEVICE_CODENAME" in env:
            conf = DEVICES_DIR / f"{env['DEVICE_CODENAME']}-51-qcom.conf"
            lines.append(f"Device config: {conf.name}")
            lines.append("  EXISTS" if conf.exists() else "  NOT FOUND")

    elif section == "verifier":
        lines.append("=== Verifier Generator ===")
        lines.append("")
        lines.append("  [1] Generate custom verifier")
        lines.append("  [2] View verify_build.sh")
        lines.append("")
        lines.append("Checks (quirk-gated):")
        lines.append("  - Device tarball present + sane size")
        lines.append("  - Packages installed")
        lines.append("  - Services enabled + ordered")
        lines.append("  - hexagonrpcd absent")
        lines.append("  - 51-qcom.conf present")
        lines.append("  - ALSA services masked")
        lines.append("  - qcom-firmware hook present")
        lines.append("  - Kernel + initrd present")
        lines.append("  - Firmware blobs present")
        lines.append("  - Autoresize service present")
        lines.append("  - build.env + run_build.sh present")

    elif section == "basecache":
        lines.append("=== Base Tarball Cache ===")
        lines.append("")
        lines.append("Base tarballs are built once and reused")
        lines.append("for all device builds of the same release.")
        lines.append("")
        for release in ["noble", "oracular", "resolute"]:
            tb = SCRIPT_DIR / f"base-{release}.tar.gz"
            if tb.exists():
                import os
                mtime = os.path.getmtime(str(tb))
                import datetime
                dt = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
                size = tb.stat().st_size // (1024*1024)
                lines.append(f"  base-{release}.tar.gz")
                lines.append(f"    Size:  {size} MB")
                lines.append(f"    Built: {dt}")
            else:
                lines.append(f"  base-{release}.tar.gz  [NOT BUILT]")
            lines.append("")
        lines.append("To force rebuild: delete the tarball and")
        lines.append("re-run run_build.sh")
        lines.append("")
        lines.append("  [1] Delete all base tarballs")
        lines.append("  [2] Delete specific release tarball")

    elif section == "staged":
        lines.append("=== Staged Changes ===")
        lines.append("")
        if STAGED:
            for i, (desc, src, dst) in enumerate(STAGED):
                lines.append(f"  [{i+1}] {desc}")
                if dst: lines.append(f"       -> {dst}")
        else:
            lines.append("  No staged changes.")
        lines.append("")
        if STAGED:
            lines.append("  [A] Apply all")
            lines.append("  [C] Clear all")

    return lines


# ============================================================
# Dialogs
# ============================================================

def input_dialog(stdscr, title, prompt, default=""):
    h, w = stdscr.getmaxyx()
    dh, dw = 7, min(w - 4, 70)
    win = curses.newwin(dh, dw, h//2 - dh//2, w//2 - dw//2)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    win.addstr(2, 2, prompt[:dw-4])
    win.addstr(4, 2, "> ")
    curses.echo(); curses.curs_set(1); win.refresh()
    win.addstr(4, 4, default); win.refresh()
    result = win.getstr(4, 4, dw - 6).decode("utf-8", errors="replace")
    curses.noecho(); curses.curs_set(0)
    return result.strip() if result.strip() else default


def message_dialog(stdscr, title, msg):
    h, w = stdscr.getmaxyx()
    lines = msg.splitlines()
    dh = min(len(lines) + 4, h - 4)
    dw = min(max((len(l) for l in lines), default=20) + 4, w - 4)
    win = curses.newwin(dh, dw, h//2 - dh//2, w//2 - dw//2)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    for i, line in enumerate(lines[:dh-3]):
        win.addstr(i + 2, 2, line[:dw-4])
    win.addstr(dh - 1, dw // 2 - 5, "[ OK ]", curses.color_pair(C_SELECTED))
    win.refresh(); win.getch()


def confirm_dialog(stdscr, title, msg):
    h, w = stdscr.getmaxyx()
    lines = msg.splitlines()
    dh = len(lines) + 5
    dw = min(max((len(l) for l in lines), default=20) + 6, w - 4)
    win = curses.newwin(dh, dw, h//2 - dh//2, w//2 - dw//2)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    for i, line in enumerate(lines):
        win.addstr(i + 2, 2, line[:dw-4])
    focus = 0
    while True:
        win.addstr(dh-2, dw//2-9, "[ Yes ]",
            curses.color_pair(C_SELECTED) if focus == 0 else curses.color_pair(C_OK))
        win.addstr(dh-2, dw//2+0, "  [ No ]",
            curses.color_pair(C_SELECTED) if focus == 1 else curses.color_pair(C_WARN))
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('\t')): focus = 1 - focus
        elif k in (curses.KEY_ENTER, 10, 13): return focus == 0
        elif k == 27: return False


# ============================================================
# Actions
# ============================================================

def action_device(stdscr, choice_key):
    if choice_key == "1":
        configs = list(DEVICES_DIR.glob("*.conf")) if DEVICES_DIR.exists() else []
        if not configs:
            message_dialog(stdscr, "Device Config", "No configs found in devices/")
            return
        names = [f.name for f in configs]
        message_dialog(stdscr, "Load Config", "\n".join(names) + "\n\nType filename in next prompt.")
        sel = input_dialog(stdscr, "Load Config", "Enter config filename:", names[0])
        p = DEVICES_DIR / sel
        message_dialog(stdscr, "Loaded" if p.exists() else "Error",
                       f"Config loaded: {sel}" if p.exists() else f"Not found: {sel}")

    elif choice_key == "2":
        name    = input_dialog(stdscr, "New Device", "Full device name:", "My Device")
        code    = input_dialog(stdscr, "New Device", "Codename:", "mydevice")
        brand   = input_dialog(stdscr, "New Device", "Brand:", "brand")
        host    = input_dialog(stdscr, "New Device", "Hostname:", f"mobuntu-{code}")
        label   = input_dialog(stdscr, "New Device", "Image label:", f"mobuntu-{code}")
        family  = input_dialog(stdscr, "New Device", "Device family [qcom/l4t]:", "qcom")
        outfile = DEVICES_DIR / f"{brand}-{code}.conf"
        DEVICES_DIR.mkdir(exist_ok=True)
        if outfile.exists():
            if confirm_dialog(stdscr, "Warning", f"{outfile.name} exists.\nRename to .bak?"):
                outfile.rename(str(outfile) + ".bak")
            else:
                return
        if family == "l4t":
            quirks = "l4t_bootfiles firmware_source_online"
            boot_method = "l4t"; kernel_method = "custom_url"
            kernel_repo = ""; kernel_series = "tegra210"
            firmware_method = "apt"
            mkbootimg_fields = ""
        else:
            quirks = "dtb_append qcom_services firmware_source_local"
            boot_method = "mkbootimg"; kernel_method = "mobian"
            kernel_repo = "https://repo.mobian.org/pool/main/l/"
            kernel_series = "sdm845"; firmware_method = "git"
            mkbootimg_fields = (
                'MKBOOTIMG_PAGESIZE="4096"\n'
                'MKBOOTIMG_BASE="0x00000000"\n'
                'MKBOOTIMG_KERNEL_OFFSET="0x00008000"\n'
                'MKBOOTIMG_RAMDISK_OFFSET="0x01000000"\n'
                'MKBOOTIMG_TAGS_OFFSET="0x00000100"\n'
            )
        outfile.write_text(
            f'# Mobuntu Device Config -- {VERSION}\n'
            f'# Generated by mobuntu-developer-masterkit\n'
            f'DEVICE_NAME="{name}"\n'
            f'DEVICE_CODENAME="{code}"\n'
            f'DEVICE_BRAND="{brand}"\n'
            f'DEVICE_ARCH="arm64"\n'
            f'DEVICE_SIM_SLOTS=0\n'
            f'DEVICE_HOSTNAME="{host}"\n'
            f'DEVICE_IMAGE_LABEL="{label}"\n'
            f'DEVICE_PACKAGES=""\n'
            f'DEVICE_SERVICES=""\n'
            f'DEVICE_QUIRKS="{quirks}"\n'
            f'KERNEL_METHOD="{kernel_method}"\n'
            f'KERNEL_REPO="{kernel_repo}"\n'
            f'KERNEL_SERIES="{kernel_series}"\n'
            f'KERNEL_VERSION_PIN=""\n'
            f'BOOT_METHOD="{boot_method}"\n'
            f'BOOT_DTB=""\n'
            f'BOOT_DTB_APPEND="{"true" if family == "qcom" else "false"}"\n'
            f'BOOT_PANEL_PICKER="false"\n'
            f'{mkbootimg_fields}'
            f'UBOOT_URL=""\n'
            f'UEFI_URL=""\n'
            f'UEFI_ESP_SIZE_MB=""\n'
            f'FIRMWARE_METHOD="{firmware_method}"\n'
            f'FIRMWARE_REPO=""\n'
            f'FIRMWARE_INSTALL_PATH=""\n'
        )
        message_dialog(stdscr, "Created", f"Device config created:\n{outfile.name}\n\nAlso create:\nrecipes/devices/{code}.yaml")


def action_audio(stdscr, choice_key, env):
    codename = env.get("DEVICE_CODENAME", "device")
    if choice_key == "1":
        fmt      = input_dialog(stdscr, "Audio", "Format:", "S16LE")
        rate     = input_dialog(stdscr, "Audio", "Sample rate:", "48000")
        psize    = input_dialog(stdscr, "Audio", "period-size (empty=auto):", "4096")
        pnum     = input_dialog(stdscr, "Audio", "period-num:", "6")
        headroom = input_dialog(stdscr, "Audio", "headroom:", "512")
        DEVICES_DIR.mkdir(exist_ok=True)
        outfile = DEVICES_DIR / f"{codename}-51-qcom.conf"
        period_block = ""
        if psize:
            period_block = (
                f'        api.alsa.period-size   = {psize}\n'
                f'        api.alsa.period-num    = {pnum}\n'
                f'        api.alsa.headroom      = {headroom}\n'
            )
        outfile.write_text(
            f"# Mobuntu WirePlumber ALSA Tuning -- {VERSION}\n"
            f"# Generated by mobuntu-developer-masterkit\n"
            f"monitor.alsa.rules = [\n"
            f"  {{\n"
            f"    matches = [\n"
            f'      {{ node.name = "~alsa_input.*" }},\n'
            f'      {{ node.name = "~alsa_output.*" }}\n'
            f"    ]\n"
            f"    actions = {{\n"
            f"      update-props = {{\n"
            f'        audio.format           = "{fmt}"\n'
            f"        audio.rate             = {rate}\n"
            f"{period_block}"
            f"      }}\n"
            f"    }}\n"
            f"  }}\n"
            f"]\n"
        )
        message_dialog(stdscr, "Audio Config", f"Generated:\n{outfile.name}")


def action_verifier(stdscr, choice_key, env):
    codename    = env.get("DEVICE_CODENAME", "device")
    device_name = env.get("DEVICE_NAME", "Unknown Device")
    pkgs        = env.get("DEVICE_PACKAGES", "")
    quirks      = env.get("DEVICE_QUIRKS", "")
    if choice_key == "1":
        outfile = SCRIPT_DIR / f"verify_{codename}.sh"
        qcom_checks = ""
        if "qcom_services" in quirks:
            qcom_checks = (
                f'for pkg in {pkgs} qrtr-tools rmtfs pd-mapper tqftpserv '
                f'pipewire wireplumber alsa-ucm-conf; do\n'
                f'    grep -q "^Package: $pkg$" "$VERIFY_DIR/var/lib/dpkg/status" '
                f'&& ok "$pkg" || fail "$pkg NOT installed"\ndone\n'
                f'grep -q "^Package: hexagonrpcd$" "$VERIFY_DIR/var/lib/dpkg/status" '
                f'&& fail "hexagonrpcd present (must be absent)" || ok "hexagonrpcd absent"\n'
                f'[ -f "$VERIFY_DIR/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf" ] '
                f'&& ok "51-qcom.conf" || fail "51-qcom.conf missing"\n'
                f'ls "$VERIFY_DIR/boot/vmlinuz-"*sdm845* 2>/dev/null | grep -q . '
                f'&& ok "SDM845 kernel" || fail "SDM845 kernel missing"\n'
                f'for fw in adsp.mbn cdsp.mbn venus.mbn; do\n'
                f'    find "$VERIFY_DIR/lib/firmware" -name "$fw" 2>/dev/null | grep -q . '
                f'&& ok "$fw" || warn "$fw not found"\ndone\n'
            )
        else:
            qcom_checks = (
                'ls "$VERIFY_DIR/boot/vmlinuz-"* 2>/dev/null | grep -q . '
                '&& ok "Kernel found" || fail "No kernel found"\n'
            )
        outfile.write_text(
            f'#!/bin/bash\n'
            f'# Mobuntu -- Custom Verifier: {device_name}\n'
            f'# {VERSION} -- Generated by mobuntu-developer-masterkit\n'
            f'PASS=0; FAIL=0; WARN=0\n'
            f'ok()   {{ echo "  [PASS] $1"; ((PASS++)); }}\n'
            f'fail() {{ echo "  [FAIL] $1"; ((FAIL++)); }}\n'
            f'warn() {{ echo "  [WARN] $1"; ((WARN++)); }}\n'
            f'source build.env 2>/dev/null || {{ echo "ERROR: build.env not found"; exit 1; }}\n'
            f'DEVICE_TARBALL="${{DEVICE_IMAGE_LABEL}}-${{UBUNTU_RELEASE}}.tar.gz"\n'
            f'VERIFY_DIR=$(mktemp -d /tmp/mobuntu-verify-XXXX)\n'
            f'[ -f "$DEVICE_TARBALL" ] && ok "Tarball: $DEVICE_TARBALL" || '
            f'{{ fail "Tarball missing"; exit 1; }}\n'
            f'sudo tar -xzf "$DEVICE_TARBALL" -C "$VERIFY_DIR/" 2>/dev/null\n'
            f'echo "======================================================"\n'
            f'echo "   Mobuntu Verifier -- {device_name}"\n'
            f'echo "======================================================"\n'
            f'{qcom_checks}'
            f'sudo rm -rf "$VERIFY_DIR"\n'
            f'echo ""\n'
            f'echo "RESULTS: $PASS passed | $WARN warnings | $FAIL failed"\n'
            f'[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED\u200d" && exit 0 || exit 1\n'
        )
        outfile.chmod(0o755)
        message_dialog(stdscr, "Verifier", f"Generated:\n{outfile.name}")


def action_basecache(stdscr, choice_key):
    if choice_key == "1":
        if confirm_dialog(stdscr, "Delete", "Delete ALL base tarballs?"):
            deleted = []
            for f in SCRIPT_DIR.glob("base-*.tar.gz"):
                f.unlink()
                deleted.append(f.name)
            msg = "Deleted:\n" + "\n".join(deleted) if deleted else "No base tarballs found."
            message_dialog(stdscr, "Done", msg)
    elif choice_key == "2":
        release = input_dialog(stdscr, "Delete Base", "Release name:", "resolute")
        tb = SCRIPT_DIR / f"base-{release}.tar.gz"
        if tb.exists():
            if confirm_dialog(stdscr, "Delete", f"Delete {tb.name}?"):
                tb.unlink()
                message_dialog(stdscr, "Deleted", tb.name)
        else:
            message_dialog(stdscr, "Not Found", f"base-{release}.tar.gz not found")


def action_staged(stdscr, choice_key):
    if choice_key == "A" and STAGED:
        if confirm_dialog(stdscr, "Apply", f"Apply {len(STAGED)} staged changes?"):
            errors = []
            for desc, src, dst in STAGED:
                try:
                    if src and dst:
                        Path(dst).parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(src, dst)
                except Exception as e:
                    errors.append(f"{desc}: {e}")
            STAGED.clear()
            msg = "\n".join(errors) if errors else "All changes applied."
            message_dialog(stdscr, "Errors" if errors else "Applied", msg)
    elif choice_key == "C" and STAGED:
        if confirm_dialog(stdscr, "Clear", "Clear all staged changes?"):
            STAGED.clear()
            message_dialog(stdscr, "Cleared", "Staged changes cleared.")


# ============================================================
# Main TUI
# ============================================================

def main(stdscr):
    curses.curs_set(0); curses.start_color(); curses.use_default_colors()
    curses.init_pair(C_NORMAL,   curses.COLOR_WHITE,  -1)
    curses.init_pair(C_SELECTED, curses.COLOR_BLACK,  curses.COLOR_CYAN)
    curses.init_pair(C_HEADER,   curses.COLOR_CYAN,   -1)
    curses.init_pair(C_TITLE,    curses.COLOR_YELLOW, -1)
    curses.init_pair(C_STAGED,   curses.COLOR_YELLOW, -1)
    curses.init_pair(C_OK,       curses.COLOR_GREEN,  -1)
    curses.init_pair(C_WARN,     curses.COLOR_RED,    -1)
    curses.init_pair(C_BORDER,   curses.COLOR_CYAN,   -1)
    stdscr.bkgd(' ', curses.color_pair(C_NORMAL))

    tree = build_tree(); flat = flatten_tree(tree)
    tree_sel = 0; tree_offset = 0
    menu_sel = 0; menu_offset = 0
    focus = "menu"; section = "main"
    selected_node = None; esc_count = 0; right_scroll = 0

    while True:
        h, w = stdscr.getmaxyx()
        tree_w = w // 3; menu_w = w - tree_w - 1
        content_h = h - 3
        stdscr.erase()

        # Header
        header = f" Mobuntu Developer Masterkit -- {VERSION} "
        staged_info = f" Staged: {len(STAGED)} " if STAGED else ""
        stdscr.attron(curses.color_pair(C_HEADER) | curses.A_BOLD)
        stdscr.addstr(0, 0, " " * w)
        stdscr.addstr(0, (w - len(header)) // 2, header)
        if staged_info:
            stdscr.addstr(0, w - len(staged_info) - 1, staged_info,
                          curses.color_pair(C_STAGED) | curses.A_BOLD)
        stdscr.attroff(curses.color_pair(C_HEADER) | curses.A_BOLD)

        for row in range(1, h - 1):
            stdscr.addch(row, tree_w, curses.ACS_VLINE, curses.color_pair(C_BORDER))

        # Left pane title
        left_title = "[ Files ] <--" if focus == "tree" else "[ Files ]"
        stdscr.addstr(1, 1, left_title[:tree_w-2], curses.color_pair(C_TITLE) | curses.A_BOLD)
        stdscr.addch(1, tree_w, curses.ACS_VLINE, curses.color_pair(C_BORDER))

        # Right pane title
        right_title = f"[ {section.upper()} ] <--" if focus == "menu" else f"[ {section.upper()} ]"
        stdscr.addstr(1, tree_w + 2, right_title[:menu_w-2], curses.color_pair(C_TITLE) | curses.A_BOLD)

        # Draw tree
        flat = flatten_tree(tree)
        visible_tree = content_h - 1
        tree_offset = max(0, min(tree_offset, len(flat) - 1))
        if tree_sel >= tree_offset + visible_tree: tree_offset = tree_sel - visible_tree + 1
        if tree_sel < tree_offset: tree_offset = tree_sel

        for i, (depth, node) in enumerate(flat[tree_offset:tree_offset + visible_tree]):
            row = i + 2; idx = i + tree_offset
            prefix = "  " * depth
            expand = "[-] " if (node.children and node.expanded) else \
                     "[+] " if node.children else "    "
            label = (prefix + expand + node.label)[:tree_w - 2]
            attr = curses.color_pair(C_SELECTED) if (idx == tree_sel and focus == "tree") else \
                   (curses.color_pair(C_NORMAL) | curses.A_BOLD if idx == tree_sel else
                    curses.color_pair(C_NORMAL))
            stdscr.addstr(row, 1, label.ljust(tree_w - 1)[:tree_w - 1], attr)
            stdscr.addch(row, tree_w, curses.ACS_VLINE, curses.color_pair(C_BORDER))

        # Draw right pane
        right_lines = get_right_content(section, selected_node)
        visible = content_h - 1

        if section == "main":
            info_lines = right_lines
            info_h = min(len(info_lines), visible // 2)
            for i, line in enumerate(info_lines[:info_h]):
                stdscr.addstr(i + 2, tree_w + 2, line[:menu_w-2], curses.color_pair(C_NORMAL))
            menu_start = info_h + 3
            stdscr.addstr(menu_start - 1, tree_w + 2, "--- Sections ---", curses.color_pair(C_HEADER))
            avail = visible - menu_start
            if menu_sel >= menu_offset + avail: menu_offset = menu_sel - avail + 1
            if menu_sel < menu_offset: menu_offset = menu_sel
            for i, (label, key) in enumerate(MENU_SECTIONS[menu_offset:]):
                row = menu_start + i
                if row >= h - 1: break
                idx = i + menu_offset
                attr = curses.color_pair(C_SELECTED) if (idx == menu_sel and focus == "menu") else \
                       curses.color_pair(C_NORMAL)
                stdscr.addstr(row, tree_w + 2, f"  {label}".ljust(menu_w-2)[:menu_w-2], attr)
        else:
            right_scroll = max(0, min(right_scroll, max(0, len(right_lines) - 1)))
            for i, line in enumerate(right_lines[right_scroll:right_scroll + visible]):
                row = i + 2
                if row >= h - 1: break
                attr = curses.color_pair(C_NORMAL)
                if selected_node and selected_node.path and \
                   str(selected_node.path).endswith(".conf"):
                    key_part = line.split("=")[0].strip()
                    if key_part in HIGHLIGHT_KEYS:
                        attr = curses.color_pair(C_WARN) | curses.A_BOLD
                stdscr.addstr(row, tree_w + 2, line[:menu_w-2], attr)
            hints = "[1-9] Action  [Esc] Back  [Up/Down] Scroll"
            stdscr.addstr(h - 2, tree_w + 2, hints[:menu_w-2], curses.color_pair(C_HEADER))

        # Status bar
        env = get_build_env()
        device_info = env.get("DEVICE_NAME","No device") + " | " + \
                      env.get("UBUNTU_RELEASE","?") + " | " + \
                      env.get("FAKEMACHINE_BACKEND","?")
        status = f" Tab=panes  Esc=back  q=quit  |  {device_info} "
        stdscr.attron(curses.color_pair(C_HEADER))
        stdscr.addstr(h - 1, 0, status[:w].ljust(w - 1))
        stdscr.attroff(curses.color_pair(C_HEADER))
        stdscr.refresh()

        # Input
        k = stdscr.getch()

        if k in (ord('q'), ord('Q')):
            if STAGED and not confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged changes.\nQuit anyway?"): continue
            break
        elif k == 27:
            esc_count += 1
            if section != "main":
                section = "main"; selected_node = None; right_scroll = 0; esc_count = 0
            elif esc_count >= 2:
                if STAGED and not confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged.\nQuit?"): esc_count = 0; continue
                break
        else:
            esc_count = 0

        if k == ord('\t'):
            focus = "menu" if focus == "tree" else "tree"
        elif focus == "tree":
            if k == curses.KEY_UP:   tree_sel = max(0, tree_sel - 1)
            elif k == curses.KEY_DOWN: tree_sel = min(len(flat)-1, tree_sel+1)
            elif k in (curses.KEY_ENTER, 10, 13):
                _, node = flat[tree_sel]
                if node.children: node.expanded = not node.expanded
                elif node.path and Path(str(node.path)).is_file():
                    selected_node = node; section = "file"; right_scroll = 0
        elif focus == "menu":
            if section == "main":
                if k == curses.KEY_UP:   menu_sel = max(0, menu_sel - 1)
                elif k == curses.KEY_DOWN: menu_sel = min(len(MENU_SECTIONS)-1, menu_sel+1)
                elif k in (curses.KEY_ENTER, 10, 13):
                    _, key = MENU_SECTIONS[menu_sel]
                    if key == "exit":
                        if STAGED and not confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged.\nQuit?"): continue
                        break
                    else:
                        section = key; selected_node = None; right_scroll = 0
            else:
                if k == curses.KEY_UP:   right_scroll = max(0, right_scroll-1)
                elif k == curses.KEY_DOWN: right_scroll = min(max(0, len(right_lines)-1), right_scroll+1)
                env = get_build_env()
                ch = chr(k) if 32 <= k <= 126 else ""
                if section == "device" and ch in "123":
                    action_device(stdscr, ch); tree = build_tree()
                elif section == "audio" and ch in "12":
                    action_audio(stdscr, ch, env); tree = build_tree()
                elif section == "verifier" and ch in "12":
                    action_verifier(stdscr, ch, env); tree = build_tree()
                elif section == "basecache" and ch in "12":
                    action_basecache(stdscr, ch); tree = build_tree()
                elif section == "staged" and ch in "AaCc":
                    action_staged(stdscr, ch.upper())


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
    print("Masterkit closed.")
