import St from 'gi://St';
import GObject from 'gi://GObject';
import { filterObject } from '../utils.js';
import Clutter from 'gi://Clutter';

/**
 * The [Widgets] module provides subclasses for most St.Widgets, that offer an easier, briefer and more elegant
 * way to create complex user interfaces - in a nested declarative way:
 *
 * ```
 * const myWidget = new Widgets.Column({
 *   children: [
 *     new Widgets.Label("Hello World"),
 *     new Widgets.Bin({height: 10}),   // some spacing
 *     new Widgets.Button({
 *       label: "Clicke me please!",
 *
 *       // Use the [css] helper function to elegantly define inline styles:
 *       style: css({
 *         color: 'red',
 *         borderRadius: '10px',
 *       }),
 *
 *       // All widget events are translated to callback properties automatically:
 *       onClick: () => logger.debug("I've been clicked!")
 *     }),
 *     new Widgets.Icon({
 *       iconName: 'emblem-ok-symbolic',
 *
 *       // There are some special callbacks:
 *       onCreated: (icon) => icon.ease({ scale: 1.5 })
 *     }),
 *   ],
 * });
 * ```
 *
 * Keep in mind that while this structure is nested and looks a lot like typical declarative
 * frameworks (e.g. Flutter), there is no inherent declarative reactivity here – the UI is
 * defined once and needs to be manipulated imperatively (or rebuilt and replaced manually).
 */
/**
 * Helper class to manage references to [Clutter.Actor] instances.
 *
 * If the referenced actor is destroyed, the reference will be
 * automatically set to `null` (i.e. unset/disposed).
 */
class Ref {
    _value = null;
    _destroySignalId;
    /**
     * Create a reference with an optional initial value.
     */
    constructor(initialValue) {
        this.set(initialValue ?? null);
    }
    /**
     * Get the actor the reference points to, or `null` if the actor has been
     * destroyed or unset.
     */
    get current() {
        return this._value;
    }
    /**
     * Update the reference to point to the given actor, unset the reference if
     * `null` is passed.
     */
    set(value) {
        if (this._destroySignalId !== undefined && this._value) {
            this._value.disconnect(this._destroySignalId);
        }
        this._value = value;
        this._destroySignalId = value?.connect('destroy', () => this.set(null));
    }
    /**
     * Convenience method to call the given function or closure on the referenced
     * actor only if there is a referenced actor at the moment.
     *
     * Example:
     * ```typescript
     * const myRef = new Ref(myWidget);
     *
     * // Set the widget's opacity only if it has not been destroyed or in another way unset yet:
     * myRef.apply(w => w.opacity = 0.8);
     * ```
     */
    apply(fn) {
        if (this.current) {
            fn(this.current);
        }
    }
    /**
     * Return the current value, or null, and unset/dispose the reference.
     */
    take() {
        const val = this.current;
        this.dispose();
        return val;
    }
    /**
     * The callback-based counterpart to `Ref.take()` – analogous to `Ref.apply(...)`, but
     * unsets/disposes the reference after running the callback.
     */
    applyAndDispose(fn) {
        this.apply(fn);
        this.dispose();
    }
    /**
     * An alias to `Ref.set(null)`.
     *
     * References generally should be unset/disposed of **if** they're used with actors that may
     * outlive the extension.
     *
     * However: Refs to actors managed entirely by the extension do not need to be unset/disposed,
     * since this happens automatically once the actors are destroyed.
     *
     * Notice: References can be reused after being disposed; the name `clear` would be more
     * appropriate, but `dispose` makes Shexli happy :)
     */
    dispose() {
        this.set(null);
    }
}
function filterConfig(config, filterOut) {
    filterOut ??= [
        'ref', 'children', 'child', 'onCreated', 'constraints', /^(on|notify)[A-Z]/, 'styleClass'
    ];
    return filterObject(config, 
    //@ts-ignore
    entry => typeof entry[0] === "string" && (!filterOut.some((filter) => filter instanceof RegExp
        ? filter.test(entry[0])
        : filter === entry[0])));
}
function initWidget(widget, props) {
    // Setup ref, if given:
    if (props.ref)
        props.ref.set(widget);
    // Add constraints, if given:
    props.constraints?.forEach(c => widget.add_constraint(c));
    // Automatically connect signals from the constructor (e.g. `onClicked` or `notifySize`):
    for (const [key, value] of Object.entries(props)) {
        if (/^(on|notify)[A-Z]/.test(key) && typeof value === "function" && key !== "onCreated") {
            const signalName = key
                .replace(/^notify/, 'notify::')
                .replace(/^onCapturedEvent/, "captured-event::")
                .replace(/^onEvent(?=\w)/, "event::")
                .replace(/^onTransitionStopped/, "transition-stopped::")
                .replace(/^on/, "")
                .replace(/(\w)([A-Z])/g, "$1-$2").toLowerCase();
            widget.connect(signalName, value);
        }
    }
    // Transform the given style class (which might be an array or object of classes):
    if (props.styleClass) {
        widget.styleClass = Array.isArray(props.styleClass)
            ? props.styleClass.join(' ')
            : typeof props.styleClass === 'object'
                ? Object.keys(props).filter(k => props.styleClass[k]).join(' ')
                : props.styleClass;
    }
    // Call the special `onCreated` callback, if given:
    const onCreatedRes = props.onCreated?.(widget);
    // Optionally, `onCreated` may return a function to be called when the widget is destroyed:
    if (typeof onCreatedRes === 'function')
        widget.connect('destroy', onCreatedRes);
}
class Button extends St.Button {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        const filteredConfig = filterConfig(config, config.onLongPress ? ['onLongPress'] : []);
        super(filterConfig(filteredConfig));
        initWidget(this, filteredConfig);
        if (config.onLongPress)
            this._setupLongPress(config.onLongPress);
        if (config.child)
            this.child = config.child;
    }
    _setupLongPress(onLongPress) {
        const gesture = new Clutter.LongPressGesture();
        gesture.connect("recognize", () => onLongPress(this));
        this.add_action(gesture);
    }
}
class Icon extends St.Icon {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super(filterConfig(config));
        initWidget(this, config);
    }
}
class Label extends St.Label {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super(filterConfig(config));
        initWidget(this, config);
    }
}
class Bin extends St.Bin {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super(filterConfig(config));
        initWidget(this, config);
        if (config.child)
            this.set_child(config.child);
    }
}
class Box extends St.BoxLayout {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super(filterConfig(config));
        initWidget(this, config);
        config.children?.forEach(c => this.add_child(c));
    }
}
class Row extends St.BoxLayout {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super({
            ...filterConfig(config),
            orientation: Clutter.Orientation.HORIZONTAL,
        });
        initWidget(this, config);
        config.children?.forEach(c => this.add_child(c));
    }
}
class Column extends St.BoxLayout {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super({
            ...filterConfig(config),
            orientation: Clutter.Orientation.VERTICAL,
        });
        initWidget(this, config);
        config.children?.forEach(c => this.add_child(c));
    }
}
class ScrollView extends St.ScrollView {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super({
            ...filterConfig(config)
        });
        initWidget(this, config);
        if (config.child) {
            if ('vadjustment' in config.child) {
                this.set_child(config.child);
            }
            else {
                const s = new St.BoxLayout();
                s.add_child(config.child);
                this.set_child(s);
            }
        }
    }
}
class Entry extends St.Entry {
    static {
        GObject.registerClass(this);
    }
    constructor(config) {
        super(filterConfig(config));
        initWidget(this, config);
    }
}

export { Bin, Box, Button, Column, Entry, Icon, Label, Ref, Row, ScrollView };
