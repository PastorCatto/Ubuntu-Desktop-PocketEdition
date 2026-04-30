import * as Keyboard from 'resource:///org/gnome/shell/ui/keyboard.js';
import { getInputSourceManager } from 'resource:///org/gnome/shell/ui/status/keyboard.js';
import ExtensionFeature from '../../core/extensionFeature.js';
import { findAllActorsBy } from '../../utils/utils.js';
import { extractKeyPrototype } from './_oskUtils.js';
import { GestureRecognizer } from '../../utils/gestures/gestureRecognizer.js';
import Clutter from 'gi://Clutter';
import { Ref, Label } from '../../utils/ui/widgets.js';
import { settings } from '../../settings.js';

// @ts-ignore
class OskSpaceBarIMESwitchingFeature extends ExtensionFeature {
    recognizer;
    subpm = null;
    keyboard;
    constructor(pm, keyboard) {
        super(pm);
        // We can use one shared gesture recognizer since only one space bar will only ever be
        // visible at a time:
        this.recognizer = new GestureRecognizer({
            onGestureEnded: state => {
                if (state.finalMotionDirection?.axis === 'horizontal') {
                    const d = state.finalMotionDirection.direction === 'left'
                        ? 'backward'
                        : 'forward';
                    this._activateInputSource(this._getNextInputSource(d));
                }
            }
        });
        if (keyboard != null) {
            this.onNewKeyboard(keyboard);
        }
        this.pm.connectTo(settings.osk.spaceBarIMESwitching.indicatorMode, 'changed', () => {
            this.onNewKeyboard(this.keyboard);
        });
        // Recreate our patches whenever the keyboard is rebuilt:
        const self = this;
        this.pm.appendToMethod(Keyboard.Keyboard.prototype, '_updateKeys', function () {
            self.onNewKeyboard(this);
        });
    }
    onNewKeyboard(keyboard) {
        this.keyboard = keyboard;
        this._patchKeyboard();
    }
    _patchKeyboard() {
        // We use a separate [PatchManager] for each new keyboard, that we destroy here, to ensure to never
        // patch a keyboard twice:
        this.subpm?.destroy();
        this.subpm = this.pm.fork();
        const keyProto = extractKeyPrototype(this.keyboard);
        // There are multiple space bars, one for each `KeyContainer`:
        const spaceBars = findAllActorsBy(this.keyboard, a => keyProto.isPrototypeOf(a) && a.keyButton.label === ' ');
        spaceBars.forEach(b => this._patchSpaceBar(b));
    }
    _patchSpaceBar(key) {
        const keyButton = key.keyButton;
        // Create and add our gesture:
        const gesture = this.recognizer.createPanGesture({
            panAxis: Clutter.PanAxis.X,
        });
        this.subpm.patch(() => {
            keyButton.add_action_full('touchup-quick-ime-switching', Clutter.EventPhase.BUBBLE, gesture);
            return () => keyButton.remove_action(gesture);
        });
        // OSK keys use raw touch events by default, which conflicts with our gesture handling. Thus,
        // we'll disable the raw touch event listener, and instead make functional the built-in
        // [Clutter.ClickGesture] that [St.Button]s have anyway:
        const clickGesture = keyButton.get_actions()[0];
        this.subpm.patchSignalHandler(keyButton, 'touch-event', () => null);
        this.subpm.connectTo(clickGesture, 'may-recognize', () => {
            key._press(keyButton, ' ');
            keyButton.add_style_pseudo_class('active');
            return true;
        });
        this.subpm.connectTo(clickGesture, 'recognize', () => {
            key._release(keyButton, ' ');
            keyButton.remove_style_pseudo_class('active');
        });
        // Add the IME indicator widget to the space bar:
        this.subpm.patch(() => {
            const indicator = new Ref(this._buildIMEIndicator());
            keyButton.add_child(indicator.current);
            return () => indicator.current?.destroy();
        });
    }
    _buildIMEIndicator() {
        const { sources, currentSource } = this._getInputSources();
        const mode = settings.osk.spaceBarIMESwitching.indicatorMode.get();
        let markup = '';
        if (mode === 'all') {
            markup = sources
                .map(s => s === currentSource ? `<b>${s.shortName}</b>` : s.shortName)
                .join(" · ");
        }
        else if (mode === 'current') {
            markup = currentSource.displayName;
        }
        else if (mode === 'none') {
            markup = "";
        }
        else ;
        return new Label({
            styleClass: "touchup-osk-ime-indicator",
            text: markup,
            onCreated: widget => widget.clutterText.useMarkup = true,
        });
    }
    _getNextInputSource(direction = 'forward') {
        const { sources, currentSource } = this._getInputSources();
        const currIdx = sources.indexOf(currentSource);
        const d = direction === 'forward' ? 1 : -1;
        const newIdx = (sources.length + currIdx + d) % sources.length;
        return sources[newIdx];
    }
    _getInputSources() {
        const manager = getInputSourceManager();
        // InputManager.inputSources is an object with int keys, for convenience we'll convert it to an array:
        const sourcesObj = manager.inputSources;
        const sources = Object.keys(sourcesObj)
            .sort()
            .map(k => sourcesObj[k]);
        const currentSource = manager.currentSource;
        return { sources, currentSource };
    }
    _activateInputSource(source) {
        source.activate(true);
    }
}

export { OskSpaceBarIMESwitchingFeature };
