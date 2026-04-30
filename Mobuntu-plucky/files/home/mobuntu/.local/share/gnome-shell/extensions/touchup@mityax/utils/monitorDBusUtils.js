import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const Methods = Object.freeze({
    verify: 0,
    temporary: 1,
    persistent: 2,
});
function setMonitorTransform(transform, targetMonitor) {
    DisplayConfigState.getCurrent()
        .then((state) => {
        targetMonitor ??= state.builtinMonitor ?? state.monitors[0];
        const logicalMonitor = state.getLogicalMonitorFor(targetMonitor.connector);
        if (logicalMonitor) {
            logicalMonitor.transform = transform;
            callDbusMethod('ApplyMonitorsConfig', null, state.packToApply(Methods.temporary));
        }
    });
}
class LogicalMonitor {
    x;
    y;
    scale;
    transform;
    primary;
    monitors;
    properties;
    constructor(variant) {
        const unpacked = variant.unpack();
        this.x = unpacked[0].unpack();
        this.y = unpacked[1].unpack();
        this.scale = unpacked[2].unpack();
        this.transform = unpacked[3].unpack();
        this.primary = unpacked[4].unpack();
        this.monitors = unpacked[5].deep_unpack();
        this.properties = unpacked[6].unpack();
        for (const key in this.properties) {
            this.properties[key] = this.properties[key].unpack().unpack();
        }
    }
}
class Monitor {
    connector;
    vendorName;
    productName;
    productSerial;
    currentModeId = null;
    isUnderscanning = false;
    isBuiltin = false;
    constructor(variant) {
        // variant.deepUnpack() yields (in Gnome 48):
        // (see for docs: https://gitlab.gnome.org/GNOME/mutter/-/blob/main/data/dbus-interfaces/org.gnome.Mutter.DisplayConfig.xml#L385)
        // [
        //   [ // - [0] - meta information
        //     "LVDS1", // - [0][0] - connector
        //     "MetaProducts Inc.",  // vendor name
        //     "MetaMonitor",  // product name
        //     "0xC0FFEE-1"  // product serial
        //   ],
        //   [ // - [1] - "modes"
        //     [
        //       "1400x1000@60.000", // - [1][0]
        //       1400,
        //       1000,
        //       60,
        //       1,
        //       [ // - [1][1]
        //         1, // - [1][1][0]
        //         1.25,
        //         1.5037593841552734,
        //         1.7543859481811523
        //       ],
        //       {
        //         "is-current": {},
        //         "is-preferred": {}
        //       }
        //     ]
        //   ],
        //   { // - [2] - "props"
        //     "is-builtin": {},
        //     "display-name": {},
        //     "is-for-lease": {},
        //     "color-mode": {},
        //     "supported-color-modes": {}
        //   }
        // ]
        const unpacked = variant.deepUnpack();
        this.connector = unpacked[0][0];
        this.vendorName = unpacked[0][1];
        this.productName = unpacked[0][2];
        this.productSerial = unpacked[0][3];
        const modes = unpacked[1];
        for (const modeVariant of modes) {
            const mode = modeVariant;
            const id = mode[0];
            const modeProps = mode[6];
            if ('is-current' in modeProps) {
                const isCurrent = modeProps['is-current'].get_boolean();
                if (isCurrent) {
                    this.currentModeId = id;
                    break;
                }
            }
        }
        const props = unpacked[2];
        if ('is-underscanning' in props) {
            this.isUnderscanning = props['is-underscanning'].get_boolean();
        }
        if ('is-builtin' in props) {
            this.isBuiltin = props['is-builtin'].get_boolean();
        }
    }
    /**
     * This method makes no guarantees about the returned string, except that it will uniquely
     * identify this physical monitor, even after disconnecting and reconnecting it.
     *
     * This is at the moment done by monitor metadata by constructing a tuple of (vendor name,
     * product name, serial).
     */
    constructMonitorId() {
        return `${this.vendorName}::${this.productName}::${this.productSerial}`;
    }
}
class DisplayConfigState {
    serial;
    monitors = [];
    logicalMonitors = [];
    properties;
    constructor(result) {
        const unpacked = result.unpack();
        this.serial = unpacked[0].unpack();
        const monitorVariants = unpacked[1].unpack();
        for (const monitorPacked of monitorVariants) {
            this.monitors.push(new Monitor(monitorPacked));
        }
        const logicalMonitorVariants = unpacked[2].unpack();
        for (const logicalMonitorPacked of logicalMonitorVariants) {
            this.logicalMonitors.push(new LogicalMonitor(logicalMonitorPacked));
        }
        this.properties = unpacked[3].unpack();
        for (const key in this.properties) {
            this.properties[key] = this.properties[key].unpack().unpack();
        }
    }
    static async getCurrent() {
        return new Promise((resolve, reject) => {
            callDbusMethod('GetCurrentState', (conn, res) => {
                try {
                    const reply = conn?.call_finish(res);
                    const configState = new DisplayConfigState(reply);
                    resolve(configState);
                }
                catch (err) {
                    reject(err);
                }
            });
        });
    }
    get builtinMonitor() {
        return this.monitors.find((monitor) => monitor.isBuiltin) ?? this.monitors[0];
    }
    getMonitor(connector) {
        return this.monitors.find((monitor) => monitor.connector === connector) || null;
    }
    getLogicalMonitorFor(connector) {
        return this.logicalMonitors.find((logMonitor) => logMonitor.monitors.some((lmMonitor) => connector === lmMonitor[0])) || null;
    }
    setPrimaryMonitor(monitor) {
        this.logicalMonitors.forEach(m => m.primary = false);
        monitor.primary = true;
        callDbusMethod('ApplyMonitorsConfig', null, this.packToApply(Methods.temporary));
    }
    packToApply(method) {
        const packing = [this.serial, method, [], {}];
        const logicalMonitors = packing[2];
        const properties = packing[3];
        this.logicalMonitors.forEach((logicalMonitor) => {
            const lmonitorPack = [
                logicalMonitor.x,
                logicalMonitor.y,
                logicalMonitor.scale,
                logicalMonitor.transform,
                logicalMonitor.primary,
                [],
            ];
            const monitors = lmonitorPack[5];
            for (const logMonitor of logicalMonitor.monitors) {
                const connector = logMonitor[0];
                const monitor = this.getMonitor(connector);
                if (monitor) {
                    monitors.push([
                        connector,
                        monitor.currentModeId,
                        {
                            enable_underscanning: new GLib.Variant('b', monitor.isUnderscanning),
                        },
                    ]);
                }
            }
            logicalMonitors.push(lmonitorPack);
        });
        if ('layout-mode' in this.properties) {
            properties['layout-mode'] = new GLib.Variant('b', this.properties['layout-mode']);
        }
        return new GLib.Variant('(uua(iiduba(ssa{sv}))a{sv})', packing);
    }
}
function callDbusMethod(method, handler, params = null) {
    if (handler !== null && handler !== undefined) {
        Gio.DBus.session.call('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig', 'org.gnome.Mutter.DisplayConfig', method, params, null, Gio.DBusCallFlags.NONE, -1, null, handler);
    }
    else {
        Gio.DBus.session.call('org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig', 'org.gnome.Mutter.DisplayConfig', method, params, null, Gio.DBusCallFlags.NONE, -1, null);
    }
}

export { DisplayConfigState, LogicalMonitor, Methods, Monitor, setMonitorTransform };
