import { findActorBy } from '../../utils/utils.js';

/**
 * Extracts the prototype of [Keyboard.Key] from the given [Keyboard.Keyboard] instance
 * since it is not exported by the Shell.
 */
function extractKeyPrototype(keyboard) {
    if (_keyProtoCache != null)
        return _keyProtoCache;
    let r = findActorBy(keyboard._aspectContainer, a => a.constructor.name === 'Key' && !!Object.getPrototypeOf(a));
    _keyProtoCache = r !== null
        ? Object.getPrototypeOf(r)
        : null;
    return _keyProtoCache;
}
let _keyProtoCache = null;
/**
 * Check whether the given actor is an OSK Key (an instance of [Keyboard.Key]) – this utility
 * is needed because the class is not exported by the Shell.
 */
function isKeyboardKey(value) {
    if (_keyProtoCache == null)
        return value.constructor.name === 'Key';
    return _keyProtoCache.isPrototypeOf(value);
}

export { extractKeyPrototype, isKeyboardKey };
