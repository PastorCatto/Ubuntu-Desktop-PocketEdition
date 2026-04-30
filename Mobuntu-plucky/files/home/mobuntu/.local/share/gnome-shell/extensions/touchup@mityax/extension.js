import Gio from 'gi://Gio';
import { PatchManager } from './core/patchManager.js';
import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import { initSettings, uninitSettings } from './features/preferences/backend.js';
import { Delay } from './utils/delay.js';
import { assetsGResourceFile } from './config.js';
import { settings } from './settings.js';
import { TouchModeService } from './services/touchModeService.js';
import { DonationsFeature } from './features/donations/donationsFeature.js';
import { NotificationService } from './services/notificationService.js';
import { initLogger, uninitLogger } from './core/logging.js';
import { DisablePanelDragService } from './services/disablePanelDragService.js';
import { ExtensionFeatureManager, SessionMode } from './core/extensionFeatureManager.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

class TouchUpExtension extends Extension {
    static instance;
    pm;
    featureManager;
    async enable() {
        TouchUpExtension.instance = this;
        initLogger();
        // This is the root patch manager of which all other patch managers are descendents:
        this.pm = new PatchManager("root");
        // Load assets:
        this.pm.patch(() => {
            const assets = Gio.resource_load(this.dir.get_child(assetsGResourceFile).get_path());
            Gio.resources_register(assets);
            return () => Gio.resources_unregister(assets);
        }, 'load-and-register-assets');
        // Initialize settings:
        this.pm.patch(() => {
            initSettings(this.getSettings());
            return () => uninitSettings();
        }, 'init-settings');
        this.pm.connectTo(Main.sessionMode, 'updated', async () => {
            await this.featureManager.notifySessionModeChanged();
        });
        this.featureManager = new ExtensionFeatureManager(this.pm.fork("fm"));
        // This is the entry point for all services (= small supplementary ExtensionFeature's, that other
        // features need to work):
        await this.defineServices();
        // This is the entry point for all features of this extension:
        await this.defineFeatures();
    }
    async defineServices() {
        await this.defineFeature({
            name: 'touch-mode-service',
            create: pm => new TouchModeService(pm)
        });
        await this.defineFeature({
            name: 'notification-service',
            create: pm => new NotificationService(pm)
        });
        await this.defineFeature({
            name: 'disable-panel-drag-service',
            create: pm => new DisablePanelDragService(pm),
        });
    }
    async defineFeatures() {
        // Optional features (that can be toggled on or off via a setting) are imported dynamically, for two reasons:
        //  - make the extension as slim as possible (users only "pay" for what they use)
        //  - make the extension more compatible with modified shells (e.g. Ubuntu or Gnome Mobile): turned off
        //    features cannot cause errors
        await this.defineFeature({
            name: 'navigation-bar',
            setting: settings.navigationBar.enabled,
            create: async (pm) => {
                const m = (await import('./features/navigationBar/navigationBarFeature.js'));
                return new m.NavigationBarFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'background-gestures',
            create: async (pm) => {
                const m = (await import('./features/backgroundNavigationGestures/backgroundNavigationGesturesFeature.js'));
                return new m.BackgroundNavigationGesturesFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'notification-gestures',
            setting: settings.notificationGestures.enabled,
            create: async (pm) => {
                const m = (await import('./features/notifications/notificationGesturesFeature.js'));
                return new m.NotificationGesturesFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'osk',
            create: async (pm) => {
                const m = (await import('./features/osk/oskFeature.js'));
                return new m.OskFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'floating-screen-rotate-button',
            setting: settings.screenRotateUtils.floatingScreenRotateButtonEnabled,
            create: async (pm) => {
                const m = (await import('./features/screenRotateUtils/floatingScreenRotateButtonFeature.js'));
                return new m.FloatingScreenRotateButtonFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'double-tap-to-sleep',
            setting: settings.doubleTapToSleep.enabled,
            sessionModes: [SessionMode.user, SessionMode.unlockDialog],
            create: async (pm) => {
                const m = (await import('./features/doubleTapToSleep/doubleTapToSleepFeature.js'));
                return new m.DoubleTapToSleepFeature(pm);
            },
        });
        await this.defineFeature({
            name: 'donations',
            create: pm => new DonationsFeature(pm),
        });
    }
    /**
     * A utility method to define [ExtensionFeature]s that are optionally automatically enabled/disabled
     * depending on the given [setting] and [sessionModes].
     *
     * All features are automatically destroyed when the extension is disabled.
     */
    async defineFeature(meta) {
        await this.featureManager.defineFeature(meta);
    }
    getFeature(type) {
        return this.featureManager.getFeature(type);
    }
    /*
     * Session Modes:
     * This extension uses "unlock-dialog" session mode for some lockscreen features:
     *  - DoubleClickToSleep: Double tap `ScreenShield` to suspend
     */
    disable() {
        // Cancel any pending delays:
        Delay.getAllPendingDelays().forEach(d => d.cancel());
        // Destroy the root PatchManager and with that all its descendents:
        this.pm?.destroy();
        this.pm = undefined;
        // Destroy all features:
        this.featureManager?.destroy();
        this.featureManager = undefined;
        uninitLogger();
        TouchUpExtension.instance = undefined;
    }
}

export { TouchUpExtension as default };
