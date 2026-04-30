import ExtensionFeature from '../core/extensionFeature.js';
import Signal from '../utils/signal.js';
import Clutter from 'gi://Clutter';

class TouchModeService extends ExtensionFeature {
    _enforceTouchMode = false;
    onChanged = new Signal();
    constructor(pm) {
        super(pm);
        this.pm.connectTo(Clutter.get_default_backend().get_default_seat(), 'notify::touch-mode', () => this._onChanged());
    }
    _onChanged() {
        this.onChanged.emit(this.isTouchModeActive);
    }
    get isTouchModeActive() {
        return this.enforceTouchMode || Clutter.get_default_backend().get_default_seat().touchMode;
    }
    get enforceTouchMode() {
        return this._enforceTouchMode;
    }
    set enforceTouchMode(value) {
        this._enforceTouchMode = value;
        this._onChanged();
    }
}

export { TouchModeService };
