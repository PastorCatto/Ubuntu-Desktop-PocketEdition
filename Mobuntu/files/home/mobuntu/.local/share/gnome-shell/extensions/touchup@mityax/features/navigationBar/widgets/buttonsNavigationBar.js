import BaseNavigationBar from './baseNavigationBar.js';
import St from 'gi://St';
import { Row, Bin, Button, Icon } from '../../../utils/ui/widgets.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Clutter from 'gi://Clutter';
import { settings } from '../../../settings.js';
import { logger } from '../../../core/logging.js';
import { navigateBack, moveToWorkspace } from '../navigationBarUtils.js';
import { AssetIcon } from '../../../utils/ui/assetIcon.js';
import GLib from 'gi://GLib';

var ActorAlign = Clutter.ActorAlign;
class ButtonsNavigationBar extends BaseNavigationBar {
    _virtualKeyboardDevice;
    constructor() {
        super({ reserveSpace: true });
        let seat = Clutter.get_default_backend().get_default_seat();
        this._virtualKeyboardDevice = seat.create_virtual_device(Clutter.InputDeviceType.KEYBOARD_DEVICE);
    }
    _buildActor() {
        return new Row({
            name: 'touchup-navbar',
            styleClass: 'touchup-navbar',
            onRealize: () => GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
                // Since the navigation bar's button sizes are not yet available before/at realization (at least
                // in Gnome >= 49), we schedule reallocation here once:
                this.reallocate();
                return GLib.SOURCE_REMOVE;
            }),
            children: [
                // Left side:
                new Row({
                    xExpand: false,
                    children: settings.navigationBar.buttonsLeft.get().map(b => this._buildButton(b)),
                    onCreated: (row) => {
                        const id = settings.navigationBar.buttonsLeft.connect("changed", newValue => {
                            row.destroy_all_children();
                            for (let b of settings.navigationBar.buttonsLeft.get()) {
                                row.add_child(this._buildButton(b));
                            }
                        });
                        return () => settings.navigationBar.buttonsLeft.disconnect(id);
                    }
                }),
                // Center:
                new Row({
                    xExpand: true,
                    xAlign: ActorAlign.CENTER,
                    children: settings.navigationBar.buttonsMiddle.get().map(b => this._buildButton(b)),
                    onCreated: (row) => {
                        const id = settings.navigationBar.buttonsMiddle.connect("changed", newValue => {
                            row.destroy_all_children();
                            for (let b of settings.navigationBar.buttonsMiddle.get()) {
                                row.add_child(this._buildButton(b));
                            }
                        });
                        return () => settings.navigationBar.buttonsMiddle.disconnect(id);
                    },
                }),
                // Right side:
                new Row({
                    xExpand: false,
                    children: settings.navigationBar.buttonsRight.get().map(b => this._buildButton(b)),
                    onCreated: (row) => {
                        const id = settings.navigationBar.buttonsRight.connect("changed", newValue => {
                            row.destroy_all_children();
                            for (let b of settings.navigationBar.buttonsRight.get()) {
                                row.add_child(this._buildButton(b));
                            }
                        });
                        return () => settings.navigationBar.buttonsRight.disconnect(id);
                    },
                }),
            ]
        });
    }
    onUpdateToSurrounding(surrounding) {
        if (surrounding.isWindowNear && !surrounding.isInOverview) {
            // Make navbar opaque (black or white, based on shell theme brightness):
            this.actor.remove_style_class_name('touchup-navbar--transparent');
        }
        else {
            // Make navbar transparent:
            this.actor.add_style_class_name('touchup-navbar--transparent');
        }
    }
    _buildButton(buttonType) {
        switch (buttonType) {
            case "keyboard":
                return new Button({
                    name: 'touchup-navbar__osk-button',
                    styleClass: 'touchup-navbar__button',
                    iconName: 'input-keyboard-symbolic',
                    onClicked: () => Main.keyboard.open(this.monitor.index),
                });
            case "workspace-previous":
                return new Button({
                    name: 'touchup-navbar__workspace-previous-button',
                    styleClass: 'touchup-navbar__button',
                    iconName: 'go-previous-symbolic',
                    onClicked: () => moveToWorkspace('left'),
                });
            case "workspace-next":
                return new Button({
                    name: 'touchup-navbar__workspace-next-button',
                    styleClass: 'touchup-navbar__button',
                    iconName: 'go-next-symbolic',
                    onClicked: () => moveToWorkspace('right'),
                });
            case "overview":
                return new Button({
                    name: 'touchup-navbar__overview-button',
                    styleClass: 'touchup-navbar__button',
                    child: new Icon({
                        gicon: new AssetIcon('box-outline-symbolic'),
                    }),
                    onClicked: () => Main.overview.toggle(),
                });
            case "apps":
                return new Button({
                    name: 'touchup-navbar__apps-button',
                    styleClass: 'touchup-navbar__button',
                    child: new Icon({
                        gicon: new AssetIcon('grid-large-symbolic'),
                    }),
                    onClicked: () => {
                        Main.overview.show();
                        Main.overview.dash.showAppsButton.checked = !Main.overview.dash.showAppsButton.checked;
                    },
                });
            case "back":
                return new Button({
                    name: 'touchup-navbar__back-button',
                    styleClass: 'touchup-navbar__button',
                    child: new Icon({
                        gicon: new AssetIcon('arrow2-left-symbolic'),
                    }),
                    onClicked: () => navigateBack({ virtualKeyboardDevice: this._virtualKeyboardDevice }),
                    onLongPress: () => navigateBack({
                        virtualKeyboardDevice: this._virtualKeyboardDevice,
                        greedyMode: true,
                    }),
                });
            case "spacer":
                return new Bin({ width: 20 });
            default:
                logger.warn(`Unknown button for ButtonNavigationBar: ${buttonType}`);
                return new St.Bin({}); // fallback to not crash on invalid settings
        }
    }
}

export { ButtonsNavigationBar as default };
