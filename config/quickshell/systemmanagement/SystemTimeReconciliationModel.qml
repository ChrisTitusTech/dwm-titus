import QtQuick
import Quickshell
import "SystemDiscoveryCycle.js" as Cycle

// Owner arrival is uncertainty, not proof that time configuration changed.
// This owner never reads PackageKit or accepts journal recovery evidence.
Scope {
    id: root
    required property var model
    property var cycle: Cycle.create()
    property var request: null
    property var baseline: null
    property var expected: null
    property bool waitingSnapshot: false
    property bool mismatchRecoveryUsed: false
    property string phase: "idle"
    property bool unresolved: false
    property string failure: ""
    readonly property alias reader: readerModel
    readonly property bool blocked: waitingSnapshot || phase !== "idle" || unresolved
        || failure.length > 0 || request !== null || readerModel.current !== null
    readonly property string detail: !model.settingsVisible ? "" : failure.length > 0 ? failure
        : unresolved ? "Time changed during reconciliation. Reload status to retry; automatic rereads are paused."
        : blocked ? "Reconciling time status before allowing another time change..." : ""
    signal aboutToBlock()
    signal released()

    function ownsRead() { return request !== null || readerModel.current !== null; }
    function blocksAdmission() {
        return waitingSnapshot || cycle.phase !== "idle" || cycle.unresolved || failure.length > 0 || ownsRead();
    }
    function publish() {
        if (blocksAdmission() && !blocked) aboutToBlock();
        phase = cycle.phase;
        unresolved = cycle.unresolved;
    }
    function identity() {
        return { generation: model.generation, requestGeneration: model.requestGeneration,
            epoch: model.timeDiscovery.cycle.epoch };
    }
    function matches(ticket) {
        return model.settingsVisible && ticket.generation === model.generation
            && ticket.requestGeneration === model.requestGeneration && ticket.epoch === model.timeDiscovery.cycle.epoch;
    }
    function availableContext() {
        const monitor = model.timeDiscovery;
        return model.settingsVisible && !model.snapshotOwned && !model.snapshotPending && !model.requiredPending
            && !model.discoveryBatch && !model.dispatchingNative && !model.dispatchingUpdate
            && model.validGeneration(model.generation)
            && monitor.visible && monitor.ready && !monitor.failed && monitor.cycle.enabled
            && monitor.cycle.phase === "idle" && !monitor.cycle.unresolved
            && (!model.regional.ownsPreparation() || model.regional.awaitingTimeReconciliation());
    }
    function open() {
        mismatchRecoveryUsed = false;
        beforeSnapshot();
    }
    function beforeSnapshot() {
        // The caller reserves snapshot priority before retiring optional work.
        Cycle.close(cycle);
        cycle.unresolved = false;
        request = null;
        readerModel.cancel();
        baseline = null;
        expected = null;
        failure = "";
        waitingSnapshot = model.settingsVisible;
        publish();
    }
    function close() {
        beforeSnapshot();
        waitingSnapshot = false;
        publish();
    }
    function afterSnapshot() {
        if (!model.settingsVisible) { close(); return; }
        // Legacy snapshots have no native time offers to certify.
        waitingSnapshot = false;
        if (!model.nativeProviders.regional) { publish(); return; }
        const zone = model.nativeStates.timezone;
        const enabled = model.nativeStates["ntp-enabled"];
        const ntpOffer = model.actions.find(item => item.id === "ntp-set");
        const zoneOffer = model.actions.find(item => item.id === "timezone-set");
        // With readable time state, both actions share the same admission
        // blocker. Only NTP adds a capability check. Do not infer capability
        // absence when the shared blocker also disables the timezone action.
        const canNtp = ntpOffer && ntpOffer.availability === "available" ? true
            : zoneOffer && zoneOffer.availability === "available" ? false : null;
        expected = zone && enabled && zone.status === "available" && enabled.status === "available"
            ? { timezone: zone.value, ntpEnabled: enabled.value === "yes", canNtp: canNtp } : null;
        Cycle.begin(cycle);
        publish();
        Qt.callLater(root.requestPending);
    }
    function arrived() {
        if (!model.settingsVisible || !model.nativeProviders.regional) return;
        // Snapshot priority already reserves a fresh complete baseline read.
        if (waitingSnapshot) return;
        if (!cycle.enabled) Cycle.begin(cycle);
        else Cycle.invalidate(cycle);
        publish();
        Qt.callLater(root.requestPending);
    }
    function requestPending() {
        if (waitingSnapshot || ownsRead() || !Cycle.pending(cycle) || !availableContext()) return;
        const ticket = Object.assign(identity(), { token: Cycle.take(cycle), outcome: null,
            readerId: readerModel.serial + 1 });
        request = ticket;
        publish();
        if (request !== ticket || !matches(ticket) || !availableContext()) {
            if (request === ticket) beforeSnapshot();
            return;
        }
        if (!readerModel.requestTimeStatus() && request === ticket) {
            failure = "Time status could not start. Reload status to retry.";
            Cycle.complete(cycle, ticket.token, false);
            request = null;
            publish();
            released();
        }
    }
    function sameConfiguration(left, right) {
        return left !== null && right !== null && left.timezone === right.timezone
            && left.canNtp === right.canNtp && left.ntpEnabled === right.ntpEnabled;
    }
    function finish(ticket) {
        if (request !== ticket || readerModel.current !== null || ticket.outcome === null) return;
        let successful = false;
        try {
            if (!matches(ticket) || !availableContext()) { beforeSnapshot(); return; }
            Cycle.beforePublish(cycle, ticket.token);
            const outcome = ticket.outcome;
            successful = outcome.status === "available";
            if (outcome.status !== "available") failure = outcome.error.code + ": " + outcome.error.detail + " Reload status to retry.";
            const quiet = ticket.token.settling ? !cycle.settlingDirty : !cycle.dirty && !cycle.forceSettle;
            if (successful && quiet) {
                const observed = outcome.observation;
                const changed = baseline !== null ? !sameConfiguration(baseline, observed)
                    : expected === null || expected.timezone !== observed.timezone || expected.ntpEnabled !== observed.ntpEnabled
                        || (expected.canNtp !== null && expected.canNtp !== observed.canNtp);
                if (changed) {
                    if (mismatchRecoveryUsed) {
                        cycle.phase = "blocked";
                        cycle.unresolved = true;
                        failure = "Time changed between status reads. Reload status to reconcile it; automatic rereads are paused.";
                    } else {
                        mismatchRecoveryUsed = true;
                        model.timeDiscovery.invalidate();
                        return;
                    }
                } else {
                    baseline = observed;
                    mismatchRecoveryUsed = false;
                    model.regional.reconcileTimePreview(observed);
                    if (request !== ticket || !matches(ticket)) return;
                    const states = Object.assign({}, model.nativeStates);
                    states["ntp-synchronized"] = { status: "available", value: observed.synchronized ? "yes" : "no",
                        detail: "Verified time synchronization status" };
                    model.nativeStates = states;
                }
            }
        } finally {
            // Reentrant arrivals during publication still belong to this read
            // and must reserve settling rather than start an unbounded cycle.
            if (request === ticket) Cycle.complete(cycle, ticket.token, successful);
            if (request === ticket) request = null;
            publish();
            released();
            Qt.callLater(root.requestPending);
            Qt.callLater(model.regional.retryTimePublication);
        }
    }
    SystemRegionalPreflightModel {
        id: readerModel
        active: root.model.settingsVisible
        onCompleted: outcome => {
            const ticket = root.request;
            if (ticket === null || ticket.readerId !== outcome.id) return;
            ticket.outcome = outcome;
            Qt.callLater(function() { root.finish(ticket); });
        }
        onCurrentChanged: {
            if (current === null) Qt.callLater(function() { if (!root.ownsRead()) root.released(); });
        }
    }
}
