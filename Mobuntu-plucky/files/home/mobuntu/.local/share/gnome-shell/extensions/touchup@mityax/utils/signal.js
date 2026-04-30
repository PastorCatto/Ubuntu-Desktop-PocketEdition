/**
 * @deprecated New classes should extend [EventEmitter] instead of using this class
 */
class Signal {
    listeners = new Map();
    _signalIdCounter = 0;
    emit(args) {
        for (let l of this.listeners.values()) {
            l(args);
        }
    }
    connect(signal, handler) {
        let id = this._signalIdCounter++;
        this.listeners.set(id, handler ?? signal);
        return id;
    }
    disconnect(id) {
        this.listeners.delete(id);
    }
}

export { Signal as default };
