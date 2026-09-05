import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property int scenario: 0
    property int assertions: 0
    property int snapshotRequests: 0
    property bool sawProgress: false
    property bool sawVerifying: false
    property bool emptyReplay: false
    property var target: null
    property var integrated: null
    property bool reloaded: false
    property bool failedStart: Quickshell.env("DWM_OWNER_FAILED_START") === "1"
    property bool incompleteRecovery: Quickshell.env("DWM_OWNER_INCOMPLETE_RECOVERY") === "1"
    property bool closeRetry: Quickshell.env("DWM_OWNER_CLOSE_RETRY") === "1"
    property bool closedDuringRetry: false
    property bool delayedSnapshot: Quickshell.env("DWM_OWNER_DELAYED_SNAPSHOT") === "1"
    property bool lateSnapshotOpened: false
    property bool sawLateAck: false
    property bool completed: false

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Operation owner FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function next() {
        if (root.scenario === 9) {
            root.integrated = integratedComponent.createObject(root);
            return;
        }
        root.scenario++;
        root.snapshotRequests = 0;
        root.sawProgress = false;
        root.sawVerifying = false;
        root.emptyReplay = false;
        root.target = { id: "op-" + root.scenario.toString(16).padStart(32, "0"),
            actionId: root.scenario === 2 ? "timezone-set" : "updates-refresh",
            kind: root.scenario === 2 ? "timezone" : "refresh" };
        model.resetRecovery();
        model.result = null;
        model.acceptSnapshot(root.scenario === 6 ? root.target : null,
            root.scenario === 6 ? null : root.target);
        const parser = model.parser;
        model.acceptSnapshot(null, root.scenario === 6 ? null : root.target);
        root.check(model.parser === parser, "Repeated snapshot must not replace owned stream");
    }

    SystemOperationModel {
        id: model
        onSnapshotRequested: {
            root.snapshotRequests++;
            if (root.scenario === 6) {
                root.check(model.result !== null, "Active watch must validate result before handoff read");
                model.acceptSnapshot(null, root.target);
            } else {
                model.acceptSnapshot(root.emptyReplay ? root.target : null,
                    root.emptyReplay ? null : root.target);
            }
        }
        onProgressChanged: {
            if (progress !== null) root.sawProgress = true;
        }
        onStateChanged: {
            if (state === "verifying") {
                root.sawVerifying = true;
                root.check(!controlOwned, "Cannot acknowledge provisional terminal text");
                if (!root.emptyReplay) root.check(result === null, "Cannot publish provisional success");
            }
            if (state === "failure") Qt.callLater(root.finishFailure);
        }
        onBlockedChanged: {
            if (blocked && (root.scenario === 4 || root.scenario === 9))
                Qt.callLater(root.finishControlFailure);
        }
        onAcknowledged: operationId => {
            root.check(operationId === root.target.id, "Acknowledgment must name exact validated identity");
            root.check(root.sawProgress && root.sawVerifying, "Stream progress must arrive before exit");
            root.check(result.state === (root.scenario === 2 ? "permission-denied" : "succeeded"),
                "Replay exit zero must accept failed results without relabeling success");
            root.check(!busy && !blocked, "Acknowledgment must return to idle ownership");
            if (root.scenario === 6) root.check(root.snapshotRequests === 1, "One handoff reconciliation read");
            if (root.scenario === 1 && !root.emptyReplay) {
                root.emptyReplay = true;
                const previousResult = model.result;
                Qt.callLater(function() {
                    // Exercise collector reuse independently of the separate
                    // acknowledged-identity filter (covered by handoff tests).
                    model.acknowledgedIds = [];
                    model.result = null;
                    model.acceptSnapshot(root.target, null);
                    model.result = previousResult;
                });
            } else Qt.callLater(root.next);
        }
    }

    function finishFailure() {
        if (root.completed || (root.failedStart && !root.integrated.operation.blocked)) return;
        root.check(model.blocked && !model.busy, "Exhausted recovery must stop all automatic work");
        root.check(root.snapshotRequests === 3 && model.retries === 3, "Exactly three bounded recovery reads");
        if (root.failedStart) {
            root.check(root.integrated.operation.blocked && !root.integrated.busy,
                "Snapshot FailedToStart also exhausts bounded recovery without stale output");
            root.complete();
            return;
        }
        if (root.emptyReplay) root.check(model.result !== null, "Previous verified result remains visible");
        else root.check(model.result === null, "Malformed or missing output cannot publish a result");
        root.check(model.detail.indexOf("reload status") >= 0, "Exhaustion has explicit recovery guidance");
        Qt.callLater(root.next);
    }

    function finishControlFailure() {
        root.check(model.result !== null && model.handoff !== null, "Failed ack retains result and handoff");
        root.check(!model.busy && root.snapshotRequests === 0, "Ack failure cannot loop automatically");
        Qt.callLater(root.next);
    }

    function complete() {
        if (root.completed) return;
        root.completed = true;
        console.info("Operation owner native tests: PASS (" + root.assertions + " assertions)");
        Qt.quit();
    }

    Component { id: integratedComponent; SystemManagementModel {} }
    Connections {
        target: root.integrated
        function onSnapshotStateChanged() {
            if (root.delayedSnapshot && root.sawLateAck && root.integrated.snapshotState === "ready") {
                Qt.callLater(function() {
                    root.check(root.integrated.terminalHandoff === null && root.integrated.activeOperation === null,
                        "Delayed snapshot cannot restore acknowledged UI state");
                    root.check(!root.integrated.operation.controlOwned && !root.integrated.operation.blocked,
                        "Delayed snapshot cannot send a redundant acknowledgment or show failure");
                    root.check(root.integrated.operation.state === "result", "Verified result survives delayed discovery");
                    root.complete();
                });
            }
        }
    }
    Connections {
        target: root.integrated === null ? null : root.integrated.operation
        function onStateChanged() {
            if (root.delayedSnapshot) {
                if (root.integrated.operation.state === "observing" && !root.lateSnapshotOpened) {
                    root.lateSnapshotOpened = true;
                    lateSnapshotTimer.start();
                }
                return;
            }
            if (root.incompleteRecovery && root.integrated.operation.blocked) {
                root.check(root.integrated.operation.retries === 3, "Incomplete recovery exhausts exactly three retries");
                root.check(root.integrated.generation.length === 64 && root.integrated.errors.length === 1,
                    "Incomplete recovery preserves the readable snapshot and diagnostic");
                root.check(root.integrated.recoveryProvider.status === "partial", "Incomplete recovery stays visible");
                root.check(root.integrated.operation.result === null, "Incomplete recovery never fabricates completion");
                root.complete();
                return;
            }
            if (root.closeRetry) {
                if (root.integrated.operation.state === "recovering" && !root.closedDuringRetry) {
                    root.closedDuringRetry = true;
                    closeRetryTimer.start();
                }
                return;
            }
            if (root.integrated.operation.state === "observing") {
                root.check(!root.integrated.settingsVisible, "Startup recovery works before Settings opens");
                if (root.reloaded) {
                    root.integrated.openSettings();
                    root.integrated.closeSettings();
                    root.check(root.integrated.operation.streamOwned, "Pane closure preserves the root watcher");
                }
            }
            if (root.failedStart && root.integrated.operation.blocked && model.blocked)
                Qt.callLater(root.finishFailure);
        }
        function onProgressChanged() {
            if (root.closeRetry || root.delayedSnapshot) return;
            if (!root.reloaded && root.integrated.operation.progress !== null
                    && root.integrated.operation.progress.state === "pending") reloadTimer.start();
        }
        function onAcknowledged(operationId) {
            if (root.delayedSnapshot) {
                root.check(!root.sawLateAck, "The committed handoff is acknowledged exactly once");
                root.sawLateAck = true;
                return;
            }
            if (root.closeRetry) {
                root.check(root.closedDuringRetry && !root.integrated.settingsVisible,
                    "Recovery continues after opening and closing during backoff");
                root.check(root.integrated.operation.result.id === operationId
                    && root.integrated.operation.result.state === "succeeded", "Recovered result is exact");
                root.complete();
                return;
            }
            root.check(root.reloaded, "Reload must adopt the persisted operation");
            root.check(!root.integrated.settingsVisible, "Result is acknowledged while Settings remains closed");
            root.check(root.integrated.operation.result.id === operationId, "Integrated result is exact");
            root.complete();
        }
    }
    Timer {
        id: lateSnapshotTimer
        interval: 10
        onTriggered: root.integrated.openSettings()
    }
    Timer {
        id: closeRetryTimer
        interval: 0
        onTriggered: {
            root.integrated.openSettings();
            root.integrated.closeSettings();
            root.check(root.integrated.snapshotOwned && root.integrated.snapshotRequired,
                "Replacing a scheduled retry retains required snapshot ownership");
            root.check(root.integrated.operation.waitingSnapshot, "Recovery still waits for the required read");
        }
    }
    Timer {
        id: reloadTimer
        interval: 0
        onTriggered: {
            root.check(root.integrated.operation.streamOwned, "Reload interrupts a live observer");
            root.integrated.destroy();
            root.integrated = null;
            root.reloaded = true;
            Qt.callLater(function() { root.integrated = integratedComponent.createObject(root); });
        }
    }
    Component.onCompleted: Qt.callLater(function() {
        if (root.incompleteRecovery || root.closeRetry || root.delayedSnapshot) {
            root.integrated = integratedComponent.createObject(root);
            return;
        }
        if (root.failedStart) {
            root.integrated = integratedComponent.createObject(root);
            root.scenario = 2;
        }
        root.next();
    })
    Timer { interval: 55000; running: true; onTriggered: root.check(false, "Fixture timed out") }
}
