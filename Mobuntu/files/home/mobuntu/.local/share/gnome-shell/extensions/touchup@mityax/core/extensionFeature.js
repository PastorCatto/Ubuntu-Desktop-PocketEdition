import { ExtensionFeatureManager } from './extensionFeatureManager.js';

/**
 * Base class for each feature of this extension.
 */
class ExtensionFeature {
    pm;
    subFeatureManager;
    constructor(patchManager) {
        this.pm = patchManager;
        this.subFeatureManager = new ExtensionFeatureManager(this.pm.fork("fm"));
    }
    /**
     * Subclasses can overwrite this to perform initialization requiring async code. This will be called
     * by the [FeatureManager] immediately after the constructor has been invoked, and will be awaited
     * by the enclosing context before continuing.
     */
    async initialize() { }
    /**
     * Adds a sub-feature to this extension feature and optionally binds (= automatically creates and destroys) it
     * to the given setting.
     *
     * If no setting is given, the sub-feature is created immediately and destroyed when this extension feature
     * is destroyed.
     */
    async defineSubFeature(meta) {
        await this.subFeatureManager.defineFeature(meta);
    }
    getSubFeature(type) {
        return this.subFeatureManager.getFeature(type);
    }
    destroy() {
        this.pm.destroy();
        // Destroy all sub-features (this has been done already by the PatchManager, but is explicitly done
        // here again to not make things unnecessarily complicated for reviewers):
        this.subFeatureManager.destroy();
    }
    /**
     * Called when the Shells session mode has changed, without the extension being disabled
     * and re-enabled.
     *
     * Important: When overriding this method, make sure to call the super classes method to
     * ensure that all subfeatures are properly notified too.
     */
    async notifySessionModeChanged() {
        await this.subFeatureManager.notifySessionModeChanged();
    }
}

export { ExtensionFeature as default };
