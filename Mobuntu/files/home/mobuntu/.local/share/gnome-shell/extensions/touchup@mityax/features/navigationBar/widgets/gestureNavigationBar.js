import St from 'gi://St';
import Clutter from 'gi://Clutter';
import { IntervalRunner } from '../../../utils/intervalRunner.js';
import { clamp } from '../../../utils/utils.js';
import Shell from 'gi://Shell';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { calculateLuminance } from '../../../utils/colors.js';
import BaseNavigationBar from './baseNavigationBar.js';
import { Bin } from '../../../utils/ui/widgets.js';
import { GestureRecognizer } from '../../../utils/gestures/gestureRecognizer.js';
import { Delay } from '../../../utils/delay.js';
import GObject from 'gi://GObject';
import Mtk from 'gi://Mtk';
import { settings } from '../../../settings.js';
import { SmoothNavigationGestureController } from '../../../utils/gestures/smoothNavigationGestureController.js';
import { IdleRunner } from '../../../utils/idleRunner.js';

/**
 * Area reserved on the left side of the navbar in which a swipe up opens the OSK,
 * in logical pixels
 */
const LEFT_EDGE_OFFSET = 100;
/**
 * The full height of the navigation bar (not just the pill),
 * in logical pixels
 */
const NAV_BAR_HEIGHT = 22;
class GestureNavigationBar extends BaseNavigationBar {
    styleClassUpdateInterval;
    _isWindowNear = false;
    gestureManager;
    constructor(props) {
        super({ reserveSpace: props.reserveSpace });
        this.styleClassUpdateInterval = new IntervalRunner(500, this.updateStyleClasses.bind(this));
        this.gestureManager = new NavigationBarGestureManager({
            edgeThreshold: this.computeHeight(),
        });
        this.setInvisibleMode(props.invisibleMode);
        this.connect('notify::visible', _ => this._updateStyleClassIntervalEnabled());
        this.connect('notify::reserve-space', _ => {
            this._updateStyleClassIntervalEnabled();
            void this.updateStyleClasses();
        });
    }
    _buildActor() {
        return new _EventPassthroughActor({
            name: 'touchup-navbar',
            styleClass: 'touchup-navbar touchup-navbar--transparent bottom-panel',
            reactive: true,
            trackHover: true,
            canFocus: true,
            layoutManager: new Clutter.BinLayout(),
            notifyMapped: () => {
                this.gestureManager.setEnabled(this.actor.mapped);
                if (this.actor.mapped) {
                    this.styleClassUpdateInterval.scheduleOnce();
                }
            },
            child: this.pill = new Bin({
                name: 'touchup-navbar__pill',
                styleClass: 'touchup-navbar__pill',
                yAlign: Clutter.ActorAlign.CENTER,
                xAlign: Clutter.ActorAlign.CENTER,
            }),
        });
    }
    onUpdateToSurrounding(surrounding) {
        this._isWindowNear = surrounding.isWindowNear && !surrounding.isInOverview;
        if (!this.reserveSpace) {
            let newInterval = surrounding.isInOverview || !surrounding.isWindowNear ? 3000 : 500;
            // if a window is moved onto/away from the navigation bar or overview is toggled, schedule update soonish:
            this.styleClassUpdateInterval.scheduleOnce(250);
            this.styleClassUpdateInterval.setInterval(newInterval);
        }
        else {
            void this.updateStyleClasses();
        }
    }
    computeHeight() {
        const sf = St.ThemeContext.get_for_stage(global.stage).scaleFactor;
        return NAV_BAR_HEIGHT * sf;
    }
    computePillSize() {
        const sf = St.ThemeContext.get_for_stage(global.stage).scaleFactor;
        return {
            width: clamp(this.monitor.width * 0.25, 70 * sf, 330 * sf),
            height: Math.floor(Math.min(this.computeHeight() * 0.8, 6 * sf, this.computeHeight() - 2)),
        };
    }
    onBeforeReallocate() {
        this.actor.set_height(this.isInInvisibleMode ? 0 : this.computeHeight());
        this.pill.set_size(this.computePillSize().width, this.computePillSize().height);
        this.gestureManager.setEdgeThreshold(this.computeHeight());
    }
    setMonitor(monitorIndex) {
        super.setMonitor(monitorIndex);
        this.gestureManager.setMonitor(monitorIndex);
    }
    updateStyleClasses() {
        if (this.reserveSpace && this._isWindowNear) {
            // Make navbar opaque (black or white, based on shell theme brightness):
            this.actor.remove_style_class_name('touchup-navbar--transparent');
            this.pill.remove_style_class_name('touchup-navbar__pill--dark');
        }
        else {
            // Make navbar transparent:
            this.actor.add_style_class_name('touchup-navbar--transparent');
            // Adjust pill brightness:
            this.findBestPillBrightness().then(brightness => {
                // Avoid doing anything in case the callback has been stopped during the time
                // `findBestPillBrightness` was running:
                if (!this.styleClassUpdateInterval.enabled)
                    return;
                if (brightness == 'dark') {
                    this.pill.add_style_class_name('touchup-navbar__pill--dark');
                }
                else {
                    this.pill.remove_style_class_name('touchup-navbar__pill--dark');
                }
            });
        }
    }
    /**
     * Find the best pill brightness by analyzing what's on the screen behind the pill
     */
    findBestPillBrightness() {
        return new Promise((resolve) => {
            // Capture the pill's surrounding in a GLib idle task, to prevent it from running in bad scenarios.
            //
            // Example: While the screen is being rotated by the Shell, this can cause Shell crashes (e.g. because
            // it could result in capturing a screenshot outside the screens dimensions). In JS, we don't have
            // precise enough control over what runs when to ensure this in another way.
            IdleRunner.once(() => {
                if (!this.styleClassUpdateInterval.enabled)
                    return;
                let rect = this.pill.get_transformed_extents();
                // Get the color at one pixel centered above the navigation bar using Shell.Screenshot:
                // Notice: See the bottom of this file for other (non-working) approaches.
                new Shell.Screenshot()
                    .pick_color(rect.get_x() + rect.get_width() * 0.5, rect.get_y() - 2)
                    .then((res) => {
                    const color = res[0];
                    const luminance = calculateLuminance(color.red, color.green, color.blue);
                    resolve(luminance > 0.5 ? 'dark' : 'light');
                });
            });
        });
    }
    _updateStyleClassIntervalEnabled() {
        this.styleClassUpdateInterval.setEnabled(this.isVisible && !this.reserveSpace);
    }
    /**
     * In invisible mode, the navigation bars height and opacity are set to 0; this is because
     * we cannot use the `visible` property since this would infer with the Shell's own handling
     * of that (in `Main.layoutManager.addTopChrome`)
     */
    setInvisibleMode(invisible) {
        // We use opacity here instead of the actors `visible` property since [LayoutManager.addTopChrome] uses the
        // `visible` property itself which would interfere with this.
        this.actor.opacity = invisible ? 0 : 255;
        // Reallocate, to adjust the navbar height to invisible mode:
        this.reallocate();
    }
    get isInInvisibleMode() {
        return this.actor.opacity === 0;
    }
    destroy() {
        this.styleClassUpdateInterval.stop();
        this.gestureManager.destroy();
        super.destroy();
    }
}
class NavigationBarGestureManager {
    _gesture;
    _recognizer;
    _navigationGestureController;
    /**
     * This virtual input device is used to emulate touch events in click-through-navbar scenarios.
     */
    _virtualTouchscreenDevice;
    _scaleFactor;
    _hasStarted = false;
    _isKeyboardGesture = false;
    _edgeThreshold;
    _gestureSignalId; // notice: only for shexli
    constructor(props) {
        this._scaleFactor = St.ThemeContext.get_for_stage(global.stage).scaleFactor;
        this._edgeThreshold = props.edgeThreshold;
        // The controller used to actually perform the navigation gestures:
        this._navigationGestureController = new SmoothNavigationGestureController();
        // Our [GestureRecognizer] to interpret the gestures:
        this._recognizer = new GestureRecognizer({
            onGestureProgress: state => this._onGestureProgress(state),
            onGestureCompleted: state => this._onGestureCompleted(state),
            onGestureCanceled: _ => this._onGestureCanceled(),
        });
        // Action that listens to appropriate events on the stage:
        this._gesture = this._recognizer.createPanGesture();
        this._gestureSignalId = this._gesture.connect('should-handle-sequence', (_, e) => this._shouldHandleSequence(e));
        global.stage.add_action_full('touchup-navigation-bar', Clutter.EventPhase.CAPTURE, this._gesture);
        // To emit virtual events:
        this._virtualTouchscreenDevice = Clutter
            .get_default_backend()
            .get_default_seat()
            .create_virtual_device(Clutter.InputDeviceType.TOUCHSCREEN_DEVICE);
    }
    setMonitor(monitorIndex) {
        this._navigationGestureController.monitorIndex = monitorIndex;
    }
    setEdgeThreshold(edgeThreshold) {
        this._edgeThreshold = edgeThreshold;
    }
    setEnabled(enabled) {
        this._gesture.enabled = enabled;
    }
    _getMonitorRect(x, y) {
        const rect = new Mtk.Rectangle({ x: x - 1, y: y - 1, width: 1, height: 1 });
        const monitorIndex = global.display.get_monitor_index_for_rect(rect);
        return global.display.get_monitor_geometry(monitorIndex);
    }
    _shouldHandleSequence(event) {
        // If we're already during a gesture, capture all other events too to prevent other interactions:
        if (this._gesture.state === Clutter.GestureState.RECOGNIZING) {
            return true;
        }
        // If we're not yet during a gesture, only capture sequences that start on the navigation bar area:
        const [x, y] = event.get_coords();
        const monitorRect = this._getMonitorRect(x, y);
        return y > monitorRect.y + monitorRect.height - this._edgeThreshold;
    }
    _onGestureProgress(state) {
        if (!this._hasStarted) {
            this._startGestures(state);
        }
        if (this._isKeyboardGesture) {
            Main.keyboard._keyboard.gestureProgress(-state.totalMotionDelta.y);
        }
        else {
            const baseDistFactor = settings.navigationBar.gesturesBaseDistFactor.get() / 10.0;
            const d = state.totalMotionDelta;
            this._navigationGestureController.gestureProgress(-d.y / (this._navigationGestureController.overviewBaseDist * baseDistFactor), -d.x / (this._navigationGestureController.workspaceBaseDist * 0.62));
        }
    }
    _startGestures(state) {
        this._hasStarted = true;
        this._isKeyboardGesture = false;
        if (Main.keyboard.visible) {
            // Close the keyboard if it's visible:
            Main.keyboard._keyboard
                ? Main.keyboard._keyboard.close(true) // immediate = true
                : Main.keyboard.close();
        }
        else if (Main.keyboard._keyboard
            && state.pressCoordinates.x < LEFT_EDGE_OFFSET * this._scaleFactor
            && state.firstMotionDirection?.axis === 'vertical') {
            this._isKeyboardGesture = true;
        }
        if (!this._isKeyboardGesture) {
            this._navigationGestureController.gestureBegin();
        }
    }
    _onGestureCompleted(state) {
        const direction = state.lastMotionDirection?.direction ?? null;
        if (state.isTap) {
            this._navigationGestureController.gestureCancel();
            this._virtualTouchscreenDevice.notify_touch_down(state.events[0].timeUS, 0, state.pressCoordinates.x, state.pressCoordinates.y);
            Delay.ms(45).then(() => {
                this._virtualTouchscreenDevice.notify_touch_up(state.events.at(-1).timeUS, 0);
            });
        }
        else if (this._isKeyboardGesture) {
            if (direction === 'up') {
                Main.keyboard._keyboard?.gestureActivate();
            }
            else {
                Main.keyboard._keyboard?.gestureCancel();
            }
        }
        else {
            this._navigationGestureController.gestureEnd(direction);
        }
        this._hasStarted = false;
    }
    _onGestureCanceled() {
        Main.keyboard._keyboard?.gestureCancel();
        this._navigationGestureController.gestureCancel();
        this._hasStarted = false;
    }
    destroy() {
        global.stage.remove_action(this._gesture);
        this._gesture.disconnect(this._gestureSignalId); // notice: only for shexli, disconnect is not needed (no class-external references to gesture, gesture is removed from the stage on disabling)
        this._navigationGestureController.destroy();
    }
}
/**
 * An actor that is invisible to events, i.e. passes them through to any actors below.
 */
class _EventPassthroughActor extends Bin {
    static {
        GObject.registerClass(this);
    }
    vfunc_pick(pick_context) {
        // By not making any call to this.pick_box(...) here, we make this actor pass through all events to
        // any actor potentially below it. Therefore, this actor is only a visuals and does not react to
        // events.
        return;
    }
}

export { GestureNavigationBar as default };
