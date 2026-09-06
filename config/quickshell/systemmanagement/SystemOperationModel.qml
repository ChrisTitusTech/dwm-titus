import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemOperationProtocol.js" as Protocol

// Root-owned observation and journal acknowledgment; never starts a mutation.
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
    property var handoff: null
    property var snapshotActive: null
    property var acknowledgedIds: []
    property var parser: null
    property bool streamOwned: false
    property bool controlOwned: false
    property bool waitingSnapshot: false
    property bool blocked: false
    property int retries: 0
    property string controlId: ""
    property bool controlInvalid: false
    readonly property bool busy: streamOwned || controlOwned || waitingSnapshot || retryTimer.running

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
        root.waitingSnapshot = false;
        if (root.streamOwned || root.controlOwned || root.blocked || retryTimer.running) return;
        root.recover("Operation recovery could not read complete journal evidence");
    }

    // Only fully accepted snapshots may enter this method. A live stream is
    // the sole observer even before it emits its first operation identity.
    function acceptSnapshot(active, terminal) {
        if (active !== null && root.wasAcknowledged(active.id)) active = null;
        if (terminal !== null && root.wasAcknowledged(terminal.id)) terminal = null;
        root.waitingSnapshot = false;
        root.snapshotActive = active;
        root.handoff = terminal;
        if (root.streamOwned || root.controlOwned || root.blocked || retryTimer.running) return;
        if (terminal !== null && root.matches(terminal, root.result)) {
            root.startAcknowledgment();
        } else if (active !== null && root.matches(active, root.result)) {
            root.recover("Snapshot still reports a completed operation as active");
        } else if (active !== null || terminal !== null) {
            const target = active !== null ? active : terminal;
            root.parser = Protocol.create(target.id, target.actionId);
            root.streamOwned = true;
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
    }

    function consume(data) {
        if (!root.streamOwned) return;
        if (!Protocol.consume(root.parser, data)) {
            root.detail = root.parser.failure;
            watchProcess.signal(9);
            return;
        }
        // A terminal row is provisional until EOF, audit, completion AND the
        // exit status pass. Never display it as successful or acknowledge it.
        for (let i = root.parser.records.length - 1; i >= 0; i--) {
            if (!Protocol.terminal(root.parser.records[i].state)) {
                root.progress = root.parser.records[i];
                break;
            }
        }
        if (root.parser.operation !== null && Protocol.terminal(root.parser.operation.state)) {
            root.state = "verifying";
            root.detail = "Verifying the complete operation result...";
        }
    }

    function finishWatch(exitCode, normalExit) {
        if (!root.streamOwned) return;
        if (root.parser.expectedAction === "updates-refresh" || root.parser.expectedAction === "updates-install-all")
            root.discoveryInvalidated();
        root.streamOwned = false;
        if (!Protocol.finish(root.parser, exitCode, normalExit, true)) {
            root.recover(exitCode === 3 ? "Operation watch target changed (conflict)" : root.parser.failure);
            return;
        }
        root.result = root.parser.operation;
        root.audit = root.parser.audit;
        root.operationError = root.parser.error;
        root.progress = null;
        root.state = "result";
        root.detail = root.result.detail;
        // Even a replay that began from an active snapshot needs a committed
        // handoff snapshot before ack. Never infer that handoff from stdout.
        Qt.callLater(function() {
            if (root.matches(root.handoff, root.result)) root.startAcknowledgment();
            else root.requestSnapshot();
        });
    }

    function startAcknowledgment() {
        if (root.streamOwned || root.controlOwned || root.blocked
                || !root.matches(root.handoff, root.result)
                || root.wasAcknowledged(root.result.id)) return;
        root.controlId = root.result.id;
        root.controlInvalid = false;
        root.controlOwned = true;
        root.state = "acknowledging";
        root.detail = "Acknowledging the verified operation result...";
        ackProcess.command = Commands.systemManagementCommand("ack-operation", [root.controlId]);
        Qt.callLater(function() {
            if (root.controlOwned) {
                controlDeadline.restart();
                ackProcess.running = true;
            }
        });
    }

    function finishAcknowledgment(exitCode, normalExit) {
        if (!root.controlOwned) return;
        controlDeadline.stop();
        root.controlOwned = false;
        root.state = "result";
        if (!normalExit || exitCode !== 0 || root.controlInvalid) {
            root.blocked = true;
            root.detail = "The verified result could not be acknowledged. Reload status to retry recovery.";
            return;
        }
        if (root.matches(root.handoff, root.result)) root.handoff = null;
        // Match the bounded retained journal: late discovery output must not
        // resurrect an acknowledged identity or send a duplicate ack control.
        root.acknowledgedIds = root.acknowledgedIds.concat([root.controlId]).slice(-32);
        root.retries = 0;
        root.detail = root.result.detail;
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
