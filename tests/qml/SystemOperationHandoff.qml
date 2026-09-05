import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property int assertions: 0
    property int acknowledgments: 0
    property int snapshots: 0
    property var first: target(12)
    property var second: target(13)
    property var third: target(14)

    function target(value) {
        return { id: "op-" + value.toString(16).padStart(32, "0"),
            actionId: "updates-refresh", kind: "refresh", state: "running",
            percent: "30", cancelable: false, detail: "Concurrent fixture" };
    }

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Operation handoff FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    SystemOperationModel {
        id: model
        onStateChanged: {
            if (state === "acknowledging" && controlId !== root.third.id) snapshotTimer.restart();
        }
        onSnapshotRequested: {
            root.snapshots++;
            root.check(result.id === root.second.id && root.acknowledgments === 1,
                "Only the newly active owner needs a fresh handoff snapshot");
            model.acceptSnapshot(null, root.second);
        }
        onAcknowledged: operationId => {
            const expected = [root.first.id, root.second.id, root.third.id][root.acknowledgments++];
            root.check(operationId === expected, "New owners must be observed and acknowledged in order");
            root.check(result.id === operationId, "Ack must retain the exact verified result");
            if (root.acknowledgments === 3) {
                root.check(root.snapshots === 1, "Retained handoff replay needs no redundant snapshot");
                const latest = model.result;
                model.acceptSnapshot(null, root.first);
                root.check(!model.controlOwned && model.handoff === null, "Late handoff cannot acknowledge twice");
                model.acceptSnapshot(root.second, null);
                root.check(!model.streamOwned && model.snapshotActive === null, "Late active row cannot resurrect progress");
                root.check(model.result === latest && !model.blocked, "Late snapshots preserve the latest verified result");
                root.check(model.acknowledgedIds.length === 3, "Successful acknowledgment identities are retained");
                console.info("Operation handoff native tests: PASS (" + root.assertions + " assertions)");
                Qt.quit();
            }
        }
    }

    Timer {
        id: snapshotTimer
        interval: 20
        onTriggered: {
            root.check(model.controlOwned && !model.streamOwned, "One acknowledgment owns the control channel");
            if (model.controlId === root.first.id) model.acceptSnapshot(root.second, null);
            else model.acceptSnapshot(null, root.third);
            root.check(!model.streamOwned, "A new watcher must wait for the old acknowledgment exit");
        }
    }
    Component.onCompleted: Qt.callLater(function() { model.acceptSnapshot(null, root.first); })
    Timer { interval: 5000; running: true; onTriggered: root.check(false, "Deferred snapshot was lost") }
}
