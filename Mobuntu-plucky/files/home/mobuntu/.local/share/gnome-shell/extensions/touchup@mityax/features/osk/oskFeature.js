import * as Keyboard from 'resource:///org/gnome/shell/ui/keyboard.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import ExtensionFeature from '../../core/extensionFeature.js';
import { settings } from '../../settings.js';
import { OSKKeyPopupFeature } from './_oskKeyPopupsFeature.js';
import { OSKGesturesFeature } from './_oskGesturesFeature.js';
import { OSKQuickPasteAction } from './_oskQuickPasteActionFeature.js';
import { OskSpaceBarIMESwitchingFeature } from './_oskSpaceBarIMESwitchingFeature.js';

//@ts-ignore
class OskFeature extends ExtensionFeature {
    async initialize() {
        await this.defineSubFeature({
            name: 'osk-key-popups',
            create: (pm) => new OSKKeyPopupFeature(pm, Main.keyboard._keyboard),
            setting: settings.osk.keyPopups.enabled,
        });
        await this.defineSubFeature({
            name: 'osk-gestures',
            create: (pm) => new OSKGesturesFeature(pm, Main.keyboard._keyboard),
        });
        await this.defineSubFeature({
            name: 'osk-quick-paste-action',
            create: (pm) => new OSKQuickPasteAction(pm, Main.keyboard._keyboard),
            setting: settings.osk.quickPasteAction.enabled,
        });
        await this.defineSubFeature({
            name: 'osk-space-bar-ime-switching',
            create: (pm) => new OskSpaceBarIMESwitchingFeature(pm, Main.keyboard._keyboard),
            setting: settings.osk.spaceBarIMESwitching.enabled,
        });
        // When the keyboard is replaced/a new keyboard is created, notify all sub-features:
        const self = this;
        this.pm.appendToMethod(Keyboard.Keyboard.prototype, '_init', function () {
            self.getSubFeature(OSKKeyPopupFeature)?.onNewKeyboard(this);
            self.getSubFeature(OSKGesturesFeature)?.onNewKeyboard(this);
            self.getSubFeature(OSKQuickPasteAction)?.onNewKeyboard(this);
            self.getSubFeature(OskSpaceBarIMESwitchingFeature)?.onNewKeyboard(this);
        });
    }
}

export { OskFeature };
