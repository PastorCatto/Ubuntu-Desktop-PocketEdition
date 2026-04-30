// src/modules/themeChanger.ts
import Gio from "gi://Gio";
import { Module } from "../module.js";

var ThemeChanger = class extends Module {
  _settings;
  _signalId = null;

  enable() {
    console.log("Initializing theme monitor");
    try {
      this._settings = new Gio.Settings({
        schema_id: "org.gnome.desktop.interface",
      });
      const currentScheme = this._settings.get_string("color-scheme");
      console.log(`Current color-scheme: ${currentScheme}`);
      this._signalId = this._settings.connect("changed::color-scheme", () => {
        this._onColorSchemeChanged();
      });
      console.log("Theme monitor active");
    } catch (error) {
      console.error("Failed to initialize:", error);
    }
  }

  _onColorSchemeChanged() {
    const scheme = this._settings.get_string("color-scheme");
    console.log(`Color scheme changed to: ${scheme}`);
    if (scheme === "default") {
      console.warn('Detected "default", forcing to prefer-light');
      this._settings.set_string("color-scheme", "prefer-light");
      return;
    }
  }

  disable() {
    console.log("Disabling theme monitor");
    if (this._signalId && this._settings) {
      this._settings.disconnect(this._signalId);
      this._signalId = null;
    }
    this._settings = null;
  }
};

export { ThemeChanger };
