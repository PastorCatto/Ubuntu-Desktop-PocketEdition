import { logger } from './logging.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

/** Enum mapping to the Shell's session mode: */
var SessionMode;
(function (SessionMode) {
    SessionMode["user"] = "user";
    SessionMode["unlockDialog"] = "unlock-dialog";
})(SessionMode || (SessionMode = {}));
class ExtensionFeatureManager {
    pm;
    registry = new Map();
    enabledFeatures = new Map();
    constructor(pm) {
        this.pm = pm;
    }
    /**
     * A utility method to define [ExtensionFeature]s that are optionally automatically enabled/disabled
     * depending on the given [setting] and [sessionModes].
     *
     * All features are automatically destroyed when this [FeatureManager] is destroyed.
     */
    async defineFeature(meta) {
        this.registry.set(meta.name, meta);
        // Check whether the feature should be enabled initially:
        await this._syncFeatureEnabled(meta);
        // Connect to setting changes:
        if (meta.setting) {
            this.pm.connectTo(meta.setting, 'changed', () => this._syncFeatureEnabled(meta));
        }
    }
    /**
     * Get a feature by its type, if enabled.
     */
    getFeature(type) {
        for (let feature of this.enabledFeatures.values()) {
            if (feature instanceof type)
                return feature;
        }
        return null;
    }
    /**
     * Destroy all features that don't support the current session mode, and notify all other
     * features that the session mode has changed.
     */
    async notifySessionModeChanged() {
        // Re-check for each feature whether it should be enabled:
        for (let meta of this.registry.values()) {
            await this._syncFeatureEnabled(meta);
        }
        // Notify all features that are still enabled of the changed session mode, so they
        // might perform whatever action they need to:
        for (let feature of this.enabledFeatures.values()) {
            await feature.notifySessionModeChanged();
        }
    }
    /**
     * Evaluate whether the given feature should be enabled or not, and initialize/destroy it accordingly.
     *
     * This function will not perform any action if the feature is already in the correct state.
     *
     * @return `true` if the feature has been initialized, `false` if it has been destroyed or failed to
     *          initialize, and `null` if no change has been made.
     */
    async _syncFeatureEnabled(meta) {
        const isEnabled = this.enabledFeatures.has(meta.name);
        let shouldBeEnabled = !meta.setting || meta.setting.get();
        // If `meta` has session modes set, but the current session mode is not listed there,
        // the feature must be disabled:
        if (shouldBeEnabled) {
            const modes = meta.sessionModes ?? [SessionMode.user];
            shouldBeEnabled = modes.includes(Main.sessionMode.currentMode) || modes.includes(Main.sessionMode.parentMode);
        }
        if (shouldBeEnabled && !isEnabled) {
            // Enable the feature:
            const feature = await this._tryInitializeFeature(meta);
            return feature != null;
        }
        else if (!shouldBeEnabled && isEnabled) {
            // Disable the feature:
            this._destroyFeature(meta);
            return false;
        }
        return null;
    }
    /**
     * Initialize the given feature, and add it to [this.enabledFeatures]
     *
     * If an error occurs, the feature is disabled and a notification is shown.
     *
     * @return The initialized feature, or `null`, if initialization failed.
     */
    async _tryInitializeFeature(meta) {
        // Make sure no feature gets dropped without being properly destroyed:
        this._destroyFeature(meta);
        try {
            // Create the feature instance, and pass it its dedicated child [PatchManager]:
            const feature = await meta.create(this.pm.fork(meta.name));
            await feature.initialize();
            this.enabledFeatures.set(meta.name, feature);
            return feature;
        }
        catch (e) {
            logger.error(`Error while activating feature "${meta.name}":`, e);
            // Disable the feature for future launches:
            meta.setting?.set(false);
            // Show a notification:
            import('../utils/showFeatureInitializationErrorNotification.js')
                .then(m => m.showFeatureInitializationFailedNotification(meta.name, e));
        }
        return null;
    }
    /**
     * Destroy the feature identified by [meta.name] if it is currently initialized.
     */
    _destroyFeature(meta) {
        this.enabledFeatures.get(meta.name)?.destroy();
        this.enabledFeatures.delete(meta.name);
    }
    /**
     * Destroy all features.
     */
    destroy() {
        // Destroy features in reverse order, to be consistent with [PatchManager]:
        for (const feature of [...this.enabledFeatures.values()].reverse()) {
            feature.destroy();
        }
        this.enabledFeatures.clear();
        this.registry.clear();
        // Destroy our [PatchManager], and with it all descendents:
        this.pm.destroy();
    }
}

export { ExtensionFeatureManager, SessionMode };
