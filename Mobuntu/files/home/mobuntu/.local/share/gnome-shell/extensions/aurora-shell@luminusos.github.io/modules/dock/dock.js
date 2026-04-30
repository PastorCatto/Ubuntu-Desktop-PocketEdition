// src/modules/dock/dock.ts
import St from "gi://St";
import GLib from "gi://GLib";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { Module } from "../../module.js";
import { AuroraDash } from "../../shared/ui/dash.js";
import { DockHotArea } from "./hotArea.js";
import { DockIntellihide, OverlapStatus } from "./intellihide.js";

var HOT_AREA_REVEAL_DURATION = 1500;
var HOT_AREA_STRIP_HEIGHT = 1;
var Dock = class extends Module {
  _bindings = /* @__PURE__ */ new Map();
  _pendingRebuild = false;

  enable() {
    Main.overview.dash.hide();
    this._rebuildBindings();
    Main.layoutManager.connectObject(
      "monitors-changed",
      () => this._rebuildBindings(),
      "hot-corners-changed",
      () => this._rebuildBindings(),
      this,
    );
    global.display.connectObject(
      "workareas-changed",
      () => this._refreshWorkAreas(),
      this,
    );
    Main.sessionMode.connectObject(
      "updated",
      () => this._refreshBindingsLayout(),
      this,
    );
    Main.overview.connectObject(
      "showing",
      () => this._setOverviewVisible(true),
      "hidden",
      () => this._setOverviewVisible(false),
      this,
    );
  }

  disable() {
    Main.overview.dash.show();
    Main.layoutManager.disconnectObject(this);
    global.display.disconnectObject(this);
    Main.sessionMode.disconnectObject(this);
    Main.overview.disconnectObject(this);
    this._pendingRebuild = false;
    this._clearBindings();
  }

  _rebuildBindings() {
    if (Main.overview.visible) {
      this._pendingRebuild = true;
      return;
    }
    this._pendingRebuild = false;
    this._clearBindings();
    const monitors = Main.layoutManager.monitors ?? [];
    monitors.forEach((monitor, index) => {
      if (this._hasDefinedBottom(monitors, index)) {
        const binding = this._createBinding(monitor, index);
        if (binding) this._bindings.set(index, binding);
      }
    });
    this._refreshWorkAreas();
  }

  _createBinding(monitor, monitorIndex) {
    const container = new St.Bin({
      name: `aurora-dock-container-${monitorIndex}`,
      reactive: false,
      visible: false,
    });
    Main.layoutManager.addChrome(container, {
      trackFullscreen: true,
      affectsStruts: false,
    });
    const dash = new AuroraDash({ monitorIndex });
    container.set_child(dash);
    dash.attachToContainer(container);
    const intellihide = new DockIntellihide(monitorIndex);
    dash.setTargetBoxListener((box) => intellihide.updateTargetBox(box));
    const binding = {
      monitorIndex,
      container,
      dash,
      intellihide,
      hotArea: null,
      autoHideReleaseId: 0,
      hotAreaActive: false,
    };
    binding.hotArea = this._createHotArea(binding, monitor);
    intellihide.connectObject(
      "status-changed",
      () => {
        if (binding.hotAreaActive) return;
        if (intellihide.status === OverlapStatus.CLEAR) {
          this._clearHotAreaReveal(binding);
          dash.blockAutoHide(true);
          dash.show(true);
        } else if (intellihide.status === OverlapStatus.BLOCKED) {
          dash.blockAutoHide(false);
        }
      },
      this,
    );
    return binding;
  }

  _createHotArea(binding, monitor) {
    if (monitor.width <= 0 || monitor.height <= 0) return null;
    const hotArea = new DockHotArea(monitor);
    Main.layoutManager.addChrome(hotArea, {
      trackFullscreen: true,
      affectsStruts: false,
    });
    hotArea.set_size(monitor.width, HOT_AREA_STRIP_HEIGHT);
    hotArea.set_position(
      monitor.x,
      monitor.y + monitor.height - HOT_AREA_STRIP_HEIGHT,
    );
    hotArea.connectObject(
      "triggered",
      () => this._revealDockFromHotArea(binding),
      this,
    );
    return hotArea;
  }

  _refreshWorkAreas() {
    this._bindings.forEach((b) => this._updateWorkArea(b));
  }

  _refreshBindingsLayout() {
    this._bindings.forEach((b) => {
      b.dash.refresh();
      this._updateWorkArea(b);
    });
  }

  _updateWorkArea(binding) {
    const workArea = Main.layoutManager.getWorkAreaForMonitor(
      binding.monitorIndex,
    );
    if (!workArea) {
      binding.dash.hide(false);
      return;
    }
    const bounds = {
      x: workArea.x,
      y: workArea.y,
      width: workArea.width,
      height: workArea.height,
    };
    binding.dash.refresh();
    binding.dash.applyWorkArea(bounds);
    binding.container.show();
    if (binding.hotArea) {
      binding.hotArea.set_size(bounds.width, HOT_AREA_STRIP_HEIGHT);
      binding.hotArea.set_position(
        bounds.x,
        bounds.y + bounds.height - HOT_AREA_STRIP_HEIGHT,
      );
      binding.hotArea.setGeometry(bounds);
    }
  }

  _clearBindings() {
    this._bindings.forEach((b) => this._destroyBinding(b));
    this._bindings.clear();
  }

  _destroyBinding(binding) {
    if (binding.autoHideReleaseId) {
      GLib.source_remove(binding.autoHideReleaseId);
      binding.autoHideReleaseId = 0;
    }
    binding.intellihide.disconnectObject?.(this);
    binding.hotArea?.disconnectObject?.(this);
    if (binding.hotArea) {
      Main.layoutManager.removeChrome?.(binding.hotArea);
      binding.hotArea.destroy();
      binding.hotArea = null;
    }
    binding.intellihide.destroy();
    binding.dash.detachFromContainer();
    binding.dash.destroy();
    Main.layoutManager.removeChrome?.(binding.container);
    binding.container.destroy();
  }

  /**
   * Returns true if no other monitor sits directly below this one.
   * Used to avoid placing a dock between vertically stacked monitors.
   */
  _hasDefinedBottom(monitors, index) {
    const monitor = monitors[index];
    if (!monitor) return false;
    const bottom = monitor.y + monitor.height;
    const left = monitor.x;
    const right = left + monitor.width;
    return !monitors.some((other, i) => {
      if (i === index) return false;
      return (
        other.y >= bottom && other.x < right && other.x + other.width > left
      );
    });
  }

  _revealDockFromHotArea(binding) {
    this._clearHotAreaReveal(binding);
    binding.hotAreaActive = true;
    binding.dash.blockAutoHide(true);
    binding.dash.show(true);
    binding.autoHideReleaseId = GLib.timeout_add(
      GLib.PRIORITY_DEFAULT,
      HOT_AREA_REVEAL_DURATION,
      () => {
        const dashBounds = binding.dash.targetBox;
        if (dashBounds) {
          const [cursorX, cursorY] = global.get_pointer();
          if (
            cursorY >= dashBounds.y &&
            cursorX >= dashBounds.x &&
            cursorX <= dashBounds.x + dashBounds.width
          ) {
            return GLib.SOURCE_CONTINUE;
          }
        }
        binding.autoHideReleaseId = 0;
        binding.hotAreaActive = false;
        if (binding.intellihide.status === OverlapStatus.CLEAR) {
          binding.dash.blockAutoHide(true);
          binding.dash.show(true);
        } else {
          binding.dash.blockAutoHide(false);
          binding.dash.ensureAutoHide();
        }
        return GLib.SOURCE_REMOVE;
      },
    );
  }

  _clearHotAreaReveal(binding) {
    if (binding.autoHideReleaseId) {
      GLib.source_remove(binding.autoHideReleaseId);
      binding.autoHideReleaseId = 0;
    }
  }

  _setOverviewVisible(overviewShowing) {
    if (!overviewShowing && this._pendingRebuild) {
      this._rebuildBindings();
      return;
    }
    this._bindings.forEach((binding) => {
      if (overviewShowing) {
        this._clearHotAreaReveal(binding);
        binding.hotAreaActive = false;
        binding.dash.blockAutoHide(false);
        binding.dash.hide(false);
        binding.container.hide();
      } else {
        this._updateWorkArea(binding);
        binding.intellihide.emit("status-changed");
      }
    });
  }
};

export { Dock };
