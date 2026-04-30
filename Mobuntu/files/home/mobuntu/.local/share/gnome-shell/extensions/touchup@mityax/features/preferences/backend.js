import Gio from 'gi://Gio';
import { clamp } from '../../utils/utils.js';

let gioSettings = null;
/**
 * Initialize the settings using the given [Gio.Settings] instance.
 *
 * Do not forget to call [uninitSettings] when settings are no longer needed to
 * free the global reference kept to the [Gio.Settings] instance.
 */
function initSettings(settings) {
    gioSettings = settings;
}
function uninitSettings() {
    gioSettings = null;
}
class Setting {
    key;
    defaultValue;
    constructor(key, defaultValue) {
        this.key = key;
        this.defaultValue = defaultValue;
    }
    bind(instance, property, flags = Gio.SettingsBindFlags.DEFAULT) {
        gioSettings.bind(this.key, instance, property, flags);
    }
    connect(signal, handler) {
        if (!handler) {
            handler = signal;
            signal = 'changed';
        }
        return gioSettings.connect(`${signal}::${this.key}`, () => handler(this.get()));
    }
    disconnect(signalId) {
        gioSettings.disconnect(signalId);
    }
}
class EnumSetting extends Setting {
    get() {
        return gioSettings.get_string(this.key);
    }
    set(value) {
        gioSettings.set_string(this.key, value);
    }
}
class BoolSetting extends Setting {
    get() {
        return gioSettings.get_boolean(this.key);
    }
    set(value) {
        gioSettings.set_boolean(this.key, value);
    }
}
class IntSetting extends Setting {
    min;
    max;
    constructor(key, defaultValue, min, max) {
        super(key, defaultValue);
        this.min = min;
        this.max = max;
    }
    get() {
        return gioSettings.get_int(this.key);
    }
    set(value) {
        gioSettings.set_int(this.key, clamp(value, this.min, this.max));
    }
}
class StringSetting extends Setting {
    get() {
        return gioSettings.get_string(this.key);
    }
    set(value) {
        gioSettings.set_string(this.key, value);
    }
}
class StringListSetting extends Setting {
    get() {
        let res;
        gioSettings.get_mapped(this.key, value => {
            if (value === null) {
                res = [];
            }
            else {
                try {
                    res = JSON.parse(value.get_string()[0]);
                    this._validateValue(res);
                }
                catch (e) {
                    return false;
                }
            }
            return true;
        });
        return res;
    }
    set(value) {
        this._validateValue(value);
        gioSettings.set_string(this.key, JSON.stringify(value));
    }
    _validateValue(value) {
        if (!Array.isArray(value) || value.some(v => typeof v !== 'string')) {
            throw Error(`Invalid value for StringListSetting (not an array of strings): ${value}`);
        }
    }
}
/**
 * Store arbitrary (small!) JSON structures in a setting.
 *
 * This does not perform any kind of validation; we rely on typescript in this codebase and trust other
 * parties editing the setting to ensure that the data is valid.
 */
class JSONSetting extends Setting {
    get() {
        return JSON.parse(gioSettings.get_string(this.key));
    }
    set(value) {
        gioSettings.set_string(this.key, JSON.stringify(value));
    }
}

export { BoolSetting, EnumSetting, IntSetting, JSONSetting, Setting, StringListSetting, StringSetting, initSettings, uninitSettings };
