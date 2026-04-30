class EventEmitter {
    _listeners = [];
    _idCounter = 0;
    emit(s, ...args) {
        const listeners = this._listeners.find((l) => l.signal === s);
        if (listeners) {
            listeners.callbacks.forEach((l, idx) => l.fn(...args));
            listeners.callbacks = listeners.callbacks.filter(l => !l.options.once);
        }
    }
    connect(signal, callback) {
        return this._connect(signal, callback);
    }
    connectOnce(signal, callback) {
        return this._connect(signal, callback, { once: true });
    }
    disconnect(id) {
        for (let sig of this._listeners) {
            for (let i = 0; i < sig.callbacks.length; i++) {
                if (sig.callbacks[i].id === id) {
                    sig.callbacks.splice(i, 1);
                    return true;
                }
            }
        }
        return false;
    }
    _hasListenersFor(signal) {
        return this._listeners
            .find((l) => l.signal === signal)
            ?.callbacks.length ?? 0 > 0;
    }
    _connect(signal, callback, opts) {
        const id = this._idCounter++;
        let array = this._listeners
            .find((l) => l.signal === signal)
            ?.callbacks;
        if (!array) {
            array = [];
            this._listeners.push({
                signal,
                callbacks: array,
            });
        }
        array.push({
            id,
            fn: callback,
            options: opts ?? {},
        });
        return id;
    }
}

export { EventEmitter as default };
