import GObject from 'gi://GObject';
import { InjectionManager } from 'resource:///org/gnome/shell/extensions/extension.js';
import { repr } from './logging.js';
import { Ref } from '../utils/ui/widgets.js';
import Clutter from 'gi://Clutter';

/**
 * Class to manage global changes ("patches") that need to be undone
 * when the extension is disabled.
 */
class PatchManager {
    debugName;
    _parent;
    _children = [];
    _injectionManager = new InjectionManager();
    _patches = [];
    _isDestroyed = false;
    constructor(debugName) {
        this.debugName = debugName;
    }
    /**
     * Apply a patch. The callback peforming the patch is called immediately and must
     * return another function to undo the patch again.
    */
    patch(func, debugName) {
        const patch = this.registerPatch(func, debugName);
        patch.enable();
        return patch;
    }
    /**
     * Add a patch without automatically applying it. Otherwise, same
     * as [PatchManager.patch(...)]
     */
    registerPatch(func, debugName) {
        this._patches.push(new Patch({
            enable: func,
            debugName: this._generatePatchDebugName(debugName),
        }));
        return this._patches.at(-1);
    }
    /**
     * Automatically destroy any object with a [destroy] method when the [PatchManager] is
     * disabled or destroyed.
     */
    autoDestroy(instance, debugName) {
        this.patch(() => {
            let ref = new Ref(instance);
            return () => ref.take()?.destroy();
        }, debugName ?? `autoDestroy:${instance.constructor.name}`);
        return instance;
    }
    /**
     * Connect to a signal from any GObject/widget and automatically disconnect when the [PatchManager]
     * is disabled or destroyed.
     */
    connectTo(instance, signal, handler, debugName) {
        const patch = this.patch(() => {
            const signalIds = [
                instance.connect(signal, handler)
            ];
            // If the given instance is a [Clutter.Actor], we drop this patch on actor destruction as it is
            // an error to disconnect from a signal on a destroyed actor (which we would do if we would disable
            // the patch):
            if (instance instanceof Clutter.Actor) {
                signalIds.push(instance.connect('destroy', () => this.drop(patch)));
            }
            return () => signalIds.forEach(s => instance.disconnect(s));
        }, debugName ?? `connectTo(${instance.constructor.name}:${signal})`);
        return patch;
    }
    /**
     * Set an objects property to a certain value and automatically reset it to the original value upon
     * [PatchManager] destruction or disabling.
     */
    setProperty(instance, prop, value, debugName) {
        const patch = this.patch(() => {
            const originalValue = instance[prop];
            instance[prop] = value;
            // If the given instance is a [Clutter.Actor], we drop this patch on actor destruction as it is
            // an error to set a property on a destroyed actor (which we would do if we would disable the patch):
            let destroySignalId = null;
            if (instance instanceof Clutter.Actor) {
                destroySignalId = instance.connect('destroy', () => this.drop(patch));
            }
            return () => {
                instance[prop] = originalValue;
                if (destroySignalId !== null) {
                    instance.disconnect(destroySignalId);
                }
            };
        }, debugName ?? `setProperty(${instance.constructor?.name ?? repr(instance)}, '${prop.toString()}', ${repr(value)})`);
        return patch;
    }
    /**
     * Call the given [callback] with the given [setting]'s value and then whenever it is changed.
     */
    bindSetting(setting, callback) {
        callback(setting.get());
        return this.connectTo(setting, 'changed', () => callback(setting.get()));
    }
    patchSignalHandler(instance, signalId, handler, debugName) {
        if (Array.isArray(signalId)) {
            return new MultiPatch({
                patches: signalId.map(s => this.patchSignalHandler(instance, s, handler, `${debugName}#signal(${instance.constructor.name}:${signalId})`)),
                debugName: this._generatePatchDebugName(debugName),
            });
        }
        else {
            return this.patch(() => {
                //@ts-ignore
                const originalHandler = GObject.signal_handler_find(instance, { signalId });
                GObject.signal_handler_block(instance, originalHandler);
                const newHandler = instance.connect(signalId, handler);
                return () => {
                    GObject.signal_handler_disconnect(instance, newHandler);
                    GObject.signal_handler_unblock(instance, originalHandler);
                };
            }, debugName);
        }
    }
    patchMethod(prototype, methodName, method, debugName) {
        if (Array.isArray(methodName)) {
            return new MultiPatch({
                patches: methodName.map(m => this.patchMethod(prototype, m, function (originalMethod, ...args) {
                    method.call(this, originalMethod, m, ...args);
                }, `${debugName}#method(${prototype.constructor.name}:${m})`)),
                debugName: this._generatePatchDebugName(debugName),
            });
        }
        else {
            return this.patch(() => {
                this._injectionManager.overrideMethod(prototype, methodName, (orig) => {
                    return function (...args) {
                        return method.call(this, orig.bind(this), ...args);
                    };
                });
                return () => this._injectionManager.restoreMethod(prototype, methodName);
            }, debugName);
        }
    }
    appendToMethod(prototype, methodName, method, debugName) {
        if (Array.isArray(methodName)) {
            return new MultiPatch({
                patches: methodName.map(m => this.appendToMethod(prototype, m, method, `${debugName}#append-to-method(${prototype.constructor.name}:${m})`)),
                debugName: this._generatePatchDebugName(debugName),
            });
        }
        else {
            return this.patchMethod(prototype, methodName, function (orig, ...args) {
                const res = orig.call(this, ...args);
                method.call(this, ...args);
                return res;
            }, debugName);
        }
    }
    /**
     * Undo and delete all patches made so far.
     *
     * This function should only be called if the [PatchManager] is not going to be used anymore.
     */
    destroy() {
        if (this._isDestroyed)
            return;
        // Remove this PM from its parent:
        if (this._parent?._children.includes(this)) {
            this._parent?._children.splice(this._parent._children.indexOf(this), 1);
        }
        // Destroy all descendent PMs, in reverse order - i.e. those descendents that where
        // created first will be destroyed last.
        //
        // Note: We use a while loop here to avoid destroying PMs again that have been destroyed
        // manually by the user during this process.
        while (this._children.length > 0) {
            this._children.pop().destroy();
        }
        // Undo all patches from this PM, in reverse order - i.e. those descendents that where
        // created first will be destroyed last, to create an "encapsulation" effect:
        // If patch A depends on another patch B that was made before it, patch B's `disable`
        // function might still need patch A, but patch A will not need patch B, since it was
        // already made before patch B even existed. Thus, we do it this way:
        //      create A -> create B -> disable B -> disable A
        // => All patches encapsulate those that are made after them.
        this._patches.toReversed().forEach(p => p.disable());
        this._patches = [];
        // This should be a noop, as all patches already restored their original method during
        // unpatching, but we'll still clear the [InjectionManager] here for completeness:
        this._injectionManager.clear();
        this._isDestroyed = true;
    }
    /**
     * Undo all patches made so far, but keep them in store for a potential call to [enable]
     */
    disable() {
        if (this._isDestroyed)
            return;
        this._children.toReversed().forEach(c => c.disable());
        this._patches.toReversed().forEach(p => p.disable());
        // This should be a noop, as all patches already restored their original method during
        // unpatching, but we'll still clear the [InjectionManager] here for completeness:
        this._injectionManager.clear();
    }
    /**
     * Enable all disabled patches.
     */
    enable() {
        this._patches.forEach(p => p.enable());
        this._children.forEach(c => c.enable());
    }
    /**
     * Drops a patch from the list of patches maintained by this [PatchManager] without
     * disabling it. This is required in rare cases.
     *
     * Only use this when you are certain you know what you're doing.
     *
     * Returns the dropped patch or `null` if it is not managed by this PatchManager.
     */
    drop(patch) {
        const idx = this._patches.findIndex(p => p === patch);
        if (idx === -1)
            return null;
        return this._patches.splice(idx, 1)[0];
    }
    /**
     * Create a descendent [PatchManager].
     *
     * This child [PatchManager] will react to any call to [destroy], [disable] and [enable]
     * on any parent [PatchManager] and will forward those calls to its own descendents, should
     * it be forked again. This allows for a nice, tree structure and a consistent interface
     * for managing patches.
     * @param debugName An optional label used for debug log messages
     */
    fork(debugName) {
        const instance = new PatchManager(this.debugName
            ? `${this.debugName}/${debugName ?? this._children.length + 1}`
            : debugName);
        instance._parent = this;
        this._children.push(instance);
        return instance;
    }
    _patchNameCounter = 0;
    _generatePatchDebugName(debugName) {
        return `${this.debugName}:${debugName ?? `#${this._patchNameCounter++}`}`;
    }
}
class Patch {
    debugName;
    _enableCallback;
    _disableCallback;
    _isEnabled = false;
    constructor(props) {
        this._enableCallback = props.enable;
        this.debugName = props.debugName ?? null;
    }
    disable(force = false) {
        if (!force && !this.isEnabled)
            return;
        // logger.debug(` - Disabling patch ${this.debugName}`);
        this._disableCallback?.call(this);
        this._isEnabled = false;
    }
    enable(force = false) {
        if (!force && this.isEnabled)
            return;
        // logger.debug(` - Enabling patch ${this.debugName}`);
        this._disableCallback = this._enableCallback();
        this._isEnabled = true;
    }
    setEnabled(enabled, force = false) {
        if (enabled) {
            this.enable(force);
        }
        else {
            this.disable(force);
        }
    }
    get isEnabled() {
        return this._isEnabled;
    }
}
class MultiPatch extends Patch {
    _patches;
    constructor(props) {
        super({
            enable: () => {
                props.patches.forEach(p => p.enable());
                return () => props.patches.forEach(p => p.disable());
            },
            debugName: props.debugName,
        });
        this._patches = props.patches;
    }
    get isEnabled() {
        return this._patches.every(p => p.isEnabled);
    }
    enable(force = false) {
        this._patches.forEach(p => p.enable(force));
    }
    disable(force = false) {
        this._patches.forEach(p => p.disable(force));
    }
}

export { MultiPatch, Patch, PatchManager };
