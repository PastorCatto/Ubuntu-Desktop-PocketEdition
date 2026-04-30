// src/extension.ts
import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";
import { getModuleRegistry } from "./registry.js";
import { NoOverview } from "./modules/noOverview.js";
import { PipOnTop } from "./modules/pipOnTop.js";
import { ThemeChanger } from "./modules/themeChanger.js";
import { Dock } from "./modules/dock/dock.js";
import { VolumeMixer } from "./modules/volumeMixer/volumeMixer.js";

var MODULE_FACTORIES = {
  "no-overview": () => new NoOverview(),
  "pip-on-top": () => new PipOnTop(),
  "theme-changer": () => new ThemeChanger(),
  dock: () => new Dock(),
  "volume-mixer": () => new VolumeMixer(),
};

var AuroraShellExtension = class extends Extension {
  _modules = /* @__PURE__ */ new Map();
  _settings = null;

  enable() {
    console.log("Enabling extension");
    this._settings = this.getSettings();
    this._initializeModules();
    this._enableAllModules();
    this._connectSettings();
  }

  _initializeModules() {
    for (const def of getModuleRegistry()) {
      if (this._settings?.get_boolean(def.settingsKey)) {
        this._modules.set(def.key, MODULE_FACTORIES[def.key]());
      }
    }
  }

  _enableAllModules() {
    for (const [name, module] of this._modules) {
      try {
        module.enable();
      } catch (e) {
        console.error(`Aurora Shell: Failed to enable module ${name}:`, e);
      }
    }
  }

  _connectSettings() {
    if (!this._settings) return;
    const args = [];
    for (const def of getModuleRegistry()) {
      args.push(`changed::${def.settingsKey}`, () => {
        this._toggleModule(def);
      });
    }
    args.push(this);
    this._settings.connectObject(...args);
  }

  _toggleModule(def) {
    const enabled = this._settings.get_boolean(def.settingsKey);
    const existing = this._modules.get(def.key);
    if (enabled && !existing) {
      console.log(`Aurora Shell: Enabling module ${def.key}`);
      try {
        const module = MODULE_FACTORIES[def.key]();
        module.enable();
        this._modules.set(def.key, module);
      } catch (e) {
        console.error(`Aurora Shell: Failed to enable module ${def.key}:`, e);
      }
    } else if (!enabled && existing) {
      console.log(`Aurora Shell: Disabling module ${def.key}`);
      try {
        existing.disable();
        this._modules.delete(def.key);
      } catch (e) {
        console.error(`Aurora Shell: Failed to disable module ${def.key}:`, e);
      }
    }
  }

  disable() {
    console.log("Aurora Shell: Disabling extension");
    this._settings?.disconnectObject(this);
    for (const [name, module] of this._modules) {
      try {
        module.disable();
      } catch (e) {
        console.error(`Aurora Shell: Failed to disable module ${name}:`, e);
      }
    }
    this._modules.clear();
    this._settings = null;
  }
};

export { AuroraShellExtension as default };
