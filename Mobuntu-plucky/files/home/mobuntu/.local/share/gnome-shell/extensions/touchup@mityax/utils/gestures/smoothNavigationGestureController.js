import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { OverviewGestureController, WorkspaceGestureController } from './navigationGestureControllers.js';
import { SmoothFollower, SmoothFollowerLane } from './smoothFollower.js';
import { oneOf } from '../utils.js';

/**
 * This class fuses an [OverviewGestureController] and a [WorkspaceGestureController] with
 * a [SmoothFollower] to provide a unified, two-dimensional navigation gesture controller
 * that smoothly follows the users gesture.
 *
 * Smooth following provides a better navigation experience since gestures are usually updated
 * at a lower rate than the screen refresh rate.
 */
class SmoothNavigationGestureController {
    _overviewController;
    _wsController;
    _smoothFollower;
    _gesturesStarted = false;
    constructor() {
        this._overviewController = new OverviewGestureController();
        this._wsController = new WorkspaceGestureController({
            monitorIndex: Main.layoutManager.primaryIndex
        });
        // Use a [SmoothFollower] to make the gestures asynchronously follow the users finger:
        this._smoothFollower = new SmoothFollower([
            new SmoothFollowerLane({
                onUpdate: value => this._overviewController.gestureProgress(value - this._overviewController.initialProgress),
                smoothTime: 0.085,
            }),
            new SmoothFollowerLane({
                onUpdate: value => this._wsController.gestureProgress(value - this._wsController.initialProgress),
                smoothTime: 0.055,
            })
        ]);
    }
    gestureBegin() {
        if (!this._gesturesStarted) {
            this._gesturesStarted = true;
            this._startGestures();
        }
    }
    gestureProgress(overviewProgress, workspaceProgress) {
        if (!this._gesturesStarted) {
            this._gesturesStarted = true;
            this._startGestures();
        }
        this._smoothFollower.update((overviewLane, wsLane) => {
            overviewLane.target = this._overviewController.initialProgress + overviewProgress;
            wsLane.target = this._wsController.initialProgress + workspaceProgress;
        });
    }
    gestureEnd(direction) {
        this._stopGestures();
        this._gesturesStarted = false;
        this._overviewController.gestureEnd(oneOf(direction, ['up', 'down']));
        this._wsController.gestureEnd(oneOf(direction, ['left', 'right']));
    }
    gestureCancel() {
        this._stopGestures();
        this._gesturesStarted = false;
        this._overviewController.gestureCancel();
        this._wsController.gestureCancel();
    }
    get overviewBaseDist() {
        return this._overviewController.baseDist;
    }
    get workspaceBaseDist() {
        return this._wsController.baseDist;
    }
    set monitorIndex(value) {
        this._wsController.monitorIndex = value;
    }
    get monitorIndex() {
        return this._wsController.monitorIndex;
    }
    _startGestures() {
        this._overviewController.gestureBegin();
        this._wsController.gestureBegin();
        this._smoothFollower.start((overviewLane, wsLane) => {
            overviewLane.currentValue = this._overviewController.initialProgress;
            wsLane.currentValue = this._wsController.initialProgress;
        });
    }
    _stopGestures() {
        this._smoothFollower.stop();
    }
    destroy() {
        this._smoothFollower.stop();
        this._overviewController.destroy();
        this._wsController.destroy();
    }
}

export { SmoothNavigationGestureController };
