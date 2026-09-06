import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.systemmanagement
import "systemmanagement/SystemDiscoveryCycle.js" as Cycle

ShellRoot {
    id: root
    property int assertions: 0
    property int stage: 0
    property int ticks: 0
    property int expected: 0
    property int boundaryEvents: 0
    property string continuation: ""
    property double stoppedAt: 0
    property bool done: false

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Discovery FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function unitTests() {
        const c = Cycle.create();
        Cycle.begin(c);
        for (let i = 0; i < 100; i++) Cycle.invalidate(c);
        const first = Cycle.take(c);
        Cycle.beforePublish(c, first);
        Cycle.complete(c, first, true);
        root.check(c.phase === "idle", "Pending burst is covered by the reserved initial read");
        Cycle.invalidate(c);
        const initial = Cycle.take(c);
        for (let i = 0; i < 100; i++) Cycle.invalidate(c);
        Cycle.beforePublish(c, initial);
        Cycle.invalidate(c);
        Cycle.complete(c, initial, true);
        root.check(c.phase === "settling-pending", "Initial completion reserves exactly one settling read");
        Cycle.complete(c, initial, true);
        root.check(c.phase === "settling-pending", "Duplicate completion cannot consume the reserved rerun");
        const settling = Cycle.take(c);
        Cycle.complete(c, initial, false);
        root.check(c.phase === "settling-active", "Stale initial completion cannot fail the settling read");
        Cycle.beforePublish(c, settling);
        Cycle.invalidate(c);
        Cycle.complete(c, settling, true);
        root.check(c.unresolved && c.phase === "blocked", "Settling completion invalidation remains unresolved");
        for (let i = 0; i < 100; i++) Cycle.invalidate(c);
        root.check(!Cycle.pending(c) && Cycle.take(c) === null, "No automatic third read");
        Cycle.begin(c);
        const retry = Cycle.take(c);
        Cycle.complete(c, retry, true);
        root.check(c.unresolved && Cycle.pending(c), "Explicit retry cannot clear sticky state with its first read");
        Cycle.complete(c, Cycle.take(c), true);
        root.check(!c.unresolved && c.phase === "idle", "Quiet settling clears sticky state");
        Cycle.invalidate(c);
        const obsolete = Cycle.take(c);
        Cycle.close(c);
        Cycle.begin(c);
        Cycle.complete(c, obsolete, true);
        root.check(c.phase === "initial-pending", "Old closed-cycle completion cannot consume a reopened cycle");
        Cycle.complete(c, Cycle.take(c), false);
        root.check(c.unresolved && c.phase === "blocked", "Failed snapshots stop automatic rereads");
    }

    function count() { return parseInt(model.generation, 16); }

    function control(mode, next) {
        root.continuation = next;
        controlProcess.command = Commands.systemManagementCommand("fixture-control", [mode]);
        controlProcess.running = true;
    }

    function controlled() {
        if (root.continuation === "open") { root.stage = 1; model.openSettings(); }
        else if (root.continuation === "self") { root.stage = 2; model.refresh(); }
        else if (root.continuation === "events") { root.stage = 3; root.ticks = 0; }
        else if (root.continuation === "quiet") { root.stage = 4; model.refresh(); }
        else if (root.continuation === "clear-boundary") { root.stage = 6; model.refresh(); }
        else if (root.continuation === "slow") { root.stage = 7; model.refresh(); }
        else if (root.continuation === "reopen") { root.stage = 9; model.openSettings(); }
        else if (root.continuation === "fail") { root.stage = 10; model.closeSettings(); model.openSettings(); }
        else if (root.continuation === "retry-monitor") { root.stage = 11; model.refresh(); }
        else if (root.continuation === "ignore-term") { root.stage = 12; model.closeSettings(); model.openSettings(); }
        else if (root.continuation === "malformed") { root.stage = 14; model.openSettings(); }
        else if (root.continuation === "no-ready") {
            root.stage = 15;
            root.stoppedAt = Date.now();
            model.closeSettings();
            model.openSettings();
        }
        else if (root.continuation === "failed-stopping") { root.stage = 17; model.openSettings(); }
        else if (root.continuation === "early-retry") { root.stage = 18; model.refresh(); }
    }

    function advance() {
        if (root.done || controlProcess.running) return;
        const idle = !model.busy;
        if (root.stage === 0 && idle && model.snapshotState === "ready") {
            root.check(root.count() === 1 && !model.discovery.monitorOwned, "Closed startup has exactly one required read, no monitor");
            root.stage = -1;
            root.control("quiet", "open");
        } else if (root.stage === 1 && idle && model.discovery.fresh) {
            root.check(root.count() === 2, "Pane opening reads after the readiness handshake");
            root.stage = -1;
            root.control("self", "self");
        } else if (root.stage === 2 && idle && model.discovery.phase === "blocked") {
            root.check(root.count() === 4, "Self-generated global events stop after initial plus settling reads");
            root.check(model.providerState === "partial" && model.updates.length === 1
                && model.packageChanges.length === 1 && model.discoveryDetail.indexOf("Reload status") >= 0,
                "Dirty state preserves readable inventory and recovery guidance");
            root.stage = -1;
            root.control("events", "events");
        } else if (root.stage === 3 && ++root.ticks >= 5) {
            root.check(root.count() === 4 && idle && model.discovery.unresolved, "Further global bursts cannot start work");
            root.stage = -1;
            root.control("quiet", "quiet");
        } else if (root.stage === 4 && idle && model.discovery.fresh) {
            root.check(root.count() === 6 && !model.discovery.unresolved, "Explicit quiet retry performs its settling read");
            root.stage = 5;
            model.refresh();
        } else if (root.stage === 5 && idle && model.discovery.phase === "blocked") {
            root.check(root.count() === 8 && root.boundaryEvents === 2,
                "Reentrant completion-boundary events cannot be lost or schedule a third read");
            root.stage = -1;
            root.control("quiet", "clear-boundary");
        } else if (root.stage === 6 && idle && model.discovery.fresh) {
            root.check(root.count() === 10, "Boundary-dirty retry settles exactly once");
            root.stage = -1;
            root.control("slow", "slow");
        } else if (root.stage === 7 && model.busy) {
            root.stage = 8;
            model.closeSettings();
        } else if (root.stage === 8 && idle && !model.discovery.monitorOwned) {
            root.check(!model.discovery.visible && !model.discovery.fresh, "Pane closure stops optional read and monitor");
            root.stage = -1;
            root.control("quiet", "reopen");
        } else if (root.stage === 9 && idle && model.discovery.fresh) {
            root.check(root.count() > 10, "Reopen reads new state after a new monitor baseline");
            root.expected = root.count() + 1;
            root.stage = -1;
            root.control("fail-monitor", "fail");
        } else if (root.stage === 10 && idle && model.discovery.failed && root.count() === root.expected) {
            root.check(model.providerState === "partial" && model.updates.length === 1 && !model.discovery.fresh,
                "Startup monitor failure retains finite readable status without freshness");
            root.stage = -1;
            root.control("quiet", "retry-monitor");
        } else if (root.stage === 11 && idle && model.discovery.fresh) {
            root.check(root.count() === root.expected + 1, "Explicit retry restores failed monitoring");
            root.stage = -1;
            root.control("ignore-term", "ignore-term");
        } else if (root.stage === 12 && idle && model.discovery.fresh) {
            root.stage = 13;
            root.stoppedAt = Date.now();
            model.closeSettings();
        } else if (root.stage === 13 && !model.discovery.monitorOwned) {
            root.check(Date.now() - root.stoppedAt >= 1000 && Date.now() - root.stoppedAt < 4000,
                "Unresponsive monitor is killed after bounded close grace");
            root.expected = root.count() + 1;
            root.stage = -1;
            root.control("malformed", "malformed");
        } else if (root.stage === 14 && idle && model.discovery.failed && root.count() === root.expected) {
            root.check(!model.discovery.ready && model.updates.length === 1,
                "A changed record before readiness fails monitoring without hiding the snapshot");
            root.expected++;
            root.stage = -1;
            root.control("no-ready", "no-ready");
        } else if (root.stage === 15 && idle && model.discovery.failed && root.count() === root.expected) {
            root.check(Date.now() - root.stoppedAt >= 11000 && Date.now() - root.stoppedAt < 17000,
                "Missing readiness falls back to a finite snapshot within the setup deadline");
            model.closeSettings();
            root.stage = 16;
        } else if (root.stage === 16 && !model.discovery.monitorOwned) {
            root.expected = root.count() + 1;
            root.stage = -1;
            root.control("failed-stopping", "failed-stopping");
        } else if (root.stage === 17 && idle && model.discovery.failed && root.count() === root.expected) {
            root.check(model.discovery.monitorOwned && model.discovery.stopping,
                "Retry fixture retains the failed monitor during its shutdown grace");
            root.expected++;
            root.stage = -1;
            root.control("restart-quiet", "early-retry");
        } else if (root.stage === 18 && idle && model.discovery.fresh) {
            root.check(root.count() === root.expected, "Queued replacement monitor has exactly one baseline read");
            model.closeSettings();
            root.stage = 19;
        } else if (root.stage === 19 && !model.discovery.monitorOwned) {
            root.done = true;
            console.info("Discovery native tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }

    SystemManagementModel {
        id: model
        onSnapshotStateChanged: {
            if (root.stage === 5 && snapshotState === "ready") {
                root.check(snapshotOwned, "Snapshot ownership covers all publication callbacks");
                root.boundaryEvents++;
                discovery.invalidate();
            }
        }
    }
    Process {
        id: controlProcess
        onExited: (code, status) => {
            root.check(code === 0 && status === 0, "Private fixture control succeeds");
            Qt.callLater(root.controlled);
        }
    }
    Timer { interval: 50; repeat: true; running: true; onTriggered: root.advance() }
    Timer {
        interval: 45000; running: true
        onTriggered: root.check(false, "Discovery scenario timed out at stage " + root.stage + ", phase "
            + model.discovery.phase + ", snapshot " + model.snapshotState + ", count " + root.count())
    }
    Component.onCompleted: root.unitTests()
}
