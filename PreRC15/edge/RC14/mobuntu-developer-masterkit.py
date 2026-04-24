#!/usr/bin/env python3
"""
Mobuntu Developer Masterkit — RC14
Regedit-style TUI: left tree pane + right content/menu pane
Navigation: arrow keys, Enter, Esc, Tab to switch panes
"""

import curses
import os
import sys
import subprocess
import tempfile
import json
import time
from pathlib import Path

# ============================================================
# Constants
# ============================================================
VERSION = "RC14"
SCRIPT_DIR = Path(__file__).parent.resolve()
DEVICES_DIR = SCRIPT_DIR / "devices"
STAGED = []  # list of (description, src, dst)

# Color pairs
C_NORMAL    = 1
C_SELECTED  = 2
C_HEADER    = 3
C_TITLE     = 4
C_STAGED    = 5
C_OK        = 6
C_WARN      = 7
C_BORDER    = 8

# Keys to highlight in .conf file previews
HIGHLIGHT_KEYS = {
    "DEVICE_QUIRKS", "KERNEL_METHOD", "BOOT_METHOD",
    "FIRMWARE_METHOD", "DEVICE_SERVICES", "KERNEL_VERSION_PIN",
    "KERNEL_REPO", "FIRMWARE_REPO",
}

# ============================================================
# Tree node
# ============================================================
class Node:
    def __init__(self, label, path=None, children=None, action=None):
        self.label = label
        self.path = path
        self.children = children or []
        self.action = action
        self.expanded = True

def build_tree():
    root = []

    scripts = Node("Scripts", children=[])
    for name in sorted(["1_preflight.sh","2_kernel_prep.sh","3_rootfs_cooker.sh",
                         "4_enter_chroot.sh","5_seal_rootfs.sh","watchdog.sh",
                         "verify_build.sh","mobuntu-developer-masterkit.py"]):
        p = SCRIPT_DIR / name
        scripts.children.append(Node(name, path=p))
    root.append(scripts)

    devices = Node("devices/", children=[])
    if DEVICES_DIR.exists():
        for f in sorted(DEVICES_DIR.iterdir()):
            if f.is_file():
                devices.children.append(Node(f.name, path=f))
    if not devices.children:
        devices.children.append(Node("(empty)"))
    root.append(devices)

    kp = Node("kernel_payload/", children=[])
    kp_dir = SCRIPT_DIR / "kernel_payload"
    if kp_dir.exists():
        for f in sorted(kp_dir.glob("*.deb")):
            kp.children.append(Node(f.name, path=f))
    if not kp.children:
        kp.children.append(Node("(no .deb files)"))
    root.append(kp)

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

    benv = SCRIPT_DIR / "build.env"
    root.append(Node("build.env" + (" [OK]" if benv.exists() else " [NOT GENERATED]"),
                     path=benv if benv.exists() else None))

    return root


def flatten_tree(nodes, depth=0):
    result = []
    for node in nodes:
        result.append((depth, node))
        if node.expanded and node.children:
            result.extend(flatten_tree(node.children, depth + 1))
    return result


# ============================================================
# Right pane content
# ============================================================

MENU_SECTIONS = [
    ("[>] Boot Chain",        "bootchain"),
    ("[D] Device Config",     "device"),
    ("[A] APT & Packages",    "apt"),
    ("[K] Kernel",            "kernel"),
    ("[S] Service Ordering",  "services"),
    ("[~] Audio Config",      "audio"),
    ("[V] Verifier Generator","verifier"),
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
        if not p.exists():
            return ["(file not found)"]
        if p.stat().st_size > 100000:
            return ["(file too large to preview)"]
        return p.read_text(errors="replace").splitlines()[:200]
    except Exception as e:
        return [f"(error: {e})"]

def get_right_content(section, selected_node):
    lines = []

    if selected_node and selected_node.path and Path(str(selected_node.path)).is_file():
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
                       "DEVICE_HOSTNAME","DEVICE_QUIRKS","BOOT_METHOD"]:
                if k in env:
                    lines.append(f"  {k}: {env[k]}")
        else:
            lines.append("  build.env not generated.")
            lines.append("  Run 1_preflight.sh first.")
        lines.append("")
        lines.append(f"  Staged changes: {len(STAGED)}")

    elif section == "bootchain":
        lines.append("=== Mobuntu Build Chain ===")
        lines.append("")
        lines.append("  Run scripts in this order:")
        lines.append("")
        lines.append("  [1] 1_preflight.sh")
        lines.append("      Host setup, device selection, build.env")
        lines.append("      generation. Optionally auto-runs 2 and 3.")
        lines.append("")
        lines.append("  [2] 2_kernel_prep.sh")
        lines.append("      Downloads kernel .deb files into")
        lines.append("      kernel_payload/.")
        lines.append("")
        lines.append("  [3] 3_rootfs_cooker.sh")
        lines.append("      Debootstrap + chroot build. Installs all")
        lines.append("      packages, firmware, services, and kernel")
        lines.append("      inside the rootfs. Quirk-gated per device.")
        lines.append("")
        lines.append("  [4] verify_build.sh  (recommended)")
        lines.append("      Verifies rootfs integrity before sealing.")
        lines.append("      Checks are device-family aware via quirks.")
        lines.append("")
        lines.append("  [5] 5_seal_rootfs.sh")
        lines.append("      Seals and packages the image for flashing.")
        lines.append("")
        lines.append("      SDM845 (mkbootimg):")
        lines.append("        -> boot.img + root.img")
        lines.append("        -> fastboot flash boot / system")
        lines.append("")
        lines.append("      Switch (l4t):")
        lines.append("        -> kernel.lz4 + initrd.lz4 + DTB")
        lines.append("        -> root.img (dd to Linux partition)")
        lines.append("        -> Copy boot files to switchroot/ubuntu/")
        lines.append("")
        lines.append("  --- Dev / Automation tools ---")
        lines.append("")
        lines.append("  [DEV] 4_enter_chroot.sh")
        lines.append("      Interactive chroot for manual inspection.")
        lines.append("      Do NOT run during automated builds.")
        lines.append("")
        lines.append("  [AUTO] watchdog.sh")
        lines.append("      Unattended runner: 2 -> 3 -> verify -> 5")
        lines.append("      Uses ZWJ (U+200D) for clean-exit detection.")

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
            lines.append("  devices/ folder not found")

    elif section == "apt":
        lines.append("=== APT & Packages ===")
        lines.append("")
        lines.append("  [1] Add custom repo")
        lines.append("  [2] Pin package version")
        lines.append("  [3] Add extra packages")
        lines.append("")
        if "DEVICE_PACKAGES" in env:
            lines.append("Current packages:")
            for p in env["DEVICE_PACKAGES"].split():
                lines.append(f"  - {p}")

    elif section == "kernel":
        lines.append("=== Kernel Config ===")
        lines.append("")
        lines.append("  [1] Edit kernel cmdline")
        lines.append("  [2] Edit version pin")
        lines.append("")
        for k in ["KERNEL_METHOD","KERNEL_REPO","KERNEL_VERSION_PIN","KERNEL_SERIES"]:
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
            lines.append("Default service order:")
            for s in ["qrtr-ns","rmtfs","pd-mapper","tqftpserv"]:
                lines.append(f"  -> {s}")
        elif "l4t_bootfiles" in quirks:
            lines.append("Device family: NVIDIA Tegra (L4T)")
            lines.append("No Qualcomm services required.")
        else:
            lines.append("Device family: unknown (check DEVICE_QUIRKS)")
        lines.append("")
        if "DEVICE_SERVICES" in env:
            lines.append(f"Configured: {env['DEVICE_SERVICES']}")

    elif section == "audio":
        lines.append("=== Audio Config ===")
        lines.append("")
        lines.append("  [1] Generate 51-qcom.conf")
        lines.append("  [2] Edit existing config")
        lines.append("")
        lines.append("SDM845 recommended settings:")
        lines.append("  audio.format         = S16LE")
        lines.append("  audio.rate           = 48000")
        lines.append("  api.alsa.period-size = 4096")
        lines.append("  api.alsa.period-num  = 6")
        lines.append("  api.alsa.headroom    = 512")
        lines.append("")
        if "DEVICE_CODENAME" in env:
            conf = DEVICES_DIR / f"{env['DEVICE_CODENAME']}-51-qcom.conf"
            lines.append(f"Config file: {conf.name}")
            lines.append("  EXISTS" if conf.exists() else "  NOT FOUND")

    elif section == "verifier":
        lines.append("=== Verifier Generator ===")
        lines.append("")
        lines.append("  [1] Generate custom verifier")
        lines.append("  [2] View verify_build.sh")
        lines.append("")
        lines.append("Generates a device-specific")
        lines.append("verification script that checks:")
        lines.append("  - Packages installed")
        lines.append("  - Services enabled")
        lines.append("  - Audio config present")
        lines.append("  - Kernel present")
        lines.append("  - Firmware present")
        lines.append("")
        lines.append("Qualcomm-specific checks gated")
        lines.append("behind qcom_services quirk.")

    elif section == "staged":
        lines.append("=== Staged Changes ===")
        lines.append("")
        if STAGED:
            for i, (desc, src, dst) in enumerate(STAGED):
                lines.append(f"  [{i+1}] {desc}")
                if dst:
                    lines.append(f"       -> {dst}")
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
    dy, dx = h // 2 - dh // 2, w // 2 - dw // 2
    win = curses.newwin(dh, dw, dy, dx)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    win.addstr(2, 2, prompt[:dw-4])
    win.addstr(4, 2, "> ")
    curses.echo()
    curses.curs_set(1)
    win.refresh()
    win.addstr(4, 4, default)
    win.refresh()
    result = win.getstr(4, 4, dw - 6).decode("utf-8", errors="replace")
    curses.noecho()
    curses.curs_set(0)
    return result.strip() if result.strip() else default


def message_dialog(stdscr, title, msg):
    h, w = stdscr.getmaxyx()
    lines = msg.splitlines()
    dh = min(len(lines) + 4, h - 4)
    dw = min(max((len(l) for l in lines), default=10) + 4, w - 4)
    dy, dx = h // 2 - dh // 2, w // 2 - dw // 2
    win = curses.newwin(dh, dw, dy, dx)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    for i, line in enumerate(lines[:dh-3]):
        win.addstr(i + 2, 2, line[:dw-4])
    win.addstr(dh - 1, dw // 2 - 5, "[ OK ]", curses.color_pair(C_SELECTED))
    win.refresh()
    win.getch()


def confirm_dialog(stdscr, title, msg):
    h, w = stdscr.getmaxyx()
    lines = msg.splitlines()
    dh = len(lines) + 5
    dw = min(max((len(l) for l in lines), default=10) + 6, w - 4)
    dy, dx = h // 2 - dh // 2, w // 2 - dw // 2
    win = curses.newwin(dh, dw, dy, dx)
    win.bkgd(' ', curses.color_pair(C_NORMAL))
    win.box()
    win.addstr(0, 2, f" {title} ", curses.color_pair(C_TITLE) | curses.A_BOLD)
    for i, line in enumerate(lines):
        win.addstr(i + 2, 2, line[:dw-4])
    focus = 0
    while True:
        win.addstr(dh - 2, dw // 2 - 9, "[ Yes ]",
                   curses.color_pair(C_SELECTED) if focus == 0 else curses.color_pair(C_OK))
        win.addstr(dh - 2, dw // 2 + 0, "  [ No ]",
                   curses.color_pair(C_SELECTED) if focus == 1 else curses.color_pair(C_WARN))
        win.refresh()
        k = win.getch()
        if k in (curses.KEY_LEFT, curses.KEY_RIGHT, ord('\t')):
            focus = 1 - focus
        elif k in (curses.KEY_ENTER, 10, 13):
            return focus == 0
        elif k == 27:
            return False


# ============================================================
# Actions
# ============================================================

def action_device(stdscr, choice_key):
    env = get_build_env()
    if choice_key == "1":
        configs = list(DEVICES_DIR.glob("*.conf")) if DEVICES_DIR.exists() else []
        if not configs:
            message_dialog(stdscr, "Device Config", "No configs found in devices/")
            return
        names = [f.name for f in configs]
        message_dialog(stdscr, "Load Config", "\n".join(names) + "\n\nType filename in next prompt.")
        sel = input_dialog(stdscr, "Load Config", "Enter config filename:", names[0] if names else "")
        p = DEVICES_DIR / sel
        if p.exists():
            message_dialog(stdscr, "Loaded", f"Config loaded: {sel}\n(Restart to reflect in tree)")
        else:
            message_dialog(stdscr, "Error", f"Not found: {sel}")

    elif choice_key == "2":
        name   = input_dialog(stdscr, "New Device", "Full device name:", "My Device")
        code   = input_dialog(stdscr, "New Device", "Codename:", "mydevice")
        brand  = input_dialog(stdscr, "New Device", "Brand:", "brand")
        host   = input_dialog(stdscr, "New Device", "Hostname:", f"mobuntu-{code}")
        label  = input_dialog(stdscr, "New Device", "Image label:", f"mobuntu-{code}")
        family = input_dialog(stdscr, "New Device", "Device family [qcom/l4t]:", "qcom")
        outfile = DEVICES_DIR / f"{brand}-{code}.conf"
        DEVICES_DIR.mkdir(exist_ok=True)
        if outfile.exists():
            if confirm_dialog(stdscr, "Warning", f"{outfile.name} exists.\nRename original to .bak?"):
                outfile.rename(str(outfile) + ".bak")
            else:
                return

        if family == "l4t":
            quirks         = "l4t_bootfiles firmware_source_online"
            boot_method    = "l4t"
            kernel_method  = "custom_url"
            kernel_repo    = ""
            kernel_series  = "tegra210"
            firmware_method = "apt"
            dtb_append     = "false"
            mkbootimg_vals = ("","","","","")
        else:
            quirks         = "dtb_append qcom_services firmware_source_local"
            boot_method    = "mkbootimg"
            kernel_method  = "mobian"
            kernel_repo    = "https://repo.mobian.org/pool/main/l/"
            kernel_series  = "sdm845"
            firmware_method = "git"
            dtb_append     = "true"
            mkbootimg_vals = ("4096","0x00000000","0x00008000","0x01000000","0x00000100")

        ps, base, koff, roff, toff = mkbootimg_vals
        outfile.write_text(f"""# Mobuntu Device Config -- {VERSION}
# Generated by mobuntu-developer-masterkit
DEVICE_NAME="{name}"
DEVICE_CODENAME="{code}"
DEVICE_BRAND="{brand}"
DEVICE_ARCH="arm64"
DEVICE_SIM_SLOTS=0
DEVICE_HOSTNAME="{host}"
DEVICE_IMAGE_LABEL="{label}"
DEVICE_PACKAGES=""
DEVICE_SERVICES=""
DEVICE_QUIRKS="{quirks}"
KERNEL_METHOD="{kernel_method}"
KERNEL_REPO="{kernel_repo}"
KERNEL_SERIES="{kernel_series}"
KERNEL_VERSION_PIN=""
BOOT_METHOD="{boot_method}"
BOOT_DTB=""
BOOT_DTB_APPEND="{dtb_append}"
BOOT_PANEL_PICKER="false"
MKBOOTIMG_PAGESIZE="{ps}"
MKBOOTIMG_BASE="{base}"
MKBOOTIMG_KERNEL_OFFSET="{koff}"
MKBOOTIMG_RAMDISK_OFFSET="{roff}"
MKBOOTIMG_TAGS_OFFSET="{toff}"
UBOOT_URL=""
UEFI_URL=""
UEFI_ESP_SIZE_MB=""
FIRMWARE_METHOD="{firmware_method}"
FIRMWARE_REPO=""
FIRMWARE_INSTALL_PATH=""
""")
        message_dialog(stdscr, "Created", f"Device config created:\n{outfile.name}")

    elif choice_key == "3":
        message_dialog(stdscr, "Edit Config",
                       "Select a config file from the\nleft tree panel and press Enter\nto view/edit it.")


def action_audio(stdscr, choice_key, env):
    codename = env.get("DEVICE_CODENAME", "device")
    if choice_key == "1":
        fmt      = input_dialog(stdscr, "Audio", "Format:", "S16LE")
        rate     = input_dialog(stdscr, "Audio", "Sample rate:", "48000")
        psize    = input_dialog(stdscr, "Audio", "period-size:", "4096")
        pnum     = input_dialog(stdscr, "Audio", "period-num:", "6")
        headroom = input_dialog(stdscr, "Audio", "headroom:", "512")
        DEVICES_DIR.mkdir(exist_ok=True)
        outfile = DEVICES_DIR / f"{codename}-51-qcom.conf"
        outfile.write_text(f"""# Mobuntu WirePlumber ALSA Tuning -- {VERSION}
# Generated by mobuntu-developer-masterkit
monitor.alsa.rules = [
  {{
    matches = [
      {{ node.name = "~alsa_input.*" }},
      {{ node.name = "~alsa_output.*" }}
    ]
    actions = {{
      update-props = {{
        audio.format           = "{fmt}"
        audio.rate             = {rate}
        api.alsa.period-size   = {psize}
        api.alsa.period-num    = {pnum}
        api.alsa.headroom      = {headroom}
      }}
    }}
  }}
]
""")
        message_dialog(stdscr, "Audio Config", f"Generated:\n{outfile.name}")


def action_verifier(stdscr, choice_key, env):
    codename    = env.get("DEVICE_CODENAME", "device")
    device_name = env.get("DEVICE_NAME", "Unknown Device")
    pkgs        = env.get("DEVICE_PACKAGES", "")
    quirks      = env.get("DEVICE_QUIRKS", "")
    if choice_key == "1":
        outfile = SCRIPT_DIR / f"verify_{codename}.sh"
        if "qcom_services" in quirks:
            hw_checks = f"""
for pkg in {pkgs} qrtr-tools rmtfs pd-mapper tqftpserv pipewire wireplumber alsa-ucm-conf; do
    chroot "$ROOTFS_DIR" dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && ok "$pkg" || fail "$pkg NOT installed"
done
[ -f "$ROOTFS_DIR/usr/share/wireplumber/wireplumber.conf.d/51-qcom.conf" ] && ok "51-qcom.conf present" || fail "51-qcom.conf missing"
ls "$ROOTFS_DIR/boot/vmlinuz-"*sdm845* 2>/dev/null | grep -q . && ok "SDM845 kernel found" || fail "SDM845 kernel missing"
for fw in adsp.mbn cdsp.mbn venus.mbn slpi.mbn; do
    find "$ROOTFS_DIR/lib/firmware" -name "$fw" 2>/dev/null | grep -q . && ok "$fw" || warn "$fw not found"
done
for jsn in slpius.jsn slpir.jsn adspr.jsn adspua.jsn; do
    find "$ROOTFS_DIR/lib/firmware" -name "$jsn" 2>/dev/null | grep -q . && ok "$jsn" || warn "$jsn not found"
done
"""
        else:
            hw_checks = """
ls "$ROOTFS_DIR/boot/vmlinuz-"* 2>/dev/null | grep -q . && ok "Kernel found" || fail "No kernel found"
"""
        outfile.write_text(f"""#!/bin/bash
# Mobuntu -- Custom Verifier: {device_name}
# {VERSION} -- Generated by mobuntu-developer-masterkit
PASS=0; FAIL=0; WARN=0
ok()   {{ echo "  [PASS] $1"; ((PASS++)); }}
fail() {{ echo "  [FAIL] $1"; ((FAIL++)); }}
warn() {{ echo "  [WARN] $1"; ((WARN++)); }}
source build.env 2>/dev/null || {{ echo "ERROR: build.env not found"; exit 1; }}
echo "======================================================="
echo "   Mobuntu Verifier -- {device_name}"
echo "======================================================="
[ "$DEVICE_CODENAME" = "{codename}" ] && ok "Codename: {codename}" || fail "Codename mismatch"
{hw_checks}
echo ""
echo "RESULTS: $PASS passed | $WARN warnings | $FAIL failed"
[ $FAIL -eq 0 ] && echo "ALL CHECKS PASSED\u200d" && exit 0 || exit 1
""")
        outfile.chmod(0o755)
        message_dialog(stdscr, "Verifier", f"Generated:\n{outfile.name}")


def action_staged(stdscr, choice_key):
    if choice_key == "A" and STAGED:
        if confirm_dialog(stdscr, "Apply", f"Apply {len(STAGED)} staged changes?"):
            errors = []
            for desc, src, dst in STAGED:
                try:
                    if src and dst:
                        Path(dst).parent.mkdir(parents=True, exist_ok=True)
                        import shutil
                        shutil.copy2(src, dst)
                except Exception as e:
                    errors.append(f"{desc}: {e}")
            STAGED.clear()
            if errors:
                message_dialog(stdscr, "Errors", "\n".join(errors))
            else:
                message_dialog(stdscr, "Applied", "All changes applied.")
    elif choice_key == "C" and STAGED:
        if confirm_dialog(stdscr, "Clear", "Clear all staged changes?"):
            STAGED.clear()
            message_dialog(stdscr, "Cleared", "Staged changes cleared.")


# ============================================================
# Main TUI
# ============================================================

def main(stdscr):
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(C_NORMAL,   curses.COLOR_WHITE,  -1)
    curses.init_pair(C_SELECTED, curses.COLOR_BLACK,  curses.COLOR_CYAN)
    curses.init_pair(C_HEADER,   curses.COLOR_CYAN,   -1)
    curses.init_pair(C_TITLE,    curses.COLOR_YELLOW, -1)
    curses.init_pair(C_STAGED,   curses.COLOR_YELLOW, -1)
    curses.init_pair(C_OK,       curses.COLOR_GREEN,  -1)
    curses.init_pair(C_WARN,     curses.COLOR_RED,    -1)
    curses.init_pair(C_BORDER,   curses.COLOR_CYAN,   -1)
    stdscr.bkgd(' ', curses.color_pair(C_NORMAL))

    tree = build_tree()
    flat = flatten_tree(tree)
    tree_sel    = 0
    tree_offset = 0
    menu_sel    = 0
    menu_offset = 0
    focus       = "menu"
    section     = "main"
    selected_node = None
    esc_count   = 0
    right_scroll = 0

    while True:
        h, w = stdscr.getmaxyx()
        tree_w   = w // 3
        menu_w   = w - tree_w - 1
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

        # Divider
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
        if tree_sel >= tree_offset + visible_tree:
            tree_offset = tree_sel - visible_tree + 1
        if tree_sel < tree_offset:
            tree_offset = tree_sel

        for i, (depth, node) in enumerate(flat[tree_offset:tree_offset + visible_tree]):
            row = i + 2
            idx = i + tree_offset
            prefix = "  " * depth
            has_children = bool(node.children)
            expand = "[-] " if (has_children and node.expanded) else \
                     "[+] " if has_children else "    "
            label = (prefix + expand + node.label)[:tree_w - 2]
            if idx == tree_sel and focus == "tree":
                attr = curses.color_pair(C_SELECTED)
            elif idx == tree_sel:
                attr = curses.color_pair(C_NORMAL) | curses.A_BOLD
            else:
                attr = curses.color_pair(C_NORMAL)
            stdscr.addstr(row, 1, label.ljust(tree_w - 1)[:tree_w - 1], attr)
            stdscr.addch(row, tree_w, curses.ACS_VLINE, curses.color_pair(C_BORDER))

        # Draw right pane
        right_lines = get_right_content(section, selected_node)
        visible_menu = content_h - 1

        if section == "main":
            info_lines = right_lines
            info_h = min(len(info_lines), visible_menu // 2)
            for i, line in enumerate(info_lines[:info_h]):
                stdscr.addstr(i + 2, tree_w + 2, line[:menu_w - 2], curses.color_pair(C_NORMAL))

            menu_start_row = info_h + 3
            stdscr.addstr(menu_start_row - 1, tree_w + 2, "--- Sections ---",
                          curses.color_pair(C_HEADER))

            slots = visible_menu - menu_start_row
            if menu_sel >= menu_offset + slots:
                menu_offset = menu_sel - slots + 1
            if menu_sel < menu_offset:
                menu_offset = menu_sel

            for i, (label, key) in enumerate(MENU_SECTIONS[menu_offset:]):
                row = menu_start_row + i
                if row >= h - 1:
                    break
                idx = i + menu_offset
                attr = curses.color_pair(C_SELECTED) if (idx == menu_sel and focus == "menu") else \
                       curses.color_pair(C_NORMAL)
                stdscr.addstr(row, tree_w + 2, f"  {label}".ljust(menu_w - 2)[:menu_w - 2], attr)
        else:
            visible = content_h - 1
            right_scroll = min(right_scroll, max(0, len(right_lines) - 1))
            for i, line in enumerate(right_lines[right_scroll:right_scroll + visible]):
                row = i + 2
                if row >= h - 1:
                    break
                attr = curses.color_pair(C_NORMAL)
                # Highlight quirk keys in .conf file previews
                if selected_node and selected_node.path and \
                   str(selected_node.path).endswith(".conf"):
                    key_part = line.split("=")[0].strip()
                    if key_part in HIGHLIGHT_KEYS:
                        attr = curses.color_pair(C_WARN) | curses.A_BOLD
                stdscr.addstr(row, tree_w + 2, line[:menu_w - 2], attr)
            hints = "[1-9] Action  [Esc] Back  [Up/Down] Scroll"
            stdscr.addstr(h - 2, tree_w + 2, hints[:menu_w - 2], curses.color_pair(C_HEADER))

        # Status bar
        env = get_build_env()
        device_info = env.get("DEVICE_NAME", "No device") + " | " + env.get("UBUNTU_RELEASE", "?")
        status = f" Tab=switch  Esc=back  q=quit  |  {device_info} "
        stdscr.attron(curses.color_pair(C_HEADER))
        stdscr.addstr(h - 1, 0, status[:w].ljust(w - 1))
        stdscr.attroff(curses.color_pair(C_HEADER))

        stdscr.refresh()

        # Input
        k = stdscr.getch()

        if k in (ord('q'), ord('Q')):
            if STAGED:
                if confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged changes unsaved.\nQuit anyway?"):
                    break
            else:
                break

        elif k == 27:
            esc_count += 1
            if section != "main":
                section = "main"
                selected_node = None
                right_scroll = 0
                esc_count = 0
            elif esc_count >= 2:
                if STAGED:
                    if confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged changes.\nQuit?"):
                        break
                else:
                    break
        else:
            esc_count = 0

        if k == ord('\t'):
            focus = "menu" if focus == "tree" else "tree"

        elif focus == "tree":
            if k == curses.KEY_UP:
                tree_sel = max(0, tree_sel - 1)
            elif k == curses.KEY_DOWN:
                tree_sel = min(len(flat) - 1, tree_sel + 1)
            elif k in (curses.KEY_ENTER, 10, 13):
                _, node = flat[tree_sel]
                if node.children:
                    node.expanded = not node.expanded
                elif node.path and Path(str(node.path)).is_file():
                    selected_node = node
                    section = "file"
                    right_scroll = 0

        elif focus == "menu":
            if section == "main":
                if k == curses.KEY_UP:
                    menu_sel = max(0, menu_sel - 1)
                elif k == curses.KEY_DOWN:
                    menu_sel = min(len(MENU_SECTIONS) - 1, menu_sel + 1)
                elif k in (curses.KEY_ENTER, 10, 13):
                    _, key = MENU_SECTIONS[menu_sel]
                    if key == "exit":
                        if STAGED:
                            if confirm_dialog(stdscr, "Quit", f"{len(STAGED)} staged changes.\nQuit?"):
                                break
                        else:
                            break
                    else:
                        section = key
                        selected_node = None
                        right_scroll = 0
            else:
                if k == curses.KEY_UP:
                    right_scroll = max(0, right_scroll - 1)
                elif k == curses.KEY_DOWN:
                    right_scroll = min(max(0, len(right_lines) - 1), right_scroll + 1)
                env = get_build_env()
                ch = chr(k) if 32 <= k <= 126 else ""
                if section == "device" and ch in "123":
                    action_device(stdscr, ch)
                    tree = build_tree()
                elif section == "audio" and ch in "12":
                    action_audio(stdscr, ch, env)
                    tree = build_tree()
                elif section == "verifier" and ch in "12":
                    action_verifier(stdscr, ch, env)
                    tree = build_tree()
                elif section == "staged" and ch.upper() in "AC":
                    action_staged(stdscr, ch.upper())


if __name__ == "__main__":
    try:
        curses.wrapper(main)
    except KeyboardInterrupt:
        pass
    print("Masterkit closed.")
