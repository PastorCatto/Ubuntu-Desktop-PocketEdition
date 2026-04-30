// src/modules/dock/intellihide.ts
import GObject from "gi://GObject";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import * as Main from "resource:///org/gnome/shell/ui/main.js";

var OVERLAP_WINDOW_TYPES = [
  Meta.WindowType.NORMAL,
  Meta.WindowType.DOCK,
  Meta.WindowType.DIALOG,
  Meta.WindowType.MODAL_DIALOG,
  Meta.WindowType.TOOLBAR,
  Meta.WindowType.MENU,
  Meta.WindowType.UTILITY,
  Meta.WindowType.SPLASHSCREEN,
];

var OverlapStatus = /* @__PURE__ */ ((OverlapStatus2) => {
  OverlapStatus2[(OverlapStatus2["CLEAR"] = 0)] = "CLEAR";
  OverlapStatus2[(OverlapStatus2["BLOCKED"] = 1)] = "BLOCKED";
  return OverlapStatus2;
})(OverlapStatus || {});

var DockIntellihide = GObject.registerClass(
  {
    Signals: { "status-changed": {} },
  },
  class DockIntellihide2 extends GObject.Object {
    _targetBox = null;
    _status = 0 /* CLEAR */;
    _focusActor = null;

    _init(monitorIndex) {
      super._init();
      this._monitorIndex = monitorIndex;
      this._tracker = Shell.WindowTracker.get_default() ?? null;
      global.display.connectObject(
        "window-entered-monitor",
        () => this._checkOverlap(),
        "window-left-monitor",
        () => this._checkOverlap(),
        "restacked",
        () => this._checkOverlap(),
        "notify::focus-window",
        () => this._checkOverlap(),
        this,
      );
      Main.layoutManager.connectObject(
        "monitors-changed",
        () => this._checkOverlap(),
        this,
      );
      this._tracker?.connectObject(
        "notify::focus-app",
        () => this._checkOverlap(),
        this,
      );
      Main.keyboard.connectObject(
        "visibility-changed",
        () => this._onKeyboardVisibilityChanged(),
        this,
      );
      Main.overview.connectObject(
        "showing",
        () => this._applyOverlap(false, true),
        "hidden",
        () => this._checkOverlap(),
        this,
      );
    }

    get status() {
      return this._status;
    }

    updateTargetBox(box) {
      this._targetBox = box;
      this._checkOverlap();
    }

    destroy() {
      this._disconnectFocusActor();
      global.display.disconnectObject(this);
      Main.layoutManager.disconnectObject(this);
      this._tracker?.disconnectObject(this);
      this._tracker = null;
      Main.keyboard.disconnectObject(this);
      Main.overview.disconnectObject(this);
      this.disconnectObject?.(this);
    }

    _checkOverlap() {
      if (Main.overview.visible) {
        this._applyOverlap(false, true);
        return;
      }
      if (!this._targetBox) return;
      this._disconnectFocusActor();
      const focusApp = this._tracker?.focus_app;
      if (!focusApp) {
        this._checkRemainingWindows();
        return;
      }
      let focusWin = focusApp
        .get_windows()
        .find((w) => this._isCandidateWindow(w));
      if (focusWin && this._monitorIndex === Main.layoutManager.primaryIndex) {
        const activeWs = global.workspace_manager.get_active_workspace();
        if (focusWin.get_workspace() !== activeWs) focusWin = null;
      }
      if (!focusWin) {
        this._checkRemainingWindows();
        return;
      }
      this._applyOverlap(this._doesOverlap(focusWin.get_frame_rect()), true);
      this._focusActor = focusWin.get_compositor_private();
      if (this._focusActor) {
        this._focusActor.connectObject(
          "notify::allocation",
          () => {
            this._applyOverlap(this._doesOverlap(focusWin.get_frame_rect()));
          },
          this,
        );
      }
    }

    _checkRemainingWindows() {
      const windows = global
        .get_window_actors()
        .map((actor) => actor.meta_window)
        .filter((win) => this._isCandidateWindow(win));
      const overlap = windows.some((win) =>
        this._doesOverlap(win.get_frame_rect()),
      );
      this._applyOverlap(overlap, windows.length === 0);
    }

    _isCandidateWindow(win) {
      if (!win || win.get_monitor() !== this._monitorIndex) return false;
      if (win.minimized || !win.showing_on_its_workspace()) return false;
      if (this._monitorIndex === Main.layoutManager.primaryIndex) {
        if (
          win.get_workspace() !==
          global.workspace_manager.get_active_workspace()
        )
          return false;
      }
      return OVERLAP_WINDOW_TYPES.includes(win.get_window_type());
    }

    /** AABB overlap test between a window rectangle and the dock's target box. */
    _doesOverlap(rectangle) {
      const target = this._targetBox;
      if (!target) {
        return false;
      }
      const isToTheLeft = rectangle.x + rectangle.width < target.x;
      const isToTheRight = target.x + target.width < rectangle.x;
      const isAbove = rectangle.y + rectangle.height < target.y;
      const isBelow = target.y + target.height < rectangle.y;
      return !(isToTheLeft || isToTheRight || isAbove || isBelow);
    }

    _applyOverlap(overlap, force = false) {
      const newStatus = overlap ? 1 /* BLOCKED */ : 0; /* CLEAR */
      if (!force && newStatus === this._status) return;
      this._status = newStatus;
      this.emit("status-changed");
    }

    _disconnectFocusActor() {
      if (this._focusActor) {
        this._focusActor.disconnectObject(this);
        this._focusActor = null;
      }
    }

    _onKeyboardVisibilityChanged() {
      this._applyOverlap(Main.keyboard.visible, true);
      if (!Main.keyboard.visible) this._checkOverlap();
    }
  },
);

export { DockIntellihide, OverlapStatus };
