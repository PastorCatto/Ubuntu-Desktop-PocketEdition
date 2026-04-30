// src/modules/volumeMixer/streamSlider.ts
import GObject from "gi://GObject";
import Gvc from "gi://Gvc";
import Gio from "gi://Gio";
import GLib from "gi://GLib";
import { QuickSlider } from "resource:///org/gnome/shell/ui/quickSettings.js";

var ALLOW_AMPLIFIED_VOLUME_KEY = "allow-volume-above-100-percent";
var ApplicationStreamSlider = GObject.registerClass(
  {
    Signals: {
      "stream-updated": {},
    },
  },
  class ApplicationStreamSlider2 extends QuickSlider {
    constructor(control, stream, showIcon) {
      super(control, stream, showIcon);
    }

    _init(control, stream, showIcon) {
      this._control = control;
      this._notifyVolumeChangeId = 0;
      this._volumeCancellable = null;
      this._showIcon = showIcon;
      super._init();
      this._soundSettings = new Gio.Settings({
        schema_id: "org.gnome.desktop.sound",
      });
      this._soundSettings.connectObject(
        `changed::${ALLOW_AMPLIFIED_VOLUME_KEY}`,
        () => this._updateAllowAmplified(),
        this,
      );
      this._updateAllowAmplified();
      this.iconReactive = true;
      this.connect("icon-clicked", () => {
        if (!this._stream) return;
        this._stream.change_is_muted(!this._stream.is_muted);
      });
      this._inDrag = false;
      this._sliderChangedId = this.slider.connect("notify::value", () =>
        this._sliderChanged(),
      );
      this.slider.connect("drag-begin", () => {
        this._inDrag = true;
      });
      this.slider.connect("drag-end", () => {
        this._inDrag = false;
      });
      if (stream) {
        this.stream = stream;
      } else {
        this._stream = null;
      }
    }

    get stream() {
      return this._stream;
    }

    set stream(stream) {
      if (this._stream === stream) return;
      this._stream?.disconnectObject(this);
      this._stream = stream;
      if (stream) {
        stream.connectObject(
          "notify::is-muted",
          () => this._updateSlider(),
          "notify::volume",
          () => this._updateSlider(),
          this,
        );
        this._updateSlider();
      } else {
        this.emit("stream-updated");
      }
      this._sync();
    }

    _sync() {
      this.visible = this._stream != null;
      this.menuEnabled = false;
      if (this._showIcon && this._stream) {
        this._updateVolumeIcon();
      }
    }

    _updateVolumeIcon() {
      if (!this._stream) return;
      let iconName;
      if (this._stream.is_muted || this._stream.volume === 0) {
        iconName = "audio-volume-muted-symbolic";
      } else {
        const norm = this._control.get_vol_max_norm();
        const ratio = this._stream.volume / norm;
        if (ratio < 0.33) {
          iconName = "audio-volume-low-symbolic";
        } else if (ratio < 0.66) {
          iconName = "audio-volume-medium-symbolic";
        } else {
          iconName = "audio-volume-high-symbolic";
        }
      }
      this.iconName = iconName;
    }

    _feedbackVolumeChange() {
      if (this._volumeCancellable) this._volumeCancellable.cancel();
      this._volumeCancellable = null;
      if (this._stream.state === Gvc.MixerStreamState.RUNNING) return;
      this._volumeCancellable = new Gio.Cancellable();
      global.display
        .get_sound_player()
        .play_from_theme(
          "audio-volume-change",
          _("Volume changed"),
          this._volumeCancellable,
        );
    }

    _updateSlider() {
      this.slider.block_signal_handler(this._sliderChangedId);
      this.slider.value = this._stream.is_muted
        ? 0
        : this._stream.volume / this._control.get_vol_max_norm();
      this.slider.unblock_signal_handler(this._sliderChangedId);
      if (this._showIcon) this._updateVolumeIcon();
      this.emit("stream-updated");
    }

    _sliderChanged() {
      if (!this._stream) return;
      const volume = this.slider.value * this._control.get_vol_max_norm();
      const prevMuted = this._stream.is_muted;
      const prevVolume = this._stream.volume;
      const volumeChanged = this._stream.volume !== prevVolume;
      if (volume < 1) {
        this._stream.volume = 0;
        if (!prevMuted) this._stream.change_is_muted(true);
      } else {
        this._stream.volume = volume;
        if (prevMuted) this._stream.change_is_muted(false);
      }
      this._stream.push_volume();
      if (volumeChanged && !this._notifyVolumeChangeId && !this._inDrag) {
        this._notifyVolumeChangeId = GLib.timeout_add(
          GLib.PRIORITY_DEFAULT,
          30,
          () => {
            this._feedbackVolumeChange();
            this._notifyVolumeChangeId = 0;
            return GLib.SOURCE_REMOVE;
          },
        );
      }
    }

    _updateAllowAmplified() {
      this._allowAmplified = this._soundSettings.get_boolean(
        ALLOW_AMPLIFIED_VOLUME_KEY,
      );
      const maxLevel = this._allowAmplified
        ? this._control.get_vol_max_amplified() /
          this._control.get_vol_max_norm()
        : 1;
      this.slider.maximumValue = maxLevel;
      if (this._stream) this._updateSlider();
    }

    destroy() {
      if (this._notifyVolumeChangeId) {
        GLib.Source.remove(this._notifyVolumeChangeId);
        this._notifyVolumeChangeId = 0;
      }
      if (this._volumeCancellable) {
        this._volumeCancellable.cancel();
        this._volumeCancellable = null;
      }
      this._soundSettings?.disconnectObject(this);
      this._stream?.disconnectObject(this);
      super.destroy();
    }

    vfunc_get_preferred_height(forWidth) {
      return super.vfunc_get_preferred_height(forWidth).map(Math.floor);
    }
  },
);

export { ApplicationStreamSlider };
