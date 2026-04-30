// src/prefs.ts
import Adw from "gi://Adw";
import Gio from "gi://Gio";
import {

  ExtensionPreferences,
  gettext as _,
} from "resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js";
import { getModuleRegistry } from "./registry.js";

var AuroraShellPreferences = class extends ExtensionPreferences {
  // @ts-ignore: Conflicting Adw version types from gnome-shell
  fillPreferencesWindow(window) {
    const settings = this.getSettings();
    const page = new Adw.PreferencesPage({
      title: _("General"),
      icon_name: "dialog-information-symbolic",
    });
    const group = new Adw.PreferencesGroup({
      title: _("Modules"),
      description: _("Enable or disable extension modules"),
    });
    for (const def of getModuleRegistry()) {
      const row = new Adw.SwitchRow({
        title: def.title,
        subtitle: def.subtitle,
      });
      settings.bind(
        def.settingsKey,
        row,
        "active",
        Gio.SettingsBindFlags.DEFAULT,
      );
      group.add(row);
    }
    page.add(group);
    window.add(page);
    return Promise.resolve();
  }
};

export { AuroraShellPreferences as default };
