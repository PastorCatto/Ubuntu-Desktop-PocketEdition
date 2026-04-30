import { Delay } from './delay.js';

function debounce(func, delay_ms) {
    let d = null;
    return (...args) => {
        d?.cancel();
        d = Delay.ms(delay_ms);
        d.then(_ => func(...args));
    };
}

export { debounce };
