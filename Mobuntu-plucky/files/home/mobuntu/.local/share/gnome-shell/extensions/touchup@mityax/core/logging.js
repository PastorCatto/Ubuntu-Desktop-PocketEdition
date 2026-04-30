import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import { logFile } from '../config.js';

/**
 * The main logger instance.
 */
let logger;
function initLogger() {
    logger = new Logger('touchup');
}
function uninitLogger() {
    // @ts-ignore
    logger = undefined;
}
/**
 * The several log methods of this class log text to the console and, if given, to the global
 * logfile for this extension.
 *
 * Note: The logging methods are **not** optimized for speed (!)
 */
class Logger {
    tag;
    constructor(tag) {
        this.tag = tag;
    }
    /**
     * Log a debug-level message.
     *
     * This is a no-op in release builds.
     */
    debug(...text) {
    }
    /**
     * Perform an info-level log.
     */
    info(...text) {
        this._log('info', this._formatTag(), ...text);
    }
    /**
     * Log a warning message.
     */
    warn(...text) {
        this._log('warn', this._formatTag(), 'WARNING:', ...text);
    }
    /**
     * Log an error. The stacktrace is printed if the error instance is given as the last argument, e.g.:
     *
     * ```ts
     * try {
     *     foo()
     * } catch (e) {
     *     logger.error('An error occurred while doing foo:', error);
     * }
     * ```
     */
    error(...text) {
        this._log('error', this._formatTag(), 'ERROR:', ...text);
    }
    _log(level, tag, ...text) {
        if (text.length < 1)
            return '';
        const consoleLogFn = {
            debug: console.debug,
            info: console.log,
            warn: console.warn,
            error: console.error,
        }[level];
        let msg = text.map(item => {
            let errorMatch = matchError(item);
            return errorMatch
                ? `${errorMatch.errorType}: ${errorMatch.message}`
                : repr(item);
        }).join(" ");
        // If the last item is an error, we append its stack trace to the log message:
        let errorMatch = matchError(text.at(-1));
        if (errorMatch?.stack) {
            msg += '\n' + errorMatch.stack.trim();
        }
        consoleLogFn(tag, msg);
        if (logFile) {
            const stream = Gio.File.new_for_path(logFile).append_to(Gio.FileCreateFlags.NONE, null);
            // @ts-ignore
            stream.write_bytes(new GLib.Bytes(`${new Date().toISOString()}: ${msg}\n`), null);
        }
        for (let cb of logCallbacks.values()) {
            cb({
                level: level,
                tag: tag,
                formattedMessage: msg,
                rawArguments: text,
            });
        }
        return msg;
    }
    _formatTag(subtag) {
        return `[${this.tag}${subtag ? `:${subtag}` : ''}]`;
    }
}
/**
 * Tries to convert anything into a string representation that provides suitable debugging
 * information to developers
 */
function repr(item) {
    if (item === '')
        return "<empty string>";
    if (typeof item === 'symbol')
        return `<#${item.description}>`;
    if (['number', 'string'].indexOf(typeof item) !== -1)
        return `${item}`;
    let json;
    try {
        if (typeof item === 'object' || Array.isArray(item)) {
            json = JSON.stringify(item);
        }
    }
    catch (e) { }
    if (item && typeof item === 'object' && item.constructor && item.constructor.name) {
        let errorMatch = matchError(item);
        if (errorMatch !== null) {
            return `<${errorMatch.errorType} object ${errorMatch.message}>`;
        }
        else if (json) {
            return `<${item.constructor.name} object ${json.length > 300 ? json.substring(0, 300) + ' [...]' : json}>`;
        }
        else {
            return `<${item.constructor.name} object (not stringifyable)>`;
        }
    }
    return json || `${item}`;
}
const logCallbacks = new Map();
// Helpers:
/** Check if the given item is of a known error class, and return a unified error interface, if so. */
function matchError(item) {
    if (item instanceof Error) {
        return {
            errorType: item.constructor.name,
            message: item.message,
            stack: item.stack,
        };
    }
    else if (item instanceof Gio.IOErrorEnum) {
        return {
            errorType: `Gio.IOErrorEnum(${item.code})`,
            message: item.message,
            stack: item.stack,
        };
    }
    else if (item instanceof GLib.Error) {
        return {
            errorType: `GLib.Error(${item.code})`,
            message: item.message,
            stack: item.stack,
        };
    }
    return null;
}

export { Logger, initLogger, logger, repr, uninitLogger };
