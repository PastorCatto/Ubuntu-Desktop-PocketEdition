import ExtensionFeature from '../../core/extensionFeature.js';
import { settings } from '../../settings.js';

class BackgroundNavigationGesturesFeature extends ExtensionFeature {
    constructor(pm) {
        super(pm);
        this.defineSubFeature({
            name: 'desktop-background-gestures',
            create: async (pm) => {
                const m = await import('./_desktopBackgroundGestures.js');
                return new m.DesktopBackgroundGesturesFeature(pm);
            },
            setting: settings.backgroundNavigationGestures.desktopBackgroundGesturesEnabled,
        });
        this.defineSubFeature({
            name: 'overview-background-gestures',
            create: async (pm) => {
                const m = await import('./_overviewBackgroundGestures.js');
                return new m.OverviewBackgroundGesturesFeature(pm);
            },
            setting: settings.backgroundNavigationGestures.overviewBackgroundGesturesEnabled,
        });
        this.defineSubFeature({
            name: 'window-preview-gestures',
            create: async (pm) => {
                const m = await import('./_windowPreviewGestures.js');
                return new m.WindowPreviewGestureFeature(pm);
            },
            setting: settings.backgroundNavigationGestures.windowPreviewGesturesEnabled,
        });
    }
}

export { BackgroundNavigationGesturesFeature };
