import { GestureRecognizer } from '../../utils/gestures/gestureRecognizer.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import Clutter from 'gi://Clutter';
import ExtensionFeature from '../../core/extensionFeature.js';
import { SmoothNavigationGestureController } from '../../utils/gestures/smoothNavigationGestureController.js';

class OverviewBackgroundGesturesFeature extends ExtensionFeature {
    static clutterGestureName = "touchup-overview-background-gesture";
    gesture;
    _navigationGestureController;
    constructor(pm) {
        super(pm);
        this._navigationGestureController = new SmoothNavigationGestureController();
        const recognizer = new GestureRecognizer({
            onGestureStarted: _ => this._navigationGestureController.gestureBegin(),
            onGestureProgress: state => {
                const d = state.totalMotionDelta;
                this._navigationGestureController.gestureProgress(-d.y / (this._navigationGestureController.overviewBaseDist * 0.25), -d.x / (this._navigationGestureController.workspaceBaseDist * 0.62));
            },
            onGestureCompleted: state => {
                this._navigationGestureController.gestureEnd(state.finalMotionDirection?.direction);
            },
            onGestureCanceled: _ => this._navigationGestureController.gestureCancel(),
        });
        this.gesture = recognizer.createPanGesture();
        this.pm.patch(() => {
            Main.overview._overview._controls.add_action_full(OverviewBackgroundGesturesFeature.clutterGestureName, Clutter.EventPhase.BUBBLE, this.gesture);
            return () => Main.overview._overview._controls.remove_action(this.gesture);
        });
        this.pm.setProperty(Main.overview._overview._controls, 'reactive', true);
    }
    canNotCancel(otherGesture) {
        this.gesture.can_not_cancel(otherGesture);
    }
    destroy() {
        this._navigationGestureController.destroy();
        super.destroy();
    }
}

export { OverviewBackgroundGesturesFeature };
