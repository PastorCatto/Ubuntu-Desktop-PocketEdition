// src/modules/noOverview.ts
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import { Module } from "../module.js";

var NoOverview = class extends Module {
  enable() {
    if (!Main.layoutManager._startingUp) return;
    Main.sessionMode.hasOverview = false;
    Main.layoutManager.connectObject(
      "startup-complete",
      () => {
        Main.sessionMode.hasOverview = true;
        Main.overview.hide();
      },
      this,
    );
  }

  disable() {
    Main.sessionMode.hasOverview = true;
    Main.layoutManager.disconnectObject(this);
  }
};

export { NoOverview };
