import { initSettings } from './backend.js';
import { NavigationBarPage } from './pages/navigationBarPage.js';
import { OskPage } from './pages/oskPage.js';
import { ExtensionPreferences } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
import { DonationsPage } from './pages/donationsPage.js';
import Gtk from 'gi://Gtk';
import Gdk from 'gi://Gdk';
import { settings } from '../../settings.js';
import { MiscPage } from './pages/miscPage.js';
import Gio from 'gi://Gio';
import { assetsGResourceFile } from '../../config.js';

class TouchUpPreferences extends ExtensionPreferences {
    async fillPreferencesWindow(window) {
        // @ts-ignore
        initSettings(this.getSettings());
        const assets = Gio.resource_load(this.dir.get_child(assetsGResourceFile).get_path());
        Gio.resources_register(assets);
        this.loadCss();
        Gtk.Settings.get_default()?.connect('notify::gtk-application-prefer-dark-theme', () => this.loadCss());
        const pages = [
            new NavigationBarPage(),
            new OskPage(),
            new MiscPage(),
            new DonationsPage(),
        ];
        pages.forEach(p => window.add(p));
        const initialPage = settings.initialPreferencesPage.get();
        if (pages.some(p => p.name == initialPage)) {
            window.visiblePageName = initialPage;
        }
        settings.initialPreferencesPage.set('default'); // reset initial page
        window.searchEnabled = true;
    }
    loadCss() {
        const display = Gdk.Display.get_default();
        const settings = Gtk.Settings.get_for_display(display);
        const cssProvider = new Gtk.CssProvider();
        const cssFile = this.dir.get_child(settings.gtk_application_prefer_dark_theme
            ? 'prefs-dark.css'
            : 'prefs-light.css');
        cssProvider.load_from_file(cssFile);
        Gtk.StyleContext.add_provider_for_display(display, cssProvider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }
}

export { TouchUpPreferences as default };
