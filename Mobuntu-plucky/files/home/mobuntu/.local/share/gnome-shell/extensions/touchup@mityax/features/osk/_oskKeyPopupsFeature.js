import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Clutter from 'gi://Clutter';
import GObject from 'gi://GObject';
import { logger } from '../../core/logging.js';
import ExtensionFeature from '../../core/extensionFeature.js';
import { settings } from '../../settings.js';
import { Delay } from '../../utils/delay.js';
import { extractKeyPrototype } from './_oskUtils.js';
import { Column, Label } from '../../utils/ui/widgets.js';

class OSKKeyPopupFeature extends ExtensionFeature {
    _keyPopupsCache = new Map();
    _hasPatchedKeyProto = false;
    constructor(pm, keyboard) {
        super(pm);
        // Destroy all cached popups on style change:
        this.pm.connectTo(settings.osk.keyPopups.style, 'changed', () => {
            this._keyPopupsCache.forEach((popup) => popup.destroy());
            this._keyPopupsCache.clear();
        });
        if (keyboard !== null) {
            this.onNewKeyboard(keyboard);
        }
    }
    _patchKeyMethods(keyProto) {
        const self = this;
        // Show the key popup on key press:
        this.pm.appendToMethod(keyProto, '_press', function (button, commitString) {
            if (!commitString || commitString.trim().length === 0) {
                return;
            }
            if (!self._keyPopupsCache.get(this)) {
                self._createKeyPopup(this, commitString);
            }
            self._keyPopupsCache.get(this)?.open();
            Delay.ms(2000).then(() => {
                self._keyPopupsCache.get(this)?.close();
            });
        });
        // Hide the key popup a few ms after a key has been released:
        this.pm.appendToMethod(keyProto, '_release', function (button, commitString) {
            Delay.ms(settings.osk.keyPopups.duration.get()).then(() => {
                self._keyPopupsCache.get(this)?.close();
            });
        });
        // Hide the key popup when the key's subkeys (umlauts etc.) popup is shown or the keypress is cancelled:
        this.pm.appendToMethod(keyProto, ['_showSubkeys', 'cancel'], function () {
            // @ts-ignore
            self._keyPopupsCache.get(this)?.close();
        });
    }
    _createKeyPopup(key, commitString) {
        const popup = new KeyPopup({
            sourceActor: key,
            label: commitString,
        });
        this._keyPopupsCache.set(key, popup);
        // When the popup is destroyed (which it is automatically, when the key it's attached to is),
        // remove it from the cache and drop this patch (to not destroy again later):
        popup.connect('destroy', () => this._keyPopupsCache.delete(key));
        // Destroy the popup on extension (or feature) disabling:
        this.pm.autoDestroy(popup);
        return popup;
    }
    onNewKeyboard(keyboard) {
        if (!this._hasPatchedKeyProto) {
            let proto = extractKeyPrototype(keyboard);
            if (proto !== null) {
                this._patchKeyMethods(proto);
                this._hasPatchedKeyProto = true;
            }
            else {
                logger.error("Could not extract Key prototype, thus not patching OSK key popups.");
            }
        }
    }
}
class KeyPopup extends Column {
    static {
        GObject.registerClass(this);
    }
    _sourceActor;
    _label;
    _open = false;
    constructor(props) {
        super({
            styleClass: [
                'touchup-osk-key-popup',
                `touchup-osk-key-popup--${settings.osk.keyPopups.style.get()}`,
                'keyboard-key'
            ], // inherit default key style via `keyboard-key` (color is overwritten in CSS)
            notifyMapped: () => this._relayout(),
        });
        this._sourceActor = props.sourceActor;
        this._label = new Label({
            text: props.label,
            yAlign: Clutter.ActorAlign.START,
            xAlign: Clutter.ActorAlign.CENTER,
        });
        this.add_child(this._label);
        this._sourceActor.connectObject('notify::allocation', () => this._relayout(), 'notify::mapped', () => this._updateOpen(), 'destroy', () => this.destroy(), this);
    }
    _relayout() {
        const sourceExtents = this._sourceActor.get_transformed_extents();
        const width = Math.max(sourceExtents.get_width(), this._label.width);
        const height = sourceExtents.get_height() + this._label.height;
        this.set_size(width, height);
        this.set_position(sourceExtents.get_x() + sourceExtents.get_width() / 2 - width / 2, sourceExtents.get_y() - this._label.height);
    }
    open() {
        this._open = true;
        this._updateOpen();
    }
    close() {
        this._open = false;
        this._updateOpen();
    }
    get _isActuallyOpen() {
        return this.get_parent() !== null;
    }
    get _shouldBeOpen() {
        return this._open && this._sourceActor.mapped;
    }
    _updateOpen() {
        if (this._shouldBeOpen && !this._isActuallyOpen) {
            Main.layoutManager.addTopChrome(this);
        }
        else if (!this._shouldBeOpen && this._isActuallyOpen) {
            Main.layoutManager.removeChrome(this);
        }
    }
    vfunc_pick(pick_context) {
        // By not making any call to this.pick_box(...) here, we make this actor pass through all events to
        // any actor potentially below it.
        return;
    }
}

export { OSKKeyPopupFeature };
