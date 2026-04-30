// src/modules/volumeMixer/mixerPanel.ts
import St from "gi://St";
import GObject from "gi://GObject";
import Clutter from "gi://Clutter";
import { VolumeMixerList } from "./mixerList.js";

var MAX_MIXER_HEIGHT = 300;
var VolumeMixerPanel = GObject.registerClass(
  class VolumeMixerPanel2 extends St.BoxLayout {
    constructor() {
      super();
    }

    _init() {
      super._init({
        orientation: Clutter.Orientation.VERTICAL,
        style_class: "aurora-volume-mixer",
        style: `max-height: ${MAX_MIXER_HEIGHT}px;`,
      });
      this._emptyLabel = new St.Label({
        text: _("No audio playing"),
        style_class: "aurora-volume-mixer-empty",
        x_align: Clutter.ActorAlign.CENTER,
        y_align: Clutter.ActorAlign.CENTER,
        x_expand: true,
        y_expand: true,
      });
      this.add_child(this._emptyLabel);
      const sections = new St.BoxLayout({
        orientation: Clutter.Orientation.VERTICAL,
        x_expand: true,
        y_expand: true,
      });
      const scroll = new St.ScrollView({
        x_expand: true,
        y_expand: true,
        child: sections,
      });
      this._list = new VolumeMixerList();
      sections.add_child(this._list);
      this._scroll = scroll;
      this.add_child(scroll);
      this._list.connectObject("notify::should-show", () => this._sync(), this);
      this._sync();
    }

    _sync() {
      const hasStreams = this._list.shouldShow;
      this._scroll.visible = hasStreams;
      this._emptyLabel.visible = !hasStreams;
    }

    vfunc_get_preferred_height(forWidth) {
      if (!this.get_stage()) return [0, 0];
      if (!this._list.shouldShow) {
        return this._emptyLabel.get_preferred_height(forWidth);
      }
      const contentHeight = this._list.get_preferred_height(forWidth);
      return [
        Math.min(MAX_MIXER_HEIGHT, contentHeight[0]),
        Math.min(MAX_MIXER_HEIGHT, contentHeight[1]),
      ];
    }
  },
);

export { MAX_MIXER_HEIGHT, VolumeMixerPanel };
