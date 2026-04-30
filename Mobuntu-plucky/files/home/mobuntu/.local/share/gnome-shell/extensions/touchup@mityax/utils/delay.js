import GLib from 'gi://GLib';

/**
 * Returns a promise that resolves after a specified duration (using GLib.timeout_add) or can be canceled.
 *
 * @param durationMs - The duration of the delay in milliseconds.
 * @param onCancel - Specifies the behavior when the delay is canceled:
 *   - `'throw'`: Reject the promise, simulating an error.
 *   - `'resolve'`: Resolve the promise with `false` to indicate cancellation.
 *   - `'nothing'`: Do nothing; the promise remains unresolved.
 *
 * @returns A `CancellablePromise` that:
 *   - Resolves to `true` if the delay completes successfully.
 *   - Resolves to `false` if canceled with `onCancel='resolve'`.
 *   - Rejects if canceled with `onCancel='throw'`.
 *   - Forever remains unresolved if canceled with `onCancel='nothing'` (which is the default)
 *
 * ### Usage
 * ```typescript
 * const promise = Delay.ms(1000, 'resolve').then(result => {
 *     logger.debug(result ? 'Delay ended!' : 'Cancelling delay!');
 * });
 *
 * // Optionally cancel the delay:
 * let wasCancelled = promise.cancel(); // Cancels the promise
 *
 * logger.debug(wasCanceled ? "Delay has been canceled successfully!" : "Too late, delay was already over!");
 * ```
 */
class Delay {
    static pendingDelays = [];
    static ms(durationMs, onCancel = 'nothing') {
        let timeoutHandle = null;
        let resolve;
        let reject;
        const promise = new CancellablePromise((res, rej) => {
            [resolve, reject] = [res, rej];
            timeoutHandle = GLib.timeout_add(GLib.PRIORITY_DEFAULT, durationMs, () => {
                timeoutHandle = null;
                Delay.pendingDelays = Delay.pendingDelays.filter(d => d !== promise);
                resolve(true);
                return GLib.SOURCE_REMOVE;
            });
        }, () => {
            if (timeoutHandle !== null) {
                GLib.source_remove(timeoutHandle);
                Delay.pendingDelays = Delay.pendingDelays.filter(d => d !== promise);
                if (onCancel === 'throw')
                    reject();
                else if (onCancel === 'resolve')
                    resolve(false);
                return true;
            }
            return false;
        });
        this.pendingDelays.push(promise);
        return promise;
    }
    static s(seconds, onCancel = 'nothing') {
        return Delay.ms(seconds * 1000, onCancel);
    }
    static min(minutes, onCancel = 'nothing') {
        return Delay.ms(minutes * 60 * 1000, onCancel);
    }
    static h(hours, onCancel = 'nothing') {
        return Delay.ms(hours * 60 * 60 * 1000, onCancel);
    }
    /**
     * Get a list of all pending delays.
     *
     * This function is only intended to be used to clean up pending [Delay]s when
     * the extension is being disabled; thus do not use it anywhere outside
     * [TouchUpExtension.disable()].
     */
    static getAllPendingDelays() {
        return [...this.pendingDelays];
    }
}
class CancellablePromise extends Promise {
    _onCancel;
    constructor(executor, onCancel) {
        super(executor);
        this._onCancel = onCancel;
    }
    /**
     * Returns true if the promise was cancelled successfully, false if it was already
     * resolved/rejected before.
     */
    cancel() {
        return this._onCancel();
    }
    then(onFulfilled, onRejected) {
        return new CancellablePromise((resolve, reject) => {
            super.then(
            // @ts-ignore
            onFulfilled
                ? (v) => resolve(onFulfilled(v))
                : null, onRejected
                ? (r) => reject(onRejected(r))
                : null);
        }, this._onCancel);
    }
    catch(onRejected) {
        return new CancellablePromise((resolve, reject) => {
            // @ts-ignore
            super.catch((r) => {
                const reason = onRejected?.(r);
                reject(reason);
                return reason ?? r;
            });
        }, this._onCancel);
    }
}

export { CancellablePromise, Delay };
