import GLib from 'gi://GLib';

const logFile = GLib.getenv('TOUCHUP_LOGFILE');
['true', 'yes', '1'].includes(GLib.getenv('TOUCHUP_DEV_MODE') ?? 'false');
const assetsGResourceFile = 'assets.gresource';
/**
 * Path configuration for the resources embedded in [assetsGResourceFile]
 */
const assetPath = Object.freeze({
    root: 'resource:///org/gnome/shell/extensions/touchup',
    icon: (name) => `resource:///org/gnome/shell/extensions/touchup/icons/scalable/actions/${name}.svg`,
});
/**
 * All platforms users can use to donate
 */
const donationPlatforms = Object.freeze([
    {
        name: 'Ko-fi',
        url: 'https://ko-fi.com/mityax',
        description: 'Most payment methods, one-time or recurring donations, no sign up required.',
        recommended: true,
    },
    {
        name: 'Buy Me A Coffee',
        url: 'https://buymeacoffee.com/mityax',
        description: 'Donate by card, no sign up required.',
    },
]);
const feedbackPlatforms = Object.freeze([
    {
        title: 'Create an Issue on GitHub',
        url: 'https://github.com/mityax/gnome-extension-touchup/issues/new',
        buttonLabel: 'Create Issue',
    },
    {
        title: 'Leave a review on Gnome Extensions',
        url: 'https://extensions.gnome.org/extension/8102',
        buttonLabel: 'Leave Review',
    },
]);

export { assetPath, assetsGResourceFile, donationPlatforms, feedbackPlatforms, logFile };
