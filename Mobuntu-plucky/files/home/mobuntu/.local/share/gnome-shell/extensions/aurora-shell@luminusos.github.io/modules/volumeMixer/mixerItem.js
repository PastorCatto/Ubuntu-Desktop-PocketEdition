// src/modules/volumeMixer/mixerItem.ts
import St from "gi://St";
import GObject from "gi://GObject";
import Shell from "gi://Shell";
import Clutter from "gi://Clutter";
import { ApplicationStreamSlider } from "./streamSlider.js";

var VolumeMixerItem = GObject.registerClass(
  class VolumeMixerItem2 extends St.BoxLayout {
    constructor(control, stream, showIcon) {
      super(control, stream, showIcon);
    }

    _init(control, stream, showIcon) {
      super._init({
        orientation: Clutter.Orientation.VERTICAL,
        style_class: "aurora-volume-mixer-item",
      });
      this._stream = stream;
      const headerBox = new St.BoxLayout({
        orientation: Clutter.Orientation.HORIZONTAL,
        style_class: "aurora-volume-mixer-header",
        x_expand: true,
      });
      this._icon = new St.Icon({
        style_class: "aurora-volume-mixer-app-icon",
        icon_size: 16,
      });
      this._label = new St.Label({
        x_expand: true,
        y_align: Clutter.ActorAlign.CENTER,
        style_class: "aurora-volume-mixer-label",
      });
      headerBox.add_child(this._icon);
      headerBox.add_child(this._label);
      this.add_child(headerBox);
      this._slider = new ApplicationStreamSlider(control, stream, showIcon);
      this.add_child(this._slider);
      this._updateHeader();
    }

    _lookupApp() {
      const appSystem = Shell.AppSystem.get_default();
      const appId = this._stream.get_application_id();
      if (appId) {
        const app =
          appSystem.lookup_app(`${appId}.desktop`) ||
          appSystem.lookup_app(appId);
        if (app) return app;
      }
      const iconName = this._stream.get_icon_name();
      if (iconName) {
        const app =
          appSystem.lookup_app(`${iconName}.desktop`) ||
          appSystem.lookup_app(iconName);
        if (app) return app;
      }
      const name = this._stream.get_name();
      if (name) {
        const app =
          appSystem.lookup_desktop_wmclass(name) ||
          appSystem.lookup_startup_wmclass(name);
        if (app) return app;
      }
      const lowerAppId = appId?.toLowerCase();
      const lowerName = name?.toLowerCase();
      const lowerIcon = iconName?.toLowerCase();
      for (const app of appSystem.get_running()) {
        const id = app.get_id()?.toLowerCase();
        if (!id) continue;
        if (
          (lowerAppId && id.includes(lowerAppId)) ||
          (lowerName && id.includes(lowerName)) ||
          (lowerIcon && id.includes(lowerIcon))
        ) {
          return app;
        }
      }
      return null;
    }

    _updateHeader() {
      const app = this._lookupApp();
      const streamName = this._stream.get_name();
      const description = this._stream.get_description();
      if (app) {
        this._icon.gicon = app.get_icon();
        this._icon.show();
      } else if (this._stream.get_icon_name()) {
        this._icon.icon_name = this._stream.get_icon_name();
        this._icon.show();
      } else {
        this._icon.hide();
      }
      const appName = app ? app.get_name() : streamName;
      if (appName && description && description !== appName) {
        this._label.text = `${appName} \u2014 ${description}`;
      } else if (appName) {
        this._label.text = appName;
      } else if (description) {
        this._label.text = description;
      } else {
        this._label.text = _("Unknown");
      }
      this._label.show();
    }

    syncStream() {
      this._updateHeader();
      this._slider._sync();
    }
  },
);

export { VolumeMixerItem };
