import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.systemmanagement

ShellRoot {
    id: root
    property string eventDomain: Quickshell.env("DWM_DISCOVERY_DOMAIN") || "time"
    readonly property string heldDomain: root.eventDomain === "time" ? "locale" : root.eventDomain
    readonly property string stateId: root.eventDomain === "storage" ? "filesystem-summary" : root.eventDomain === "security" ? "firewalld" : "timezone"
    function eventMonitor() { return model.discoveryModels().find(item => item.domain === root.eventDomain); }
    readonly property string failedDomain: root.eventDomain === "time" ? "locale" : root.eventDomain
    readonly property string failedStateId: root.eventDomain === "time" ? "locale" : root.stateId
    function failedMonitor() { return model.discoveryModels().find(item => item.domain === root.failedDomain); }
    function peerMonitor() { return root.failedDomain === "locale" ? model.timeDiscovery : model.localeDiscovery; }
    function heldMonitor() { return model.discoveryModels().find(item => item.domain === root.heldDomain); }
    property int stage: 0
    property int assertions: 0
    property int ticks: 0
    property int timeEvents: 0
    property int expectedEvents: 0
    property int boundaryEvents: 0
    property int expectedCount: 0
    property string continuation: ""
    property bool done: false
    property bool closeDuringTake: false
    property bool closeDuringLoading: false

    function check(value, detail) {
        root.assertions++;
        if (!value) {
            console.error("Native discovery FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function count() { return parseInt(model.generation, 16); }
    function allFresh() { return model.discoveryModels().every(item => item.fresh); }
    function allStopped() { return model.discoveryModels().every(item => !item.monitorOwned); }

    function command(action, args, next) {
        root.continuation = next;
        control.command = Commands.systemManagementCommand(action, args);
        control.running = true;
    }

    function mode(domain, value, next) { root.command("fixture-mode", [domain, "set", value], next); }
    function event(domain, value, next) {
        if (domain === root.eventDomain && value === "emit") root.expectedEvents = root.timeEvents + 100;
        root.command("fixture-event", [domain, value], next);
    }

    function controlled() {
        const next = root.continuation;
        if (next === "open") { root.stage = 1; model.openSettings(); }
        else if (next === "released-ready") { root.stage = -1; root.mode(root.heldDomain, "quiet", "released-quiet"); }
        else if (next === "released-quiet") root.stage = 3;
        else if (next === "first") { root.stage = 4; model.refresh(); }
        else if (next === "first-events") root.stage = 5;
        else if (next === "first-finished") root.stage = 6;
        else if (next === "settling-events") root.stage = 7;
        else if (next === "settling-finished") { root.stage = 8; root.ticks = 0; }
        else if (next === "quiet") { root.stage = 9; model.accountDiscovery.invalidate(); }
        else if (next === "blocked-count") { root.stage = 11; model.refresh(); }
        else if (next === "bad-locale") { root.stage = 14; model.openSettings(); }
        else if (next === "restore-locale") { root.stage = 15; model.refresh(); }
        else if (next === "hold-close") { root.stage = 16; model.refresh(); }
        else if (next === "reopen") { root.stage = 18; model.openSettings(); }
        else if (next === "required-start") { root.stage = 24; model.operation.requestSnapshot(); }
        else if (next === "required-quiet") { root.stage = -1; root.event("snapshot", "finish", "required-finished"); }
        else if (next === "required-finished") root.stage = 26;
    }

    function advance() {
        if (root.done || control.running) return;
        const idle = !model.busy;
        if (root.stage === 0 && idle && model.snapshotState === "ready") {
            root.check(root.count() === 1 && root.allStopped(), "Closed startup has one required read and no subscriptions");
            root.stage = -1;
            root.mode(root.heldDomain, "hold", "open");
        } else if (root.stage === 1 && model.discoveryModels().filter(item => item.domain !== root.heldDomain).every(item => item.ready) && ++root.ticks >= 8) {
            root.check(!root.heldMonitor().ready && root.heldMonitor().monitorOwned, "Selected provider readiness is held");
            root.check(idle && root.count() === 1, "Optional snapshot waits for every subscription");
            root.check(!model.discoveryModels().some(item => item.fresh), "No domain inherits the closed startup baseline");
            root.stage = 2;
            model.operation.requestSnapshot();
        } else if (root.stage === 2 && idle && root.count() === 2) {
            root.check(model.nativeStates.timezone.value === "America/Chicago", "Required recovery preserves readable native state");
            root.check(!model.discoveryModels().some(item => item.fresh), "Required bypass cannot certify unmonitored baselines");
            root.stage = -1;
            root.event(root.heldDomain, "ready", "released-ready");
        } else if (root.stage === 3 && idle && root.allFresh()) {
            root.check(root.count() === 3, "All readiness handshakes produce one shared baseline");
            root.check(model.accounts.length === 1 && model.repositories.length === 1, "Cumulative lists stay readable");
            root.stage = -1;
            root.mode("snapshot", "hold", "first");
        } else if (root.stage === 4 && model.busy && root.eventMonitor().phase === "initial-active") {
            root.check(model.discoveryModels().every(item => item.phase === "initial-active"), "Refresh batches all seven initial tokens");
            root.stage = -1;
            root.event(root.eventDomain, "emit", "first-events");
        } else if (root.stage === 5 && root.timeEvents >= root.expectedEvents) {
            root.check(root.eventMonitor().cycle.dirty, "Time burst dirties only its active cycle");
            root.stage = -1;
            root.event("snapshot", "finish", "first-finished");
        } else if (root.stage === 6 && model.busy && root.eventMonitor().phase === "settling-active") {
            root.check(model.accountDiscovery.phase === "idle" && model.localeDiscovery.phase === "idle", "Quiet domains need no settling token");
            root.stage = -1;
            root.event(root.eventDomain, "emit", "settling-events");
        } else if (root.stage === 7 && root.timeEvents >= root.expectedEvents) {
            root.check(root.eventMonitor().unresolved, "Second burst retains unresolved time state");
            root.stage = -1;
            root.event("snapshot", "finish", "settling-finished");
        } else if (root.stage === 8 && idle && ++root.ticks >= 8) {
            root.check(root.count() === 5 && root.eventMonitor().phase === "blocked", "Time cycle stops after initial plus settling read");
            root.check(model.nativeStateView(root.stateId).status === "partial"
                && model.nativeStateView("locale").status === "available", "Time and locale freshness remain independent");
            root.check(model.nativeProviderView(root.eventDomain === "time" ? "regional" : root.eventDomain).status === "partial"
                && model.nativeStateView(root.stateId).value === (root.eventDomain === "time" ? "America/Chicago" : root.eventDomain === "storage" ? "1" : "enabled"), "Unresolved provider preserves readable values");
            root.check(model.nativeStateView(root.stateId).detail.indexOf("Reload status") >= 0, "Unresolved state explains explicit retry");
            root.stage = -1;
            root.mode("snapshot", "quiet", "quiet");
        } else if (root.stage === 9 && idle && root.count() === 6) {
            root.check(model.accountDiscovery.fresh && root.eventMonitor().unresolved && !root.eventMonitor().fresh,
                "Account-triggered full read cannot clear blocked time freshness");
            root.stage = 10;
            model.operation.requestSnapshot();
        } else if (root.stage === 10 && idle && root.count() === 7) {
            root.check(root.eventMonitor().phase === "blocked", "Required recovery read cannot clear blocked time freshness");
            root.check(model.actions.some(action => action.id === "health-open"), "Required core recovery retains read-only health navigation");
            root.check(model.nativeStates.firewalld.value === "enabled", "Core recovery retains optional readable observations");
            root.stage = -1;
            root.command("fixture-count", ["7"], "blocked-count");
        } else if (root.stage === 11 && idle && root.eventMonitor().phase === "blocked") {
            root.check(root.count() === 9 && root.boundaryEvents === 2, "Reentrant publication invalidations stop after two reads");
            root.stage = 12;
            model.refresh();
        } else if (root.stage === 12 && idle && root.allFresh()) {
            root.check(root.count() === 11, "Explicit quiet retry clears unresolved state after one settling read");
            root.check(model.nativeProviderView(root.eventDomain === "time" ? "regional" : root.eventDomain).status === "available", "Quiet retry restores clean provider projection");
            model.closeSettings();
            root.stage = 13;
        } else if (root.stage === 13 && root.allStopped()) {
            root.stage = -1;
            root.mode(root.failedDomain, "fail", "bad-locale");
        } else if (root.stage === 14 && idle && root.failedMonitor().failed && root.peerMonitor().fresh) {
            root.check(root.count() === 12 && !root.failedMonitor().fresh, "Failed monitor gets one finite shared fallback");
            root.check(model.nativeStateView(root.failedStateId).status === "partial"
                && model.nativeStateView(root.failedDomain === "locale" ? "timezone" : "locale").status === "available",
                "Failed monitor does not hide unrelated readable state");
            if (root.eventDomain === "storage")
                root.check(model.filesystemsRetained && model.filesystems.length === 1
                    && model.nativeStates["filesystem-summary"].value === "unknown", "Unmonitored storage retains explicitly stale rows with unknown current summary");
            root.stage = -1;
            root.mode(root.failedDomain, "quiet", "restore-locale");
        } else if (root.stage === 15 && idle && root.allFresh()) {
            root.check(root.count() === 13, "Explicit refresh retries only the failed subscription and shares one read");
            root.stage = -1;
            root.mode("snapshot", "hold", "hold-close");
        } else if (root.stage === 16 && model.busy && root.eventMonitor().phase === "initial-active") {
            model.closeSettings();
            root.stage = 17;
        } else if (root.stage === 17 && idle && root.allStopped()) {
            root.check(!model.discoveryModels().some(item => item.visible || item.fresh), "Close retires all cycles and optional work");
            root.expectedCount = root.count();
            root.stage = -1;
            root.mode("snapshot", "quiet", "reopen");
        } else if (root.stage === 18 && idle && root.allFresh()) {
            root.check(root.count() > root.expectedCount, "Reopen requires a new shared baseline");
            model.closeSettings();
            root.stage = 19;
        } else if (root.stage === 19 && root.allStopped()) {
            root.stage = 20;
            model.openSettings();
        } else if (root.stage === 20 && idle && root.allFresh()) {
            root.expectedCount = root.count();
            root.stage = 21;
            root.closeDuringTake = true;
            model.refresh();
        } else if (root.stage === 21 && idle && root.allFresh()) {
            root.check(!root.closeDuringTake && root.count() === root.expectedCount + 1,
                "Close/reopen during take cannot launch the canceled read or consume new-cycle tokens");
            root.expectedCount = root.count();
            root.stage = 22;
            root.closeDuringLoading = true;
            model.refresh();
        } else if (root.stage === 22 && idle && root.allFresh()) {
            root.check(!root.closeDuringLoading && root.count() === root.expectedCount + 1,
                "Close/reopen during loading publication cannot launch the canceled read");
            model.closeSettings();
            root.stage = 23;
        } else if (root.stage === 23 && root.allStopped()) {
            root.expectedCount = root.count();
            root.stage = -1;
            root.mode("snapshot", "hold", "required-start");
        } else if (root.stage === 24 && model.busy && model.snapshotRequired) {
            model.openSettings();
            root.stage = 25;
        } else if (root.stage === 25 && model.discoveryReady()) {
            root.check(!root.allFresh() && model.snapshotRequired, "Opening during a required read still needs a monitored baseline");
            model.closeSettings();
            root.check(model.busy && model.snapshotRequired, "Pane close cannot stop required recovery");
            root.stage = -1;
            root.mode("snapshot", "quiet", "required-quiet");
        } else if (root.stage === 26 && idle && root.allStopped()) {
            root.check(root.count() === root.expectedCount + 2, "Queued required recovery completes independently of closed subscriptions");
            root.check(!model.discoveryModels().some(item => item.fresh), "Required reads cannot certify closed domains");
            root.stage = 27;
            model.openSettings();
        } else if (root.stage === 27 && idle && root.allFresh()) {
            root.check(root.count() === root.expectedCount + 3, "Reopen reserves its own monitored baseline after required recovery");
            model.closeSettings();
            root.stage = 28;
        } else if (root.stage === 28 && root.allStopped()) {
            root.done = true;
            console.info("Native discovery tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }

    SystemManagementModel {
        id: model
        onSnapshotStateChanged: {
            if (root.closeDuringLoading && snapshotState === "loading") {
                root.closeDuringLoading = false;
                root.check(snapshotOwned, "Loading publication retains ownership");
                closeSettings();
                openSettings();
            }
            if (root.stage === 11 && snapshotState === "ready") {
                root.check(snapshotOwned, "All publication callbacks retain the shared snapshot owner");
                root.boundaryEvents++;
                root.eventMonitor().invalidate();
            }
        }
    }
    Connections {
        target: root.eventMonitor()
        function onInvalidated() { root.timeEvents++; }
        function onPhaseChanged() {
            if (root.closeDuringTake && root.eventMonitor().phase === "initial-active") {
                root.closeDuringTake = false;
                root.check(model.snapshotOwned, "Token admission retains ownership");
                model.closeSettings();
                model.openSettings();
            }
        }
    }
    Process {
        id: control
        stderr: StdioCollector { id: controlError }
        onExited: (code, status) => {
            root.check(code === 0 && status === 0, "Private fixture control succeeds ("
                + root.continuation + ", exit " + code + ", status " + status + "): " + controlError.text);
            Qt.callLater(root.controlled);
        }
    }
    Timer { interval: 25; repeat: true; running: !root.done; onTriggered: root.advance() }
    Timer {
        interval: 30000; running: true
        onTriggered: root.check(false, "Timeout at stage " + root.stage + ", count " + root.count()
            + ", time " + root.eventMonitor().phase + ", snapshot " + model.snapshotState)
    }
}
