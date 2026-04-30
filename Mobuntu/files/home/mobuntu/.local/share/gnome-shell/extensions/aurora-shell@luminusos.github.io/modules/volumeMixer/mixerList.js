// src/modules/volumeMixer/mixerList.ts
import St from "gi://St";
import GObject from "gi://GObject";
import Gvc from "gi://Gvc";
import Clutter from "gi://Clutter";
import * as Volume from "resource:///org/gnome/shell/ui/status/volume.js";
import { VolumeMixerItem } from "./mixerItem.js";

var VolumeMixerList = GObject.registerClass(
  {
    Properties: {
      "should-show": GObject.ParamSpec.boolean(
        "should-show",
        null,
        null,
        GObject.ParamFlags.READWRITE,
        false,
      ),
    },
  },
  class VolumeMixerList2 extends St.BoxLayout {
    constructor() {
      super();
    }

    _init() {
      super._init({
        orientation: Clutter.Orientation.VERTICAL,
        style_class: "aurora-volume-mixer-list",
        clip_to_allocation: true,
        x_expand: true,
      });
      this._sliders = /* @__PURE__ */ new Map();
      this._control = Volume.getMixerControl();
      this._control.connectObject(
        "stream-added",
        (_ctrl, id) => this._streamAdded(id),
        "stream-removed",
        (_ctrl, id) => this._streamRemoved(id),
        "stream-changed",
        (_ctrl, id) => this._streamChanged(id),
        this,
      );
      for (const stream of this._control.get_streams()) {
        this._streamAdded(stream.get_id());
      }
      this.connect("destroy", () => {
        this._control.disconnectObject(this);
        for (const slider of this._sliders.values()) {
          slider.destroy();
        }
        this._sliders.clear();
      });
    }

    _streamAdded(id) {
      if (this._sliders.has(id)) return;
      const stream = this._control.lookup_stream_id(id);
      if (!stream) return;
      if (stream.is_event_stream || !(stream instanceof Gvc.MixerSinkInput))
        return;
      const item = new VolumeMixerItem(this._control, stream, true);
      this._sliders.set(id, item);
      this.add_child(item);
      this._sync();
    }

    _streamChanged(id) {
      const slider = this._sliders.get(id);
      if (!slider) return;
      slider.syncStream();
    }

    _streamRemoved(id) {
      const slider = this._sliders.get(id);
      if (!slider) return;
      slider.destroy();
      this._sliders.delete(id);
      this._sync();
    }

    _sync() {
      if (!this._sliders.size) {
        this.shouldShow = false;
        return;
      }
      for (const slider of this._sliders.values()) {
        if (slider.visible) {
          this.shouldShow = true;
          return;
        }
      }
      this.shouldShow = false;
    }
  },
);

export { VolumeMixerList };
