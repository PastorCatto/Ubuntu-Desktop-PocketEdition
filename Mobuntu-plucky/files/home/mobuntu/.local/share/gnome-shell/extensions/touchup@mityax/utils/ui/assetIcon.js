import Gio from 'gi://Gio';
import GObject from 'gi://GObject';
import { assetPath } from '../../config.js';

class AssetIcon extends Gio.FileIcon {
    static {
        GObject.registerClass(this);
    }
    constructor(iconName) {
        super({
            file: Gio.File.new_for_uri(assetPath.icon(iconName)),
        });
    }
}

export { AssetIcon };
