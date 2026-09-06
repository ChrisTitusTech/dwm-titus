import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property string scenario: Quickshell.env("DWM_UPDATE_ACTION_SCENARIO")
    property int assertions: 0
    property int snapshots: 0
    property int invalidations: 0
    property bool cancelSent: false
    property bool sawCancelable: false
    property bool sawRevoked: false
    property bool sawVerifying: false
    property bool sawHandoffDuringCancel: false
    property bool retryProbed: false
    property bool sawUncertainRecovery: false
    property bool seededActive: false
    property bool done: false
    property var identity: ({id: "op-" + "b".repeat(32), actionId: root.scenario === "install"
        ? "updates-install-all" : "updates-refresh", kind: root.scenario === "install" ? "update" : "refresh"})

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Update action owner FAILED: " + root.scenario + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function finish() {
        if (root.done) return;
        root.done = true;
        root.check(!model.busy && !model.blocked && model.canStart, "Verified recovery releases admission");
        root.check(root.sawVerifying && model.audit !== null, "Audit and process exit verify the result");
        root.check(root.invalidations >= 2, "Origin and completion invalidate discovery without global signals");
        root.check(model.log.length > 1 && model.log[model.log.length - 1].state === model.result.state,
            "Bounded log publishes the verified terminal result only after exit");
        const expected = root.scenario === "denied" ? "permission-denied"
            : root.scenario === "rejected" || root.scenario === "wrong-exit" ? "failed"
            : root.scenario === "cancel-accepted" ? "canceled" : "succeeded";
        root.check(model.result.state === expected, "Origin exit/result contract preserves failure and cancellation");
        if (root.scenario === "rejected" || root.scenario === "wrong-exit")
            root.check(model.operationError.code === "conflict", "Request failure retains typed diagnostics");
        if (root.scenario === "uncertain" || root.scenario === "wrong-exit")
            root.check(root.snapshots === 2, "Uncertain origin recovers by watch, not another origin");
        if (root.scenario === "cancel-recovery" || root.scenario === "cancel-recovery-denied")
            root.check(root.snapshots === 2 && model.retries === 0, "Failed read during cancellation resumes bounded recovery");
        if (root.scenario === "cancel-uncertain-recover")
            root.check(root.snapshots === 2 && root.sawUncertainRecovery, "Same-ID recovery retains uncertain cancellation ownership");
        if (root.scenario === "cancel-pending-snapshot")
            root.check(root.snapshots === 1 && model.retries === 0, "Awaited handoff is not delayed by cached-active recovery");
        if (root.scenario === "cancel-race")
            root.check(root.sawHandoffDuringCancel, "Terminal handoff is retained while cancellation owns control");
        if (root.scenario.indexOf("cancel-") === 0) {
            root.check(root.cancelSent && root.sawCancelable, "Only live AllowCancel enables the exact-ID control");
            const accepted = root.scenario === "cancel-accepted" || root.scenario === "cancel-race"
                || root.scenario === "cancel-recovery" || root.scenario === "cancel-pending-snapshot";
            root.check(accepted ? model.cancelRequestedId === root.identity.id : model.cancelRequestedId === "",
                "Only a valid successful control claims an accepted request");
            root.check(accepted || root.scenario === "cancel-conflict"
                ? model.cancelUncertainId === "" : model.cancelUncertainId === root.identity.id,
                "Unconfirmed dispatch has its own exact-ID guard, separate from acceptance");
            root.check(model.cancelDetail.indexOf(accepted ? "Waiting" : "not confirmed") >= 0
                || root.scenario === "cancel-conflict", "Cancellation outcome has separate guidance");
        }
        if (root.scenario === "revoked") root.check(root.sawCancelable && root.sawRevoked, "Revoked AllowCancel disables the control");
        console.info("Update action owner native tests: PASS (" + root.scenario + ", " + root.assertions + " assertions)");
        Qt.quit();
    }

    SystemOperationModel {
        id: model
        onDiscoveryInvalidated: {
            root.invalidations++;
            root.check(!model.startUpdate("updates-refresh", ""), "Reentrant invalidation cannot overlap an owned stream");
        }
        onSnapshotRequested: {
            root.snapshots++;
            if (root.scenario === "cancel-pending-snapshot" && root.snapshots === 1) {
                delayedSnapshot.start();
                return;
            }
            if (root.scenario.indexOf("cancel-recovery") === 0
                    && (root.snapshots === 1 || root.scenario === "cancel-recovery-failure")) {
                root.check(!model.streamOwned && model.result !== null, "Terminal result precedes the failed recovery read");
                if (root.snapshots === 1) root.check(model.controlOwned, "Cancellation still owns control when the read fails");
                model.snapshotFailed();
                return;
            }
            if (root.scenario === "failed-start") model.acceptSnapshot(root.identity, null);
            else if (model.result !== null) {
                if (model.controlOwned && model.controlPurpose === "cancel") root.sawHandoffDuringCancel = true;
                model.acceptSnapshot(null, root.scenario === "rejected" ? null : root.identity);
                if (root.scenario === "rejected") Qt.callLater(root.finish);
            } else model.acceptSnapshot(root.identity, null);
        }
        onWaitingSnapshotChanged: {
            if (!waitingSnapshot && root.snapshots > 0 && model.result === null && !model.streamOwned)
                root.check(!model.startUpdate("updates-refresh", ""), "Recovery publication cannot admit a reentrant origin");
        }
        onControlIdChanged: {
            root.check(!model.requestCancel(), "Control identity publication cannot admit a duplicate control");
        }
        onControlOwnedChanged: {
            if (!controlOwned && model.controlPurpose === "cancel" && model.streamOwned
                    && root.scenario !== "cancel-conflict" && !root.retryProbed) {
                root.retryProbed = true;
                root.check(!model.requestCancel(), "Accepted or uncertain cancellation cannot be dispatched twice");
            }
        }
        onLogChanged: {
            if (!model.streamOwned) return;
            const current = model.parser.operation;
            if (current === null) return;
            if (current.cancelable) root.sawCancelable = true;
            if (root.scenario === "cancel-pending-snapshot" && current.cancelable && !root.seededActive) {
                root.seededActive = true;
                model.acceptSnapshot(root.identity, null);
            }
            if (root.scenario === "cancel-uncertain-recover" && model.streamReplay && current.cancelable) {
                root.sawUncertainRecovery = true;
                root.check(!model.canCancel && !model.requestCancel(), "New AllowCancel progress cannot repeat an ambiguous control");
            }
            if (current.detail === "Cancellation unsafe") root.sawRevoked = true;
            if (!current.cancelable) root.check(!model.requestCancel(), "Latest parser state rejects stale cancellation callbacks");
            if (model.state === "verifying") {
                root.check(model.result === null, "Terminal text cannot publish result before EOF");
                root.check(model.log.every(record => record.state !== "succeeded" && record.state !== "failed"
                    && record.state !== "permission-denied" && record.state !== "canceled"), "Provisional terminal is absent from logs");
            }
            if (root.scenario.indexOf("cancel-") === 0 && model.canCancel && !root.cancelSent) {
                root.cancelSent = true;
                root.check(model.requestCancel(), "Explicit live cancellation starts one control");
                root.check(!model.requestCancel(), "Duplicate cancellation is rejected while control owns process");
                root.check(model.streamOwned && model.result === null, "Cancellation request does not stop the observer or fabricate completion");
            }
        }
        onStateChanged: {
            if (state === "verifying") {
                root.sawVerifying = true;
                root.check(!model.canCancel && !model.requestCancel(), "Provisional terminal revokes cancellation");
            }
            if (state === "failure") Qt.callLater(function() {
                const failedRead = root.scenario === "cancel-recovery-failure";
                root.check(root.scenario === "failed-start" || failedRead, "Only unavailable evidence exhausts recovery");
                root.check(root.snapshots === (failedRead ? 4 : 3) && !model.busy && model.blocked,
                    "Exhaustion preserves exactly three bounded recovery attempts");
                root.check((failedRead ? model.result !== null : model.result === null) && !model.canStart,
                    "Unknown journal state preserves verified results without admitting a replacement");
                console.info("Update action owner native tests: PASS (" + root.scenario + ", " + root.assertions + " assertions)");
                root.done = true;
                Qt.quit();
            });
        }
        onAcknowledged: Qt.callLater(root.finish)
    }

    Component.onCompleted: {
        root.check(!model.startUpdate("updates-refresh", ""), "No admission before an accepted empty recovery snapshot");
        model.acceptSnapshot(null, null);
        root.check(model.canStart, "Known empty recovery permits an internal confirmed call");
        root.check(!model.startUpdate("timezone-set", "") && !model.startUpdate("updates-cancel", ""), "Origin allowlist excludes unrelated commands");
        root.check(!model.startUpdate("updates-install-all", "wrong") && !model.startUpdate("updates-refresh", "c".repeat(64)), "Reject malformed and unexpected generation arguments");
        model.snapshotFailed();
        root.check(!model.startUpdate("updates-refresh", ""), "Lost journal evidence cannot admit an origin");
        model.resetRecovery();
        model.acceptSnapshot(null, null);
        model.cancelUncertainId = "op-" + "d".repeat(32);
        model.cancelRequestedId = "op-" + "d".repeat(32);
        root.check(model.startUpdate(root.identity.actionId, root.scenario === "install" ? "c".repeat(64) : ""), "Fixed update command starts once");
        root.check(model.cancelUncertainId === "" && model.cancelRequestedId === "", "A new explicit origin clears previous-operation guards");
        root.check(!model.startUpdate("updates-refresh", ""), "No overlap before first output");
    }
    Timer {
        id: delayedSnapshot
        interval: 200
        onTriggered: {
            root.check(!model.controlOwned && model.waitingSnapshot && model.retries === 0,
                "Control completion must wait for the replacement snapshot, not reuse cached active state");
            model.acceptSnapshot(null, root.identity);
            root.check(model.state === "acknowledging", "Fresh handoff can acknowledge immediately without an extra retry");
        }
    }
    Timer { interval: 18000; running: true; onTriggered: root.check(false, "Scenario timed out in " + model.state) }
}
