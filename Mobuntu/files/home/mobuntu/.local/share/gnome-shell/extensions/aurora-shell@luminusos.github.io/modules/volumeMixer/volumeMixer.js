// src/modules/volumeMixer/volumeMixer.ts
import St from "gi://St";
import Gio from "gi://Gio";
import * as Main from "resource:///org/gnome/shell/ui/main.js";
import * as PopupMenu from "resource:///org/gnome/shell/ui/popupMenu.js";
import { Module } from "../../module.js";
import { VolumeMixerPanel } from "./mixerPanel.js";
import { loadIcon } from "../../shared/icons.js";

var VolumeMixer = class extends Module {
  _panel = null;
  _toggleButton = null;
  _menuSection = null;
  _settingsSection = null;
  _outputSlider = null;
  _menuClosedId = 0;
  _gridChildAddedId = 0;
  _quickSettings = null;

  enable() {
    this._quickSettings = Main.panel.statusArea.quickSettings;
    const outputSlider = this._findOutputSlider();
    if (outputSlider) {
      this._attachToSlider(outputSlider);
      return;
    }
    const grid = Main.panel.statusArea.quickSettings?.menu?._grid;
    if (!grid) {
      console.error(
        "Aurora Shell: VolumeMixer could not find quick settings grid",
      );
      return;
    }
    this._gridChildAddedId = grid.connect("child-added", () => {
      if (this._outputSlider) return;
      const slider = this._findOutputSlider();
      if (slider) {
        grid.disconnect(this._gridChildAddedId);
        this._gridChildAddedId = 0;
        this._attachToSlider(slider);
      }
    });
  }

  disable() {
    if (this._gridChildAddedId) {
      Main.panel.statusArea.quickSettings?.menu?._grid?.disconnect(
        this._gridChildAddedId,
      );
      this._gridChildAddedId = 0;
    }
    if (this._menuClosedId && this._outputSlider) {
      this._outputSlider.menu.disconnect(this._menuClosedId);
      this._menuClosedId = 0;
    }
    if (this._toggleButton) {
      this._toggleButton.destroy();
      this._toggleButton = null;
    }
    if (this._menuSection) {
      this._menuSection.destroy();
      this._menuSection = null;
    }
    if (this._settingsSection) {
      this._settingsSection.destroy();
      this._settingsSection = null;
    }
    if (this._panel) {
      this._panel.destroy();
      this._panel = null;
    }
    this._outputSlider = null;
  }

  _findOutputSlider() {
    const grid = this._quickSettings?.menu?._grid;
    if (!grid) {
      console.error(
        "Aurora Shell: VolumeMixer could not find quick settings grid",
      );
      return null;
    }
    for (const child of grid.get_children()) {
      if (child.constructor.name === "OutputStreamSlider") {
        return child;
      }
    }
    return null;
  }

  _attachToSlider(slider) {
    this._outputSlider = slider;
    this._panel = new VolumeMixerPanel();
    this._menuSection = new PopupMenu.PopupMenuSection();
    this._menuSection.box.add_child(this._panel);
    slider.menu.addMenuItem(this._menuSection, 1);
    this._menuSection.box.hide();
    this._settingsSection = new PopupMenu.PopupMenuSection();
    const settingsItem = new PopupMenu.PopupMenuItem(_("Sound Settings"));
    settingsItem.connect("activate", () => {
      try {
        Gio.Subprocess.new(
          ["gnome-control-center", "sound"],
          Gio.SubprocessFlags.NONE,
        );
      } catch (e) {
        console.error(`Aurora Shell: Failed to open sound settings: ${e}`);
      }
      this._quickSettings?.menu.close(true);
    });
    this._settingsSection.addMenuItem(settingsItem);
    slider.menu.addMenuItem(this._settingsSection, 3);
    this._settingsSection.box.hide();
    this._toggleButton = new St.Button({
      child: new St.Icon({ gicon: loadIcon("volume-mixer-symbolic") }),
      style_class: "icon-button flat",
      can_focus: true,
      x_expand: false,
      y_expand: true,
      accessible_name: _("Volume Mixer"),
    });
    slider.child.add_child(this._toggleButton);
    this._toggleButton.connect("clicked", () => {
      if (!this._panel || !this._menuSection || !this._settingsSection) return;
      this._menuSection.box.show();
      this._settingsSection.box.show();
      slider._deviceSection?.box.hide();
      slider.menu._setSettingsVisibility?.(false);
      slider.menu.setHeader("audio-speakers-symbolic", _("Volume Mixer"));
      slider.menu.open(true);
    });
    this._menuClosedId = slider.menu.connect("menu-closed", () => {
      if (!this._menuSection || !this._settingsSection) return;
      this._menuSection.box.hide();
      this._settingsSection.box.hide();
      slider._deviceSection?.box.show();
      slider.menu._setSettingsVisibility?.(Main.sessionMode.allowSettings);
      slider.menu.setHeader("audio-headphones-symbolic", _("Sound Output"));
    });
  }
};

export { VolumeMixer };
