import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemOperationProtocol.js" as Protocol

// Root-owned operation streams and exact-ID controls. The Settings caller owns
// visible confirmation; this model accepts only fixed update commands.
Scope {
    id: root

    signal snapshotRequested()
    signal acknowledged(string operationId)
    signal discoveryInvalidated()

    property string state: "idle"
    property string detail: ""
    property var progress: null
    property var result: null
    property var audit: null
    property var operationError: null
    property var log: []
    property var handoff: null
    property var snapshotActive: null
    property var acknowledgedIds: []
    property var parser: null
    property bool streamReplay: true
    property bool streamFailed: false
    property bool terminalPending: false
    property bool snapshotKnown: false
    property bool streamOwned: false
    property bool controlOwned: false
    property bool controlFinishing: false
    property bool waitingSnapshot: false
    property bool blocked: false
    property int retries: 0
    property string controlId: ""
    property string controlPurpose: ""
    property string cancelRequestedId: ""
    property string cancelUncertainId: ""
    property string cancelConflictId: ""
    property string cancelDetail: ""
    property bool controlInvalid: false
    readonly property bool busy: streamOwned || controlOwned || waitingSnapshot || retryTimer.running
    readonly property bool canStart: root.snapshotKnown && !root.busy && !root.blocked
        && root.snapshotActive === null && root.handoff === null
    readonly property bool canCancel: root.streamOwned && !root.controlOwned && !root.streamFailed
        && !root.terminalPending && root.log.length > 0 && root.progress !== null && root.progress.cancelable
        && (root.progress.kind === "update" || root.progress.kind === "refresh")
        && root.progress.state !== "cancel-requested" && root.cancelRequestedId !== root.progress.id
        && root.cancelUncertainId !== root.progress.id
        && root.cancelConflictId !== root.progress.id

    function matches(left, right) {
        return left !== null && right !== null && left.id === right.id
            && left.actionId === right.actionId && left.kind === right.kind;
    }

    function wasAcknowledged(operationId) {
        return root.acknowledgedIds.indexOf(operationId) >= 0;
    }

    function requestSnapshot() {
        root.waitingSnapshot = true;
        root.snapshotRequested();
    }

    function resetRecovery() {
        retryTimer.stop();
        root.retries = 0;
        root.blocked = false;
    }

    function recover(reason) {
        root.waitingSnapshot = false;
        root.detail = reason;
        if (root.retries >= 3) {
            root.blocked = true;
            root.state = "failure";
            root.detail += ". Open System Settings and reload status to retry recovery.";
            return;
        }
        root.state = "recovering";
        retryTimer.interval = [1000, 2000, 4000][root.retries++];
        retryTimer.restart();
    }

    function snapshotFailed() {
        root.snapshotKnown = false;
        root.waitingSnapshot = false;
        if (root.streamOwned || root.controlOwned || root.blocked || retryTimer.running) return;
        root.recover("Operation recovery could not read complete journal evidence");
    }

    // Only fully accepted snapshots may enter this method. A live stream is
    // the sole observer even before it emits its first operation identity.
    function acceptSnapshot(active, terminal) {
        root.snapshotKnown = false;
        if (active !== null && root.wasAcknowledged(active.id)) active = null;
        if (terminal !== null && root.wasAcknowledged(terminal.id)) terminal = null;
        root.waitingSnapshot = false;
        root.snapshotActive = active;
        root.handoff = terminal;
        if (root.streamOwned || root.controlOwned || root.blocked || retryTimer.running) {
            root.snapshotKnown = true;
            return;
        }
        if (terminal !== null && root.matches(terminal, root.result)) {
            root.startAcknowledgment();
        } else if (active !== null && root.matches(active, root.result)) {
            root.recover("Snapshot still reports a completed operation as active");
        } else if (active !== null || terminal !== null) {
            const target = active !== null ? active : terminal;
            root.parser = Protocol.create(target.id, target.actionId);
            root.progress = null;
            root.log = [];
            root.streamOwned = true;
            root.streamReplay = true;
            root.streamFailed = false;
            root.terminalPending = false;
            if (root.cancelRequestedId !== target.id) root.cancelRequestedId = "";
            if (root.cancelUncertainId !== target.id) root.cancelUncertainId = "";
            if (root.cancelConflictId !== target.id) root.cancelConflictId = "";
            if (!root.cancelRequestedId && !root.cancelUncertainId && !root.cancelConflictId) root.cancelDetail = "";
            if (active !== null) root.discoveryInvalidated();
            root.progress = active;
            root.state = "observing";
            root.detail = "Observing " + target.actionId;
            watchProcess.command = Commands.systemManagementCommand("watch-operation", [target.id]);
            Qt.callLater(function() { if (root.streamOwned) watchProcess.running = true; });
        } else {
            root.retries = 0;
            root.progress = null;
            root.state = root.result === null ? "idle" : "result";
            root.detail = root.result === null ? "" : root.result.detail;
        }
        root.snapshotKnown = true;
    }

    // This internal entry point is not exposed by IPC. The Settings caller
    // also validates visible confirmation, fresh discovery and availability.
    function startUpdate(action, generation) {
        // Recheck fields rather than a UI binding during reentrant publication.
        if (!root.snapshotKnown || root.streamOwned || root.controlOwned || root.waitingSnapshot
                || root.blocked || retryTimer.running || root.snapshotActive !== null || root.handoff !== null
                || typeof generation !== "string"
                || (action !== "updates-refresh" && action !== "updates-install-all")
                || (action === "updates-install-all" ? !/^[0-9a-f]{64}$/.test(generation) : generation !== ""))
            return false;
        const command = Commands.systemManagementCommand(action,
            action === "updates-install-all" ? [generation] : []);
        root.snapshotKnown = false;
        root.parser = Protocol.create("", action);
        root.progress = null;
        root.log = [];
        root.streamOwned = true;
        root.streamReplay = false;
        root.streamFailed = false;
        root.terminalPending = false;
        root.result = null;
        root.audit = null;
        root.operationError = null;
        root.cancelRequestedId = "";
        root.cancelUncertainId = "";
        root.cancelConflictId = "";
        root.cancelDetail = "";
        root.state = "observing";
        root.detail = "Starting " + action;
        watchProcess.command = command;
        root.discoveryInvalidated();
        Qt.callLater(function() { if (root.streamOwned) watchProcess.running = true; });
        return true;
    }

    function consume(data) {
        if (!root.streamOwned) return;
        if (!Protocol.consume(root.parser, data)) {
            root.streamFailed = true;
            root.detail = root.parser.failure;
            watchProcess.signal(9);
            return;
        }
        // A terminal row is provisional until EOF, audit, completion AND the
        // exit status pass. Never display it as successful or acknowledge it.
        if (root.parser.operation !== null && Protocol.terminal(root.parser.operation.state)) {
            root.terminalPending = true;
            root.state = "verifying";
            root.detail = "Verifying the complete operation result...";
        }
        for (let i = root.parser.records.length - 1; i >= 0; i--) {
            if (!Protocol.terminal(root.parser.records[i].state)) {
                root.progress = root.parser.records[i];
                break;
            }
        }
        root.log = root.parser.records.filter(record => !Protocol.terminal(record.state));
    }

    function finishWatch(exitCode, normalExit) {
        if (!root.streamOwned) return;
        if (root.parser.expectedAction === "updates-refresh" || root.parser.expectedAction === "updates-install-all")
            root.discoveryInvalidated();
        if (!Protocol.finish(root.parser, exitCode, normalExit, root.streamReplay)) {
            root.streamFailed = true;
            root.recover(exitCode === 3 ? "Operation watch target changed (conflict)" : root.parser.failure);
            root.streamOwned = false;
            return;
        }
        root.result = root.parser.operation;
        root.audit = root.parser.audit;
        root.operationError = root.parser.error;
        root.progress = null;
        root.waitingSnapshot = true;
        root.state = "result";
        root.detail = root.result.detail;
        root.log = root.parser.records.slice();
        root.streamOwned = false;
        // Even a replay that began from an active snapshot needs a committed
        // handoff snapshot before ack. Never infer that handoff from stdout.
        Qt.callLater(function() {
            if (root.matches(root.handoff, root.result) && !root.controlOwned) root.startAcknowledgment();
            else root.requestSnapshot();
        });
    }

    function cancelTarget() {
        const current = root.parser === null ? null : root.parser.operation;
        if (!root.streamOwned || root.controlOwned || root.streamFailed || current === null
                || root.parser.failure.length > 0 || Protocol.terminal(current.state)
                || (current.kind !== "update" && current.kind !== "refresh")
                || !current.cancelable || current.state === "cancel-requested"
                || root.state === "verifying" || root.cancelRequestedId === current.id
                || root.cancelUncertainId === current.id || root.cancelConflictId === current.id) return null;
        return current;
    }

    function requestCancel() {
        // Recheck the parser itself: QML log/progress callbacks can run before
        // a binding catches up with the latest AllowCancel or terminal record.
        const target = root.cancelTarget();
        if (target === null) return false;
        root.controlOwned = true;
        root.controlId = target.id;
        root.controlPurpose = "cancel";
        root.controlInvalid = false;
        root.cancelDetail = "Requesting cancellation from PackageKit...";
        ackProcess.command = Commands.systemManagementCommand("updates-cancel", [root.controlId]);
        Qt.callLater(root.launchControl);
        return true;
    }

    function launchControl() {
        if (!root.controlOwned) return;
        controlDeadline.restart();
        ackProcess.running = true;
    }

    function finishCancellation(exitCode, normalExit) {
        const accepted = normalExit && exitCode === 0 && !root.controlInvalid;
        const unavailable = normalExit && exitCode === 3 && !root.controlInvalid;
        if (accepted) root.cancelRequestedId = root.controlId;
        // Exit 1 (or lost/malformed control output) cannot prove Cancel was not
        // dispatched. Keep a distinct guard without claiming acceptance, even
        // if a recovered same-ID stream repeats an old AllowCancel=true hint.
        if (!accepted && !unavailable) root.cancelUncertainId = root.controlId;
        // A stale target cannot be made safe by the same observer's cached
        // AllowCancel hint. Retire its control before releasing ownership;
        // recovery of a different operation can establish a new target.
        if (unavailable) root.cancelConflictId = root.controlId;
        root.cancelDetail = accepted
            ? "Cancellation requested. Waiting for PackageKit's verified terminal result."
            : unavailable
            ? "The cancellation target changed. Reloading recovery state; no cancellation was confirmed."
            : "Cancellation was not confirmed. A repeat request is blocked for this operation. Continue watching or reload status.";
        root.controlOwned = false;
        // The operation may finish and a newer handoff may arrive while this
        // control is running. Reconcile only after its final Process signals.
        Qt.callLater(function() {
            if (!root.streamOwned) {
                if (root.waitingSnapshot) return;
                if (root.snapshotKnown) root.acceptSnapshot(root.snapshotActive, root.handoff);
                else root.snapshotFailed();
            } else if (exitCode === 3) root.requestSnapshot();
        });
    }

    function startAcknowledgment() {
        if (root.streamOwned || root.controlOwned || root.blocked
                || !root.matches(root.handoff, root.result)
                || root.wasAcknowledged(root.result.id)) return;
        root.controlOwned = true;
        root.controlId = root.result.id;
        root.controlPurpose = "ack";
        root.controlInvalid = false;
        root.waitingSnapshot = false;
        root.state = "acknowledging";
        root.detail = "Acknowledging the verified operation result...";
        ackProcess.command = Commands.systemManagementCommand("ack-operation", [root.controlId]);
        Qt.callLater(root.launchControl);
    }

    function finishAcknowledgment(exitCode, normalExit) {
        if (!root.controlOwned || root.controlFinishing) return;
        root.controlFinishing = true;
        controlDeadline.stop();
        // Keep ownership until the old Process has emitted runningChanged.
        // Reentrant UI callbacks may request another control on release.
        Qt.callLater(function() { root.completeControl(exitCode, normalExit); });
    }

    function completeControl(exitCode, normalExit) {
        root.controlFinishing = false;
        if (root.controlPurpose === "cancel") {
            root.finishCancellation(exitCode, normalExit);
            return;
        }
        root.state = "result";
        if (!normalExit || exitCode !== 0 || root.controlInvalid) {
            root.blocked = true;
            root.detail = "The verified result could not be acknowledged. Reload status to retry recovery.";
            root.controlOwned = false;
            return;
        }
        if (root.matches(root.handoff, root.result)) root.handoff = null;
        if (root.snapshotActive !== null && root.snapshotActive.id === root.controlId)
            root.snapshotActive = null;
        // Match the bounded retained journal: late discovery output must not
        // resurrect an acknowledged identity or send a duplicate ack control.
        root.acknowledgedIds = root.acknowledgedIds.concat([root.controlId]).slice(-32);
        root.retries = 0;
        root.detail = root.result.detail;
        root.controlOwned = false;
        root.acknowledged(root.controlId);
        // Another client can admit or finish its operation after the helper
        // clears our handoff but before that helper exits. Do not drop a newer
        // snapshot received while the acknowledgment process was still owned.
        Qt.callLater(function() {
            if (root.snapshotActive !== null || root.handoff !== null)
                root.acceptSnapshot(root.snapshotActive, root.handoff);
        });
    }

    Timer { id: retryTimer; repeat: false; onTriggered: root.requestSnapshot() }
    Timer {
        id: controlDeadline
        interval: 10000
        repeat: false
        onTriggered: {
            root.controlInvalid = true;
            if (ackProcess.running) ackProcess.signal(9);
        }
    }

    Process {
        id: watchProcess
        stdout: StdioCollector { waitForEnd: false; onDataChanged: root.consume(data) }
        stderr: StdioCollector {
            waitForEnd: false
            onDataChanged: {
                if (root.streamOwned && data.byteLength > 8192) {
                    root.streamFailed = true;
                    Protocol.fail(root.parser, "Operation error output exceeded its limit");
                    watchProcess.signal(9);
                }
            }
        }
        onExited: (exitCode, exitStatus) => root.finishWatch(exitCode, exitStatus === 0)
        // FailedToStart has no exited signal. Normal exits finalize ownership
        // above BEFORE runningChanged. Never read retained collector data here.
        onRunningChanged: { if (!running && root.streamOwned) root.finishWatch(-1, false); }
    }
    Process {
        id: ackProcess
        stdout: StdioCollector {
            waitForEnd: false
            onDataChanged: {
                if (root.controlOwned && data.byteLength > 0) {
                    root.controlInvalid = true;
                    if (data.byteLength > 8192) ackProcess.signal(9);
                }
            }
        }
        stderr: StdioCollector {
            waitForEnd: false
            onDataChanged: {
                if (root.controlOwned && data.byteLength > 8192) {
                    root.controlInvalid = true;
                    ackProcess.signal(9);
                }
            }
        }
        onExited: (exitCode, exitStatus) => root.finishAcknowledgment(exitCode, exitStatus === 0)
        onRunningChanged: { if (!running && root.controlOwned) root.finishAcknowledgment(-1, false); }
    }
}
