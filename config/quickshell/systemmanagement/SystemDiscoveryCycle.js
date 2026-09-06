// Serialized state only: no QML property signals inside the completion handoff.
function create() {
    return { epoch: 0, enabled: false, phase: "idle", dirty: false,
        unresolved: false, forceSettle: false, settlingDirty: false };
}

function begin(cycle) {
    cycle.epoch++;
    cycle.enabled = true;
    cycle.phase = "initial-pending";
    cycle.dirty = false;
    cycle.forceSettle = cycle.unresolved;
    cycle.settlingDirty = false;
}

function close(cycle) {
    cycle.epoch++;
    cycle.enabled = false;
    cycle.phase = "idle";
    cycle.dirty = false;
}

function invalidate(cycle) {
    if (!cycle.enabled) return;
    if (cycle.phase === "idle") begin(cycle);
    else if (cycle.phase === "initial-active" || cycle.phase === "initial-completing")
        cycle.dirty = true;
    else if (cycle.phase === "settling-active" || cycle.phase === "settling-completing") {
        cycle.settlingDirty = true;
        cycle.unresolved = true;
    }
    // Pending invalidations are covered by the reserved read. Blocked cycles
    // retain their unresolved bit without scheduling a third automatic read.
}

function pending(cycle) {
    return cycle.enabled && (cycle.phase === "initial-pending" || cycle.phase === "settling-pending");
}

function take(cycle) {
    if (!pending(cycle)) return null;
    const settling = cycle.phase === "settling-pending";
    cycle.phase = settling ? "settling-active" : "initial-active";
    cycle.settlingDirty = false;
    return { epoch: cycle.epoch, settling: settling };
}

function owns(cycle, token) {
    if (token === null || !cycle.enabled || token.epoch !== cycle.epoch) return false;
    const prefix = token.settling ? "settling" : "initial";
    return cycle.phase === prefix + "-active" || cycle.phase === prefix + "-completing";
}

function beforePublish(cycle, token) {
    if (owns(cycle, token))
        cycle.phase = token.settling ? "settling-completing" : "initial-completing";
}

function complete(cycle, token, successful) {
    if (!owns(cycle, token)) return;
    if (!successful) {
        cycle.unresolved = true;
        cycle.phase = "blocked";
    } else if (token.settling) {
        cycle.unresolved = cycle.settlingDirty;
        cycle.phase = cycle.unresolved ? "blocked" : "idle";
    } else if (cycle.dirty || cycle.forceSettle) {
        cycle.dirty = false;
        cycle.phase = "settling-pending";
    } else cycle.phase = "idle";
}
