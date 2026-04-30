// src/shared/icons.ts
import Gio from "gi://Gio";
import { Extension } from "resource:///org/gnome/shell/extensions/extension.js";

var ICON_CONTEXTS = [
  "apps",
  "categories",
  "devices",
  "emblems",
  "mimetypes",
  "places",
  "status",
];

function loadIcon(nameOrPath) {
  if (nameOrPath.startsWith("/")) {
    const file = Gio.File.new_for_path(nameOrPath);
    if (file.query_exists(null)) {
      return new Gio.FileIcon({ file });
    }
    return Gio.Icon.new_for_string("image-missing-symbolic");
  }
  const ext = Extension.lookupByURL(import.meta.url);
  if (ext) {
    for (const ctx of ICON_CONTEXTS) {
      const file = ext.dir.get_child(
        `icons/hicolor/scalable/${ctx}/${nameOrPath}.svg`,
      );
      if (file.query_exists(null)) {
        return new Gio.FileIcon({ file });
      }
    }
  }
  return Gio.Icon.new_for_string(nameOrPath);
}

export { loadIcon };
