#!/usr/bin/env python3
"""
mobuntu-devkit  —  Grand Developer Kit Reset
Regedit-style split-pane TUI for managing Mobuntu Orange builds.

Layout:
  ┌─ Nav ──────────┐ ┌─ Content ──────────────────────────────┐
  │  tree / menu   │ │  details, actions, output              │
  └────────────────┘ └────────────────────────────────────────┘
  ┌─ Status / Progress bar ────────────────────────────────────┐
  └────────────────────────────────────────────────────────────┘

Keys: ↑↓ navigate  Enter select  Tab switch pane  q quit  r refresh
"""

import curses
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

# ── Optional requests for download progress ───────────────────────────────────
try:
    import requests as _requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR  = Path(__file__).parent.resolve()
FORK_DIR    = SCRIPT_DIR / "Mobuntu"
DEVICES_DIR = FORK_DIR / "devices"
SYNC_SCRIPT = SCRIPT_DIR / "sync.py"

# ── Colours (pair indices) ────────────────────────────────────────────────────
C_NORMAL    = 1
C_SELECTED  = 2
C_HEADER    = 3
C_BORDER    = 4
C_STATUS    = 5
C_PROGRESS  = 6
C_KEY       = 7
C_WARN      = 8
C_OK        = 9
C_DIM       = 10

NAV_WIDTH   = 26   # left pane width including border


# ══════════════════════════════════════════════════════════════════════════════
# Nav tree
# ══════════════════════════════════════════════════════════════════════════════

class NavNode:
    def __init__(self, label, key, children=None, parent=None):
        self.label    = label
        self.key      = key          # unique id used by content pane
        self.children = children or []
        self.parent   = parent
        self.expanded = True
        for c in self.children:
            c.parent = self

    def flat(self, depth=0):
        yield (depth, self)
        if self.expanded:
            for c in self.children:
                yield from c.flat(depth + 1)


def build_tree() -> NavNode:
    """Build nav tree from filesystem state."""
    device_nodes = []
    if DEVICES_DIR.exists():
        for d in sorted(DEVICES_DIR.iterdir()):
            if d.is_dir() and (d / "device.conf").exists():
                device_nodes.append(NavNode(d.name, f"device:{d.name}"))

    root = NavNode("ROOT", "root", children=[
        NavNode("⟳  Sync",    "sync"),
        NavNode("⊞  Devices", "devices", children=device_nodes),
        NavNode("⚙  Build",   "build"),
        NavNode("?  About",   "about"),
    ])
    return root


# ══════════════════════════════════════════════════════════════════════════════
# Content renderers
# ══════════════════════════════════════════════════════════════════════════════

def render_sync(win, state):
    h, w = win.getmaxyx()
    ln = 1

    def put(y, x, text, attr=0):
        try:
            win.addstr(y, x, text[:w - x - 1], attr)
        except curses.error:
            pass

    put(ln, 2, "Upstream Sync", curses.color_pair(C_HEADER) | curses.A_BOLD)
    ln += 1
    put(ln, 2, "─" * (w - 4), curses.color_pair(C_BORDER))
    ln += 2

    put(ln, 2, f"Upstream : ", curses.color_pair(C_DIM))
    put(ln, 13, "https://github.com/arkadin91/mobuntu-recipes",
        curses.color_pair(C_NORMAL))
    ln += 1
    put(ln, 2, f"Fork dir : ", curses.color_pair(C_DIM))
    put(ln, 13, str(FORK_DIR), curses.color_pair(C_NORMAL))
    ln += 2

    # State from .devkit-sync-state.json
    import json
    state_file = FORK_DIR / ".devkit-sync-state.json"
    if state_file.exists():
        s = json.loads(state_file.read_text())
        put(ln, 2, "Last sync  : ", curses.color_pair(C_DIM))
        put(ln, 15, s.get("last_sync", "never")[:19], curses.color_pair(C_OK))
        ln += 1
        put(ln, 2, "Upstream   : ", curses.color_pair(C_DIM))
        sha = s.get("upstream_sha", "unknown")
        put(ln, 15, sha[:12] if sha else "unknown", curses.color_pair(C_NORMAL))
    else:
        put(ln, 2, "Never synced", curses.color_pair(C_WARN))
    ln += 2

    put(ln, 2, "Actions:", curses.color_pair(C_HEADER))
    ln += 1
    actions = [
        ("[S]", "Sync now          (pull upstream + update device confs)"),
        ("[D]", "Dry run           (show changes without writing)"),
        ("[E]", "Extract only      (show upstream vars without syncing)"),
    ]
    for key, desc in actions:
        put(ln, 4, key, curses.color_pair(C_KEY) | curses.A_BOLD)
        put(ln, 8, desc, curses.color_pair(C_NORMAL))
        ln += 1

    # Output from last sync op
    if state.get("sync_output"):
        ln += 1
        put(ln, 2, "Last output:", curses.color_pair(C_DIM))
        ln += 1
        for line in state["sync_output"][-min(10, h - ln - 2):]:
            put(ln, 4, line, curses.color_pair(C_NORMAL))
            ln += 1
            if ln >= h - 2:
                break


def render_device(win, codename, state):
    h, w = win.getmaxyx()
    ln = 1

    def put(y, x, text, attr=0):
        try:
            win.addstr(y, x, text[:w - x - 1], attr)
        except curses.error:
            pass

    conf_path = DEVICES_DIR / codename / "device.conf"
    conf = {}
    if conf_path.exists():
        for line in conf_path.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                conf[k.strip()] = v.strip().strip('"')

    put(ln, 2, f"Device: {codename}", curses.color_pair(C_HEADER) | curses.A_BOLD)
    ln += 1
    put(ln, 2, "─" * (w - 4), curses.color_pair(C_BORDER))
    ln += 2

    fields = [
        ("Model",    conf.get("DEVICE_MODEL", "?")),
        ("Brand",    conf.get("DEVICE_BRAND", "?")),
        ("SoC",      conf.get("DEVICE_SOC", "?")),
        ("Suite",    conf.get("DEVICE_SUITE", "?")),
        ("Kernel",   conf.get("KERNEL_VERSION", "?")),
        ("Displays", conf.get("DEVICE_DISPLAYS", "default")),
        ("Packages", conf.get("DEVICE_PACKAGES", "")),
        ("Services", conf.get("DEVICE_SERVICES", "")),
        ("Masked",   conf.get("DEVICE_MASKED_SERVICES", "")),
    ]

    for label, val in fields:
        if ln >= h - 4:
            break
        put(ln, 2, f"{label:<12}", curses.color_pair(C_DIM))
        color = C_WARN if val == "?" else C_NORMAL
        put(ln, 14, val, curses.color_pair(color))
        ln += 1

    # Display variants
    displays = conf.get("DEVICE_DISPLAYS", "").split()
    if len(displays) > 1:
        ln += 1
        put(ln, 2, "Display DTBs:", curses.color_pair(C_HEADER))
        ln += 1
        for d in displays:
            dtb_key = f"DEVICE_DTB_{d.upper()}"
            dtb = conf.get(dtb_key, f"sdm845-{codename}-{d}.dtb")
            default = " ← default" if d == conf.get("DEVICE_DEFAULT_DISPLAY") else ""
            put(ln, 4, f"{d:<10} {dtb}{default}", curses.color_pair(C_NORMAL))
            ln += 1

    ln += 1
    put(ln, 2, "Actions:", curses.color_pair(C_HEADER))
    ln += 1

    actions = [
        ("build", "Build image for this device"),
        ("edit",  "Edit device.conf"),
    ]
    action_idx = state.get(f"device_action:{codename}", 0)
    state[f"device_actions:{codename}"] = actions

    for i, (key_, label) in enumerate(actions):
        selected = i == action_idx and state.get("content_focus_active")
        marker = "(x)" if selected else "( )"
        attr   = (curses.color_pair(C_SELECTED) | curses.A_BOLD) if selected                  else curses.color_pair(C_NORMAL)
        put(ln, 4, f"{marker} {label}", attr)
        ln += 1


def render_devices_overview(win, state):
    h, w = win.getmaxyx()
    ln = 1

    def put(y, x, text, attr=0):
        try:
            win.addstr(y, x, text[:w - x - 1], attr)
        except curses.error:
            pass

    put(ln, 2, "Devices", curses.color_pair(C_HEADER) | curses.A_BOLD)
    ln += 1
    put(ln, 2, "─" * (w - 4), curses.color_pair(C_BORDER))
    ln += 2

    if not DEVICES_DIR.exists():
        put(ln, 2, "No devices/ directory found.", curses.color_pair(C_WARN))
        return

    for d in sorted(DEVICES_DIR.iterdir()):
        if not d.is_dir() or not (d / "device.conf").exists():
            continue
        conf = {}
        for line in (d / "device.conf").read_text().splitlines():
            if line.strip() and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                conf[k.strip()] = v.strip().strip('"')

        model  = conf.get("DEVICE_MODEL", "?")
        suite  = conf.get("DEVICE_SUITE", "?")
        kernel = conf.get("KERNEL_VERSION", "?")
        put(ln, 2, f"  {d.name:<14}", curses.color_pair(C_NORMAL) | curses.A_BOLD)
        put(ln, 18, f"{model:<16} {suite:<10} k:{kernel}",
            curses.color_pair(C_NORMAL))
        ln += 1
        if ln >= h - 2:
            break


def render_build(win, state):
    h, w = win.getmaxyx()
    ln = 1

    def put(y, x, text, attr=0):
        try:
            win.addstr(y, x, text[:w - x - 1], attr)
        except curses.error:
            pass

    put(ln, 2, "Build", curses.color_pair(C_HEADER) | curses.A_BOLD)
    ln += 1
    put(ln, 2, "─" * (w - 4), curses.color_pair(C_BORDER))
    ln += 2
    put(ln, 2, "Select a device from the nav tree to build.",
        curses.color_pair(C_DIM))
    ln += 2
    put(ln, 2, "Or use build.sh directly:", curses.color_pair(C_NORMAL))
    ln += 1
    put(ln, 4, "sudo bash Mobuntu/build.sh -d <device> [-s <suite>]",
        curses.color_pair(C_KEY))
    ln += 2
    put(ln, 2, "Flags:", curses.color_pair(C_HEADER))
    ln += 1
    flags = [
        ("-d <device>",  "Device codename  (beryllium, fajita, enchilada)"),
        ("-s <suite>",   "Suite override   (plucky, resolute)"),
        ("-i",           "Image only       (skip rootfs, reuse tarball)"),
        ("-h",           "Help"),
    ]
    for flag, desc in flags:
        put(ln, 4, f"{flag:<16}", curses.color_pair(C_KEY) | curses.A_BOLD)
        put(ln, 22, desc, curses.color_pair(C_NORMAL))
        ln += 1


def render_about(win, state):
    h, w = win.getmaxyx()
    ln = 2

    def put(y, x, text, attr=0):
        try:
            win.addstr(y, x, text[:w - x - 1], attr)
        except curses.error:
            pass

    lines = [
        ("Mobuntu Orange — Grand Developer Kit Reset", C_HEADER, curses.A_BOLD),
        ("", C_NORMAL, 0),
        ("Built on top of arkadin91/mobuntu-recipes", C_NORMAL, 0),
        ("Multi-device wrapper: beryllium, fajita, enchilada", C_NORMAL, 0),
        ("", C_NORMAL, 0),
        ("Repo   : github.com/PastorCatto/Mobuntu", C_DIM, 0),
        ("Upstream: github.com/arkadin91/mobuntu-recipes", C_DIM, 0),
        ("", C_NORMAL, 0),
        ("Keys", C_HEADER, curses.A_BOLD),
        ("  ↑ ↓      Navigate", C_NORMAL, 0),
        ("  Enter    Select / expand", C_NORMAL, 0),
        ("  Tab      Switch pane focus", C_NORMAL, 0),
        ("  q        Quit", C_NORMAL, 0),
        ("  r        Refresh tree", C_NORMAL, 0),
    ]
    for text, color, attr in lines:
        put(ln, 2, text, curses.color_pair(color) | attr)
        ln += 1
        if ln >= h - 2:
            break


# ══════════════════════════════════════════════════════════════════════════════
# Progress bar
# ══════════════════════════════════════════════════════════════════════════════

class ProgressBar:
    def __init__(self):
        self.message  = "Ready"
        self.value    = 0.0   # 0.0 – 1.0
        self.active   = False
        self._lock    = threading.Lock()

    def update(self, message, value=None):
        with self._lock:
            self.message = message
            if value is not None:
                self.value  = max(0.0, min(1.0, value))
            self.active = True

    def done(self, message="Done"):
        with self._lock:
            self.message = message
            self.value   = 1.0
            self.active  = False

    def render(self, win, y, x, width):
        with self._lock:
            msg   = self.message
            val   = self.value

        # Layout: [bar...bar] pct% message
        # bar = fixed 30% of width, label gets the rest
        bar_w   = max(10, width // 3)
        label   = f" {int(val * 100):3d}% {msg}"
        lbl_w   = width - bar_w - 4   # 4 = " [" + "] "
        filled  = int(bar_w * val)
        empty   = bar_w - filled
        bar     = "█" * filled + "░" * empty

        attr_bar = curses.color_pair(C_PROGRESS) | curses.A_BOLD
        attr_msg = curses.color_pair(C_STATUS)

        try:
            win.addstr(y, x, f"[{bar}]", attr_bar)
            win.addstr(y, x + bar_w + 2, label[:lbl_w], attr_msg)
        except curses.error:
            pass


# ══════════════════════════════════════════════════════════════════════════════
# Download helper
# ══════════════════════════════════════════════════════════════════════════════

def download_file(url: str, dest: Path, progress: ProgressBar):
    """Stream download with live progress updates."""
    if not HAS_REQUESTS:
        progress.done("requests not installed — use pip install requests")
        return False

    try:
        progress.update(f"Connecting...", 0.0)
        r = _requests.get(url, stream=True, timeout=30)
        r.raise_for_status()

        total = int(r.headers.get("content-length", 0))
        downloaded = 0
        dest.parent.mkdir(parents=True, exist_ok=True)

        with open(dest, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                if chunk:
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        pct = downloaded / total
                        mb  = downloaded / 1_048_576
                        progress.update(
                            f"Downloading {dest.name} ({mb:.1f} MB)", pct)
                    else:
                        mb = downloaded / 1_048_576
                        progress.update(f"Downloading {dest.name} ({mb:.1f} MB)")

        progress.done(f"Downloaded {dest.name}")
        return True

    except Exception as e:
        progress.done(f"Error: {e}")
        return False


# ══════════════════════════════════════════════════════════════════════════════
# Sync runner
# ══════════════════════════════════════════════════════════════════════════════

def run_sync(dry_run: bool, progress: ProgressBar, state: dict):
    progress.update("Running sync...", 0.1)
    cmd = [sys.executable, str(SYNC_SCRIPT), "--fork-dir", str(FORK_DIR)]
    if dry_run:
        cmd.append("--dry-run")

    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True,
            cwd=str(SCRIPT_DIR)
        )
        output = (result.stdout + result.stderr).splitlines()
        state["sync_output"] = output
        if result.returncode == 0:
            progress.done("Sync complete")
        else:
            progress.done("Sync failed — check output")
    except Exception as e:
        state["sync_output"] = [str(e)]
        progress.done(f"Error: {e}")


# ══════════════════════════════════════════════════════════════════════════════
# Main TUI
# ══════════════════════════════════════════════════════════════════════════════

class DevKit:
    def __init__(self, stdscr):
        self.scr      = stdscr
        self.progress = ProgressBar()
        self.state    = {}          # shared state between panes
        self.focus    = "nav"       # "nav" | "content"
        self.tree     = build_tree()
        self._flat: list[tuple[int, NavNode]] = []
        self.nav_idx  = 0
        self._rebuild_flat()

    # ── Init ──────────────────────────────────────────────────────────────────

    def _init_colors(self):
        curses.start_color()
        curses.use_default_colors()
        bg = -1
        curses.init_pair(C_NORMAL,   curses.COLOR_WHITE,   bg)
        curses.init_pair(C_SELECTED, curses.COLOR_BLACK,   curses.COLOR_CYAN)
        curses.init_pair(C_HEADER,   curses.COLOR_CYAN,    bg)
        curses.init_pair(C_BORDER,   curses.COLOR_BLUE,    bg)
        curses.init_pair(C_STATUS,   curses.COLOR_WHITE,   bg)
        curses.init_pair(C_PROGRESS, curses.COLOR_GREEN,   bg)
        curses.init_pair(C_KEY,      curses.COLOR_YELLOW,  bg)
        curses.init_pair(C_WARN,     curses.COLOR_YELLOW,  bg)
        curses.init_pair(C_OK,       curses.COLOR_GREEN,   bg)
        curses.init_pair(C_DIM,      curses.COLOR_WHITE,   bg)

    # ── Tree helpers ──────────────────────────────────────────────────────────

    def _rebuild_flat(self):
        self._flat = []
        for child in self.tree.children:
            self._flat.extend(child.flat(0))
        self.nav_idx = max(0, min(self.nav_idx, len(self._flat) - 1))

    @property
    def selected_node(self) -> NavNode:
        if not self._flat:
            return self.tree
        return self._flat[self.nav_idx][1]

    # ── Drawing ───────────────────────────────────────────────────────────────

    def _draw_border(self, win, title="", focus=False):
        h, w = win.getmaxyx()
        attr  = curses.color_pair(C_HEADER if focus else C_BORDER)
        try:
            win.border()
            if title:
                win.addstr(0, 2, f" {title} ", attr | curses.A_BOLD)
        except curses.error:
            pass

    def _draw_nav(self, win):
        h, w  = win.getmaxyx()
        focus = self.focus == "nav"
        self._draw_border(win, "Navigation", focus)

        visible_start = max(0, self.nav_idx - (h - 3))
        for row, (depth, node) in enumerate(self._flat):
            y = row - visible_start + 1
            if y < 1 or y >= h - 1:
                continue

            indent   = "  " * depth
            is_sel   = row == self.nav_idx
            has_kids = bool(node.children)
            marker   = ("▾ " if node.expanded else "▸ ") if has_kids else "  "
            label    = f"{indent}{marker}{node.label}"

            attr = curses.color_pair(C_SELECTED) if is_sel else \
                   curses.color_pair(C_NORMAL)
            if is_sel and focus:
                attr |= curses.A_BOLD

            try:
                win.addstr(y, 1, label[:w - 2].ljust(w - 2), attr)
            except curses.error:
                pass

    def _draw_content(self, win):
        focus = self.focus == "content"
        node  = self.selected_node
        win.erase()
        self._draw_border(win, node.label.strip(), focus)

        key = node.key
        if key == "sync":
            render_sync(win, self.state)
        elif key == "devices":
            render_devices_overview(win, self.state)
        elif key.startswith("device:"):
            render_device(win, key.split(":", 1)[1], self.state)
        elif key == "build":
            render_build(win, self.state)
        elif key == "about":
            render_about(win, self.state)

    def _draw_status(self, win):
        h, w = win.getmaxyx()
        win.erase()
        try:
            win.border()
            self.progress.render(win, 1, 1, w - 2)
            hint = " Tab:switch pane  ↑↓:navigate  Enter:select  q:quit  r:refresh "
            win.addstr(0, max(2, w - len(hint) - 2), hint,
                       curses.color_pair(C_DIM))
        except curses.error:
            pass

    def _make_wins(self):
        sh, sw        = self.scr.getmaxyx()
        status_h      = 3
        main_h        = sh - status_h
        content_w     = max(1, sw - NAV_WIDTH)
        self._sh, self._sw = sh, sw
        self._nav_win     = curses.newwin(main_h,   NAV_WIDTH, 0,      0)
        self._content_win = curses.newwin(main_h,   content_w, 0,      NAV_WIDTH)
        self._status_win  = curses.newwin(status_h, sw,        main_h, 0)

    def draw(self):
        sh, sw = self.scr.getmaxyx()
        if not hasattr(self, "_sh") or (sh, sw) != (self._sh, self._sw):
            self._make_wins()

        self._draw_nav(self._nav_win)
        self._draw_content(self._content_win)
        self._draw_status(self._status_win)

        self._nav_win.noutrefresh()
        self._content_win.noutrefresh()
        self._status_win.noutrefresh()
        curses.doupdate()

    # ── Input ─────────────────────────────────────────────────────────────────

    def handle_key(self, key):
        node = self.selected_node

        if key in (ord('q'), ord('Q')):
            return False

        elif key == ord('\t'):
            self.focus = "content" if self.focus == "nav" else "nav"

        elif key == ord('r'):
            self.tree = build_tree()
            self._rebuild_flat()

        elif self.focus == "nav":
            if key == curses.KEY_UP:
                self.nav_idx = max(0, self.nav_idx - 1)
            elif key == curses.KEY_DOWN:
                self.nav_idx = min(len(self._flat) - 1, self.nav_idx + 1)
            elif key in (curses.KEY_ENTER, ord('\n'), ord('\r')):
                if node.children:
                    node.expanded = not node.expanded
                    self._rebuild_flat()
                else:
                    self.focus = "content"

        elif self.focus == "content":
            key_chr = chr(key) if 32 <= key < 127 else ""
            self.state["content_focus_active"] = True

            if node.key == "sync":
                if key_chr in ("s", "S"):
                    t = threading.Thread(
                        target=run_sync,
                        args=(False, self.progress, self.state),
                        daemon=True)
                    t.start()
                elif key_chr in ("d", "D"):
                    t = threading.Thread(
                        target=run_sync,
                        args=(True, self.progress, self.state),
                        daemon=True)
                    t.start()

            elif node.key.startswith("device:"):
                codename = node.key.split(":", 1)[1]
                akey     = f"device_action:{codename}"
                actions  = self.state.get(f"device_actions:{codename}", [])
                n_acts   = len(actions)

                if key == curses.KEY_UP:
                    self.state[akey] = (self.state.get(akey, 0) - 1) % max(1, n_acts)
                elif key == curses.KEY_DOWN:
                    self.state[akey] = (self.state.get(akey, 0) + 1) % max(1, n_acts)
                elif key in (curses.KEY_ENTER, ord("\n"), ord("\r")):
                    idx    = self.state.get(akey, 0)
                    action = actions[idx][0] if actions else None
                    if action == "build":
                        self.progress.update(f"Building {codename}...", 0.1)
                        t = threading.Thread(
                            target=self._run_build,
                            args=(codename,),
                            daemon=True)
                        t.start()
                    elif action == "edit":
                        editor = os.environ.get("EDITOR", "nano")
                        conf   = str(DEVICES_DIR / codename / "device.conf")
                        curses.endwin()
                        subprocess.run([editor, conf])
                        self._make_wins()

        return True

    # ── Actions ───────────────────────────────────────────────────────────────

    def _run_build(self, codename: str):
        build_sh = FORK_DIR / "build.sh"
        if not build_sh.exists():
            self.progress.done("build.sh not found in Mobuntu/")
            return
        cmd = ["sudo", "bash", str(build_sh), "-d", codename]
        self.progress.update(f"Running build for {codename}...", 0.2)
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, cwd=str(FORK_DIR))
            output = (result.stdout + result.stderr).splitlines()
            self.state["sync_output"] = output
            if result.returncode == 0:
                self.progress.done(f"Build complete: {codename}")
            else:
                self.progress.done(f"Build failed — check sync pane output")
        except Exception as e:
            self.progress.done(f"Error: {e}")

    # ── Main loop ─────────────────────────────────────────────────────────────

    def run(self):
        self._init_colors()
        curses.curs_set(0)
        self.scr.nodelay(True)
        self.scr.timeout(100)

        self.progress.update("Mobuntu DevKit ready", 0.0)
        self.progress.active = False

        running = True
        while running:
            try:
                self.draw()
                key = self.scr.getch()
                if key != -1:
                    running = self.handle_key(key)
            except curses.error:
                pass
            except KeyboardInterrupt:
                break


# ══════════════════════════════════════════════════════════════════════════════
# Entry point
# ══════════════════════════════════════════════════════════════════════════════

def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--download":
        # Headless download mode: python3 devkit.py --download <url> <dest>
        if not HAS_REQUESTS:
            print("pip install requests required for downloads")
            sys.exit(1)
        url  = sys.argv[2]
        dest = Path(sys.argv[3])

        class _StdoutProgress:
            def update(self, msg, val=None):
                pct = f"{int((val or 0)*100):3d}%" if val is not None else "   "
                print(f"\r{pct} {msg}", end="", flush=True)
            def done(self, msg):
                print(f"\r100% {msg}")

        download_file(url, dest, _StdoutProgress())
        return

    curses.wrapper(lambda s: DevKit(s).run())


if __name__ == "__main__":
    main()
