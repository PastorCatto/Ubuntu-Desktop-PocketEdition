// src/shared/ui/dash.ts
import GLib from "gi://GLib";
import Clutter from "gi://Clutter";
import GObject from "gi://GObject";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import * as DND from "resource:///org/gnome/shell/ui/dnd.js";
import { Dash } from "resource:///org/gnome/shell/ui/dash.js";

var TARGET_BOX_PADDING = 8;
var AUTOHIDE_TIMEOUT = 100;
var ANIMATION_TIME = 200;
var VISIBILITY_ANIMATION_TIME = 200;
var HIDE_SCALE = 0.98;
var EASE_DURATION_FACTOR = 0.8;
var AuroraDash = GObject.registerClass(
  class AuroraDash2 extends Dash {
    _workArea = null;
    _container = null;
    _autohideTimeoutId = 0;
    _delayEnsureAutoHideId = 0;
    _blockAutoHideDelayId = 0;
    _workAreaUpdateId = 0;
    _targetBox = null;
    _blockAutoHide = false;
    _draggingItem = false;
    _isDestroyed = false;
    _targetBoxListener = null;
    _pendingShow = null;
    _cycleState = null;

    _init(params = {}) {
      super._init();
      this._monitorIndex =
        params.monitorIndex ?? Main.layoutManager.primaryIndex;
      const button = this.showAppsButton;
      button?.set_toggle_mode?.(false);
      button?.connectObject?.("clicked", () => Main.overview.showApps(), this);
      Main.overview.connectObject(
        "item-drag-begin",
        () => {
          this._draggingItem = true;
          this._onHover();
        },
        "item-drag-end",
        () => {
          this._draggingItem = false;
          this._onHover();
        },
        this,
      );
      const dashContainer = this._dashContainer;
      dashContainer?.set_track_hover?.(true);
      dashContainer?.set_reactive?.(true);
      dashContainer?.connectObject?.(
        "notify::hover",
        this._onHover.bind(this),
        this,
      );
      this.set_x_align?.(Clutter.ActorAlign.CENTER);
      this.set_y_align?.(Clutter.ActorAlign.END);
      this.set_x_expand?.(false);
      this.set_y_expand?.(false);
      this.connectObject?.(
        "notify::allocation",
        () => this._queueTargetBoxUpdate(),
        this,
      );
      global.display.connectObject(
        "window-entered-monitor",
        () => this._queueRedisplay(),
        "window-left-monitor",
        () => this._queueRedisplay(),
        this,
      );
      global.workspace_manager.connectObject(
        "active-workspace-changed",
        () => this._queueRedisplay(),
        this,
      );
    }

    get monitorIndex() {
      return this._monitorIndex;
    }

    set monitorIndex(index) {
      if (this._monitorIndex === index) return;
      this._monitorIndex = index;
      this._workArea = null;
    }

    get targetBox() {
      return this._targetBox;
    }

    destroy() {
      this._isDestroyed = true;
      this._clearAllTimeouts();
      const dragMonitor = this._dragMonitor;
      if (dragMonitor) DND.removeDragMonitor(dragMonitor);
      this.showAppsButton?.disconnectObject?.(this);
      this.disconnectObject?.(this);
      Main.overview.disconnectObject(this);
      global.display.disconnectObject(this);
      global.workspace_manager.disconnectObject(this);
      this._dashContainer?.disconnectObject?.(this);
      this._container?.disconnectObject?.(this);
      this._container = null;
      this._targetBox = null;
      this._pendingShow = null;
      this._cycleState = null;
      super.destroy();
    }

    _queueRedisplay() {
      if (this._isDestroyed) return;
      super._queueRedisplay();
    }

    /** Force the dash to re-render its icon list. */
    refresh() {
      this._redisplay();
    }

    setTargetBoxListener(listener) {
      this._targetBoxListener = listener;
      listener?.(this._targetBox);
    }

    attachToContainer(container) {
      if (this._container === container) return;
      this._container?.disconnectObject?.(this);
      this._container = container;
      container.connectObject?.(
        "notify::allocation",
        () => this._queueTargetBoxUpdate(),
        "destroy",
        () => {
          if (this._container === container) this._container = null;
        },
        this,
      );
      this._queueTargetBoxUpdate();
    }

    detachFromContainer() {
      this._container?.disconnectObject?.(this);
      this._container = null;
      this._targetBox = null;
      this._targetBoxListener?.(null);
      this._pendingShow = null;
    }

    applyWorkArea(workArea) {
      this._workArea = workArea;
      if (!this._container) return;
      const [, prefW] = this.get_preferred_width(workArea.width);
      const width = Math.min(Math.max(prefW, 0), workArea.width);
      const [, prefH] = this.get_preferred_height(width || workArea.width);
      const height = Math.min(Math.max(prefH, 0), workArea.height);
      const marginBottom = this._getMarginBottom();
      const x = workArea.x + Math.round((workArea.width - width) / 2);
      const y = Math.max(
        workArea.y,
        workArea.y + workArea.height - height - marginBottom,
      );
      this._container.set_size(width, height);
      this._container.set_position(x, y);
      this._queueTargetBoxUpdate();
    }

    blockAutoHide(block) {
      this._blockAutoHide = block;
      if (block && !Main.overview.visible) {
        this.show(true);
      } else if (!block) {
        this._ensureHoverState();
      }
      this._onHover();
    }

    /** Schedule a delayed hover re-evaluation after visibility changes. */
    ensureAutoHide() {
      this._clearTimeout("_delayEnsureAutoHideId");
      this._delayEnsureAutoHideId = GLib.timeout_add(
        GLib.PRIORITY_DEFAULT,
        VISIBILITY_ANIMATION_TIME,
        () => {
          this._onHover();
          this._delayEnsureAutoHideId = 0;
          return GLib.SOURCE_REMOVE;
        },
      );
    }

    show(animate = true, onComplete) {
      if (!this._hasValidAllocation()) {
        this._pendingShow = { animate, onComplete };
        return;
      }
      this._pendingShow = null;
      this._performShow(animate, onComplete);
    }

    hide(animate = true) {
      if (this._isFullyHidden()) return;
      this.remove_all_transitions();
      this.set_pivot_point(0.5, 1);
      if (!animate) {
        this._applyHiddenState();
        super.hide();
        return;
      }
      this.ease({
        opacity: 0,
        scale_x: HIDE_SCALE,
        scale_y: HIDE_SCALE,
        duration: VISIBILITY_ANIMATION_TIME * EASE_DURATION_FACTOR,
        mode: Clutter.AnimationMode.EASE_OUT_CUBIC,
        onComplete: () => super.hide(),
      });
      this.ease_property("translation-y", this.height, {
        duration: VISIBILITY_ANIMATION_TIME,
        mode: Clutter.AnimationMode.LINEAR,
      });
    }

    _isMenuOpen() {
      const dashAny = this;
      const children = dashAny._box?.get_children?.() ?? [];
      for (const child of children) {
        const appIcon = child.child?._delegate;
        if (appIcon?._menu?.isOpen) {
          return true;
        }
      }
      const showApps =
        dashAny.showAppsButton || dashAny._showAppsIcon?._delegate;
      if (showApps?._menu?.isOpen) {
        return true;
      }
      return false;
    }

    _performShow(animate = true, onComplete) {
      if (this._isFullyShown()) {
        onComplete?.();
        return;
      }
      if (this._workArea) {
        this.applyWorkArea(this._workArea);
      }
      this.remove_all_transitions();
      this.set_pivot_point(0.5, 1);
      if (!animate) {
        this._applyShownState();
        super.show();
        onComplete?.();
        return;
      }
      this._applyHiddenState();
      super.show();
      this.ease({
        opacity: 255,
        scale_x: 1,
        scale_y: 1,
        duration: VISIBILITY_ANIMATION_TIME,
        mode: Clutter.AnimationMode.EASE_IN_CUBIC,
        onComplete,
      });
      this.ease_property("translation-y", 0, {
        duration: VISIBILITY_ANIMATION_TIME * EASE_DURATION_FACTOR,
        mode: Clutter.AnimationMode.LINEAR,
      });
    }

    /** Set transform properties to the fully-visible resting state. */
    _applyShownState() {
      this.translation_y = 0;
      this.opacity = 255;
      this.set_scale(1, 1);
    }

    /** Set transform properties to the fully-hidden state. */
    _applyHiddenState() {
      this.translation_y = this.height;
      this.opacity = 0;
      this.set_scale(HIDE_SCALE, HIDE_SCALE);
    }

    /**
     * Guard wrappers for parent Dash signal handlers that fire during DnD in the
     * overview workspace view. If GNOME Shell 50's Dash.destroy() fails to
     * disconnect a signal, the bound handler still reaches here via the prototype
     * chain. Returning early prevents any GObject property access on the already-
     * disposed object (JS-object properties such as _isDestroyed remain readable
     * after GObject disposal).
     */
    _onDragBegin() {
      if (this._isDestroyed) return;
      Dash.prototype._onDragBegin?.call(this);
    }

    _onDragEnd() {
      if (this._isDestroyed) return;
      Dash.prototype._onDragEnd?.call(this);
    }

    _onDragMotion(...args) {
      if (this._isDestroyed) return;
      return Dash.prototype._onDragMotion?.call(this, ...args);
    }

    _onDragLeave() {
      if (this._isDestroyed) return;
      Dash.prototype._onDragLeave?.call(this);
    }

    // GNOME 50 added window-drag signals forwarded from the workspace view.
    _onWindowDragBegin(...args) {
      if (this._isDestroyed) return;
      Dash.prototype._onWindowDragBegin?.call(this, ...args);
    }

    _onWindowDragEnd(...args) {
      if (this._isDestroyed) return;
      Dash.prototype._onWindowDragEnd?.call(this, ...args);
    }

    /**
     * Override Dash._redisplay to resize the container after icon list changes.
     * If iconSize changed, animate icons to the new size (applyWorkArea runs
     * after animation). Otherwise, re-apply the work area immediately so the
     * container grows/shrinks to fit added or removed icons.
     */
    _redisplay() {
      if (this._isDestroyed) return;
      const dashAny = this;
      const oldIconSize = dashAny.iconSize;
      const appSystem = dashAny._appSystem;
      const origGetRunning = appSystem?.get_running;
      if (appSystem && origGetRunning) {
        const isRelevant = (w) => this._isWindowRelevant(w);
        appSystem.get_running = function () {
          return origGetRunning
            .call(this)
            .filter((app) => app.get_windows().some(isRelevant));
        };
      }
      Dash.prototype._redisplay.call(this);
      if (appSystem && origGetRunning) {
        appSystem.get_running = origGetRunning;
      }
      this._updatePerMonitorRunningDots();
      this._overrideIconActivation();
      if (dashAny.iconSize !== oldIconSize) {
        this._animateIconResize();
      } else if (this._workArea) {
        this._queueWorkAreaUpdate();
      }
    }

    /**
     * Check whether a window belongs to this dock's monitor and the active
     * workspace. Windows stuck to all workspaces are always considered relevant.
     */
    _isWindowRelevant(w) {
      return (
        w.get_monitor() === this._monitorIndex &&
        (w.is_on_all_workspaces?.() ||
          w.get_workspace() === global.workspace_manager.get_active_workspace())
      );
    }

    /**
     * Show the running-indicator dot only for apps that have at least one
     * window on this dash's monitor and active workspace. This ensures
     * favorites pinned across all docks only display activity where the
     * app is actually open.
     */
    _updatePerMonitorRunningDots() {
      const children = this._box?.get_children?.() ?? [];
      for (const child of children) {
        const icon = child.child?._delegate;
        if (!icon?.app) continue;
        const hasWindowHere = icon.app
          .get_windows()
          .some((w) => this._isWindowRelevant(w));
        const dot = icon._dot;
        if (dot) {
          dot.visible = hasWindowHere;
        }
      }
    }

    /**
     * Override app icon activation so clicking an app with multiple windows
     * on this monitor and active workspace cycles through them in MRU
     * (Most Recently Used) order. A snapshot of the MRU list is taken on the
     * first click and reused for subsequent clicks so the order stays stable
     * while cycling. The snapshot resets automatically when the focused
     * window no longer matches the last cycled-to window (e.g. the user
     * clicked a window directly or switched apps).
     */
    _overrideIconActivation() {
      const children = this._box?.get_children?.() ?? [];
      for (const child of children) {
        const appIcon = child.child?._delegate;
        if (!appIcon?.app || appIcon._auroraActivatePatched) continue;
        appIcon._auroraActivatePatched = true;
        const originalActivate = appIcon.activate.bind(appIcon);
        const isRelevant = (w) => this._isWindowRelevant(w);
        appIcon.activate = function (button) {
          const event = Clutter.get_current_event();
          const modifiers = event ? event.get_state() : 0;
          const isMiddleButton = button && button === Clutter.BUTTON_MIDDLE;
          const isCtrlPressed =
            (modifiers & Clutter.ModifierType.CONTROL_MASK) !== 0;
          if (isCtrlPressed || isMiddleButton) {
            this._cycleState = null;

            originalActivate(button);
            return;
          }
          const windows = appIcon.app.get_windows().filter(isRelevant);
          if (windows.length <= 1) {
            this._cycleState = null;

            originalActivate(button);
            return;
          }
          const focusedWindow = global.display.focus_window;
          const isFocused = windows.some((w) => w === focusedWindow);
          const appId = appIcon.app.get_id();
          if (!isFocused) {
            this._cycleState = null;
            const win = windows[0];
            if (win.minimized) win.unminimize();
            Main.activateWindow(win);
            return;
          }
          if (
            this._cycleState?.appId === appId &&
            this._cycleState.windows[this._cycleState.index] === focusedWindow
          ) {
            const nextIndex =
              (this._cycleState.index + 1) % this._cycleState.windows.length;
            const next2 = this._cycleState.windows[nextIndex];
            if (windows.some((w) => w === next2)) {
              this._cycleState.index = nextIndex;
              if (next2.minimized) next2.unminimize();
              Main.activateWindow(next2);
              return;
            }
          }
          this._cycleState = { appId, windows: [...windows], index: 1 };
          const next = windows[1];
          if (next.minimized) next.unminimize();
          Main.activateWindow(next);
        };
      }
    }

    /**
     * Animate all dock icons to the current icon size after a size change.
     * Re-applies the work area once all animations finish to resize the
     * container to the final preferred width — NOT per-frame, to avoid a
     * feedback loop where a shrinking container triggers further shrinking.
     */
    _animateIconResize() {
      if (!this._workArea) return;
      const dashAny = this;
      const iconChildren =
        dashAny._box
          ?.get_children?.()
          ?.filter(
            (actor) => actor.child?._delegate?.icon && !actor.animatingOut,
          ) ?? [];
      if (dashAny._showAppsIcon) {
        iconChildren.push(dashAny._showAppsIcon);
      }
      const isVisible = this.visible && this.opacity > 0;
      let pendingAnimations = 0;
      const onAnimationDone = () => {
        pendingAnimations--;
        if (this._isDestroyed) return;
        if (pendingAnimations === 0 && this._workArea) {
          this.applyWorkArea(this._workArea);
        }
      };
      for (const child of iconChildren) {
        const icon = child.child._delegate.icon;
        icon.setIconSize(dashAny.iconSize);
        const [targetWidth, targetHeight] = icon.icon.get_size();
        if (!isVisible) {
          icon.icon.set_size(targetWidth, targetHeight);
          continue;
        }
        pendingAnimations++;
        icon.icon.ease({
          width: targetWidth,
          height: targetHeight,
          duration: ANIMATION_TIME,
          mode: Clutter.AnimationMode.EASE_OUT_QUAD,
          onComplete: onAnimationDone,
        });
      }
      dashAny._separator?.ease({
        height: dashAny.iconSize,
        duration: ANIMATION_TIME,
        mode: Clutter.AnimationMode.EASE_OUT_QUAD,
      });
      if (pendingAnimations === 0 && this._workArea) {
        this.applyWorkArea(this._workArea);
      }
    }

    /** Start or restart the autohide timeout — hides the dock if not hovered/dragging/blocked. */
    _onHover() {
      if (this._isDestroyed) return;
      this._clearTimeout("_autohideTimeoutId");
      this._autohideTimeoutId = GLib.timeout_add(
        GLib.PRIORITY_DEFAULT,
        AUTOHIDE_TIMEOUT,
        () => {
          const dashContainer = this._dashContainer;
          if (
            dashContainer?.get_hover?.() ||
            this._draggingItem ||
            this._blockAutoHide ||
            this._isMenuOpen()
          ) {
            return GLib.SOURCE_CONTINUE;
          }
          this.hide(true);
          this._autohideTimeoutId = 0;
          return GLib.SOURCE_REMOVE;
        },
      );
    }

    /** If the cursor is still over the dash container, ensure the dock stays shown. */
    _ensureHoverState() {
      if (this._isDestroyed) return;
      this._clearTimeout("_blockAutoHideDelayId");
      this._blockAutoHideDelayId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
        const dashContainer = this._dashContainer;
        if (dashContainer?.get_hover?.()) this.show(false);
        this._blockAutoHideDelayId = 0;
        return GLib.SOURCE_REMOVE;
      });
    }

    _isFullyShown() {
      return (
        this.visible &&
        this.translation_y === 0 &&
        this.scale_x === 1 &&
        this.scale_y === 1 &&
        this.opacity === 255
      );
    }

    _isFullyHidden() {
      return !this.visible && this.opacity === 0;
    }

    /** Read the allocation box and return `{ width, height }`, or null if empty/missing. */
    _getAllocationSize() {
      const alloc = this.get_allocation_box?.();
      if (!alloc) return null;
      const width = Math.max(0, (alloc.x2 ?? 0) - (alloc.x1 ?? 0));
      const height = Math.max(0, (alloc.y2 ?? 0) - (alloc.y1 ?? 0));
      return width > 0 && height > 0 ? { width, height } : null;
    }

    _hasValidAllocation() {
      return this._getAllocationSize() !== null;
    }

    /**
     * Compute the dash bounds in stage coordinates and notify the intellihide
     * listener. Only reads `get_transformed_position` when the dash is visible
     * with no active translation, so the result reflects the true resting
     * position rather than a mid-animation snapshot.
     */
    _queueTargetBoxUpdate() {
      if (!this._container) return;
      const size = this._getAllocationSize();
      if (!size) return;
      if (!this.visible || this.translation_y !== 0) return;
      const [stageX, stageY] = this.get_transformed_position?.() ?? [0, 0];
      const p = TARGET_BOX_PADDING;
      const padded = {
        x: stageX - p,
        y: stageY - p,
        width: size.width + p * 2,
        height: size.height + p * 2,
      };
      if (!boundsEqual(this._targetBox, padded)) {
        this._targetBox = padded;
        this._targetBoxListener?.(this._targetBox);
      }
      this._flushPendingShow();
    }

    _flushPendingShow() {
      if (!this._pendingShow || !this._hasValidAllocation()) return;
      const { animate, onComplete } = this._pendingShow;
      this._pendingShow = null;
      this._performShow(animate, onComplete);
    }

    _getMarginBottom() {
      try {
        return this.get_theme_node().get_length("margin-bottom");
      } catch {
        return 0;
      }
    }

    /** Coalesce work-area resizes into a single deferred update. */
    _queueWorkAreaUpdate() {
      if (this._isDestroyed || this._workAreaUpdateId) return;
      this._workAreaUpdateId = GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, () => {
        this._workAreaUpdateId = 0;
        if (this._workArea) {
          this.applyWorkArea(this._workArea);
        }
        return GLib.SOURCE_REMOVE;
      });
    }

    _clearTimeout(prop) {
      if (this[prop]) {
        GLib.source_remove(this[prop]);
        this[prop] = 0;
      }
    }

    _clearAllTimeouts() {
      this._clearTimeout("_autohideTimeoutId");
      this._clearTimeout("_delayEnsureAutoHideId");
      this._clearTimeout("_blockAutoHideDelayId");
      this._clearTimeout("_workAreaUpdateId");
    }
  },
);

function boundsEqual(a, b) {
  if (a === b) return true;
  if (!a || !b) return false;
  return (
    a.x === b.x && a.y === b.y && a.width === b.width && a.height === b.height
  );
}

export { AuroraDash };
