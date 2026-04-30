// src/modules/pipOnTop.ts
import Meta from "gi://Meta";
import { Module } from "../module.js";

var PIP_TITLES = [
  "Picture-in-Picture",
  "Picture in picture",
  "Picture-in-picture",
];

var PipOnTop = class extends Module {
  _lastWorkspace = null;
  _windowAddedId = 0;
  _windowRemovedId = 0;

  enable() {
    global.window_manager.connectObject(
      "switch-workspace",
      () => this._onSwitchWorkspace(),
      this,
    );
    this._onSwitchWorkspace();
  }

  disable() {
    global.window_manager.disconnectObject(this);
    this._disconnectWorkspace();
    for (const actor of global.get_window_actors()) {
      const window = actor.meta_window;
      if (!window) continue;
      this._cleanupWindow(window);
    }
  }

  _onSwitchWorkspace() {
    this._disconnectWorkspace();
    const workspace = global.workspace_manager.get_active_workspace();
    this._lastWorkspace = workspace;
    this._windowAddedId = workspace.connect("window-added", (_ws, window) =>
      this._onWindowAdded(window),
    );
    this._windowRemovedId = workspace.connect("window-removed", (_ws, window) =>
      this._onWindowRemoved(window),
    );
    const windows = global.display.get_tab_list(Meta.TabList.NORMAL, workspace);
    if (windows) {
      for (const window of windows) {
        this._onWindowAdded(window);
      }
    }
  }

  _disconnectWorkspace() {
    if (this._windowAddedId) {
      this._lastWorkspace.disconnect(this._windowAddedId);
      this._windowAddedId = 0;
    }
    if (this._windowRemovedId) {
      this._lastWorkspace.disconnect(this._windowRemovedId);
      this._windowRemovedId = 0;
    }
    this._lastWorkspace = null;
  }

  _onWindowAdded(window) {
    if (!window._notifyPipTitleId) {
      window._notifyPipTitleId = window.connect("notify::title", () =>
        this._checkTitle(window),
      );
    }
    this._checkTitle(window);
  }

  _onWindowRemoved(window) {
    if (window._notifyPipTitleId) {
      window.disconnect(window._notifyPipTitleId);
      window._notifyPipTitleId = null;
    }
  }

  _checkTitle(window) {
    if (!window.title) return;
    const isPip =
      PIP_TITLES.some((t) => window.title === t) ||
      window.title.endsWith(" - PiP");
    if (isPip) {
      window._isPipManaged = true;
      if (!window.above) window.make_above();
    } else if (window._isPipManaged) {
      window._isPipManaged = null;
      if (window.above) window.unmake_above();
    }
  }

  _cleanupWindow(window) {
    if (window._notifyPipTitleId) {
      window.disconnect(window._notifyPipTitleId);
      window._notifyPipTitleId = null;
    }
    if (window._isPipManaged) {
      if (window.above) window.unmake_above();
      window._isPipManaged = null;
    }
  }
};

export { PipOnTop };
