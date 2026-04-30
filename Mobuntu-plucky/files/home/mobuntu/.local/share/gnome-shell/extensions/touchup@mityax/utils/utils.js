/**
 * Recursively walks the topActor's nested children until a child is found that satisfies `test`.
 * If no such child is found, returns `null`
 */
function findActorBy(topActor, test) {
    for (let child of topActor.get_children()) {
        if (test(child)) {
            return child;
        }
        else if (child.get_n_children()) {
            let result = findActorBy(child, test);
            if (result) {
                return result;
            }
        }
    }
    return null;
}
/**
 * Recursively walks the topActor's nested children, collecting all actors that satisfy `test`.
 *
 * Does not descend further into the children of matching actors.
 */
function findAllActorsBy(topActor, test) {
    const res = [];
    for (let child of topActor.get_children()) {
        if (test(child)) {
            res.push(child);
        }
        else if (child.get_n_children()) {
            res.push(...findAllActorsBy(child, test));
        }
    }
    return res;
}
function clamp(value, min, max) {
    if (max < min) {
        [min, max] = [max, min];
    }
    return Math.min(Math.max(value, min), max);
}
function randomChoice(arr) {
    return arr[Math.floor(arr.length * Math.random())];
}
function filterObject(obj, fn) {
    return Object.fromEntries(
    //@ts-ignore
    Object.entries(obj).filter(fn));
}
function oneOf(v, filter, orElse) {
    if (filter.includes(v)) {
        return v;
    }
    return orElse;
}

export { clamp, filterObject, findActorBy, findAllActorsBy, oneOf, randomChoice };
