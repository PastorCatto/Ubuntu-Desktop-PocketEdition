// src/modules/dock/hotArea.ts
import St from "gi://St";
import Clutter from "gi://Clutter";
import GLib from "gi://GLib";
import Meta from "gi://Meta";
import Shell from "gi://Shell";
import GObject from "gi://GObject";
import * as Layout from "resource:///org/gnome/shell/ui/layout.js";

var HOT_AREA_TRIGGER_SPEED = 150;
var HOT_AREA_TRIGGER_TIMEOUT = 550;
var HOT_AREA_DEBOUNCE_TIMEOUT = 250;
var DockHotArea = GObject.registerClass(
  {
    Signals: { triggered: {} },
  },
  class DockHotArea2 extends St.Widget {
    _pressureBarrier = null;
    _horizontalBarrier = null;
    _monitor;
    _triggerAllowed = true;
    _pointerDwellTimeoutId = 0;

    _init(monitor) {
      super._init({
        reactive: true,
        visible: true,
        name: "aurora-dock-hot-area",
      });
      this._monitor = monitor;
      this._pressureBarrier = new Layout.PressureBarrier(
        HOT_AREA_TRIGGER_SPEED,
        HOT_AREA_TRIGGER_TIMEOUT,
        Shell.ActionMode.ALL,
      );
      this._pressureBarrier.connectObject(
        "trigger",
        () => {
          if (this._triggerAllowed) this.emit("triggered");
        },
        this,
      );
      this.connectObject(
        "enter-event",
        () => {
          if (this._triggerAllowed) {
            this._clearDebounceTimer();
            this._pointerDwellTimeoutId = GLib.timeout_add(
              GLib.PRIORITY_DEFAULT,
              HOT_AREA_DEBOUNCE_TIMEOUT,
              () => {
                this.emit("triggered");
                this._pointerDwellTimeoutId = 0;
                return GLib.SOURCE_REMOVE;
              },
            );
          }
          return Clutter.EVENT_PROPAGATE;
        },
        this,
      );
      this.connectObject(
        "leave-event",
        () => {
          if (this._pointerDwellTimeoutId) {
            GLib.source_remove(this._pointerDwellTimeoutId);
            this._pointerDwellTimeoutId = 0;
          }
          return Clutter.EVENT_PROPAGATE;
        },
        this,
      );
      global.display.connectObject(
        "grab-op-begin",
        (_d, _w, op) => {
          if (op === Meta.GrabOp.MOVING) this._triggerAllowed = false;
        },
        "grab-op-end",
        (_d, _w, op) => {
          if (op === Meta.GrabOp.MOVING) this._triggerAllowed = true;
        },
        this,
      );
    }

    setGeometry(monitor) {
      this._monitor = monitor;
      this._rebuildBarrier(monitor.width);
    }

    destroy() {
      global.display.disconnectObject(this);
      this._destroyBarrier();
      this._clearDebounceTimer();
      this._pressureBarrier?.disconnectObject?.(this);
      this._pressureBarrier?.destroy?.();
      this._pressureBarrier = null;
      super.destroy();
    }

    _rebuildBarrier(size) {
      if (!this._pressureBarrier) return;
      this._destroyBarrier();
      const width = Number.isFinite(size) ? size : 0;
      const left = this._monitor.x;
      const bottom = this._monitor.y + this._monitor.height;
      if (width <= 0 || !Number.isFinite(left) || !Number.isFinite(bottom))
        return;
      this._horizontalBarrier = new Meta.Barrier({
        backend: global.backend,
        x1: left,
        x2: left + width,
        y1: bottom,
        y2: bottom,
        directions: Meta.BarrierDirection.POSITIVE_Y,
      });
      this._pressureBarrier.addBarrier(this._horizontalBarrier);
    }

    _destroyBarrier() {
      if (!this._horizontalBarrier) return;
      this._pressureBarrier?.removeBarrier(this._horizontalBarrier);
      this._horizontalBarrier.destroy();
      this._horizontalBarrier = null;
    }

    _clearDebounceTimer() {
      if (this._pointerDwellTimeoutId) {
        GLib.source_remove(this._pointerDwellTimeoutId);
        this._pointerDwellTimeoutId = 0;
      }
    }
  },
);

export { DockHotArea };
