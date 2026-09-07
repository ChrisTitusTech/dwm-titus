import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property string action: Quickshell.env("DWM_NATIVE_ACTION")
    property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    property string value: action === "timezone-set" ? "America/Chicago" : action === "ntp-set" ? "enabled"
        : action === "locale-set" ? "LANG=en_US.UTF-8" : ""
    property string generation: value === "" ? "" : "c".repeat(64)
    property var identity: ({ id: "op-" + "d".repeat(32), actionId: root.action,
        kind: root.action === "timezone-set" ? "timezone" : root.action === "ntp-set" ? "ntp"
            : root.action === "locale-set" ? "locale" : "delegate" })
    property int assertions: 0
    property int invalidations: 0
    property int snapshots: 0
    property bool verifying: false
    property bool done: false

    function check(condition, detail) {
        assertions++;
        if (!condition) {
            console.error("Native action owner FAILED: " + action + "/" + scenario + ": " + detail);
            throw new Error(detail);
        }
    }

    function finish() {
        if (done) return;
        done = true;
        check(!model.busy && !model.blocked && model.canStart, "Verified acknowledgment releases owner");
        check(verifying && model.audit !== null, "Terminal result requires audit and process exit");
        check(invalidations >= 3, "Origin, completion and acknowledgment invalidate only the action provider");
        check(model.result.state === (scenario === "denied" ? "permission-denied"
            : ["rejected", "unsupported", "wrong-exit"].indexOf(scenario) >= 0 ? "failed" : "succeeded"), "Typed outcome preserved");
        check(snapshots === (scenario === "uncertain" || scenario === "wrong-exit" ? 2 : 1), "Recovery never reissues origin");
        if (identity.kind === "delegate" && model.result.state === "succeeded")
            check(model.result.detail.indexOf("not verified") >= 0, "Accepted launch is not completed administration");
        model.acceptSnapshot(null, identity);
        check(model.handoff === null && !model.controlOwned, "Acknowledged identity cannot be replayed again");
        console.info("Native action owner tests: PASS (" + action + "/" + scenario + ", " + assertions + " assertions)");
        Qt.quit();
    }

    function run() {
        model.acceptSnapshot(null, null);
        for (const args of [["unknown", "", ""], ["watch-operation", identity.id, ""],
                ["timezone-set", "../etc", generation], ["timezone-set", "America//Chicago", "c".repeat(64)],
                ["timezone-set", "UTC\n", "c".repeat(64)], ["timezone-set", "x".repeat(256), "c".repeat(64)],
                ["ntp-set", "yes", "c".repeat(64)], ["locale-set", "LANG=", "c".repeat(64)],
                ["locale-set", "LANG=en_US\n", "c".repeat(64)], ["locale-set", "LANG=" + "x".repeat(129), "c".repeat(64)],
                ["accounts-open", "extra", ""], ["password-open", "", "c".repeat(64)],
                ["ntp-set", "enabled", "c".repeat(64) + "\n"], ["ntp-set", "enabled", "C".repeat(64)],
                ["timezone-set", null, "c".repeat(64)], ["sources-open", "", null]]) {
            check(!model.startNative(args[0], args[1], args[2]), "Invalid native entry rejected");
            check(!model.startOperation(args[0], args[1], args[2]), "Shared entry also validates arguments");
        }
        check(!model.startNative("updates-refresh", "", ""), "Native entry excludes updates");
        check(!model.startUpdate(action, generation), "Update entry excludes native actions");
        for (const field of ["streamOwned", "controlOwned", "waitingSnapshot", "blocked"]) {
            model[field] = true;
            check(!model.startNative(action, value, generation), field + " blocks origin");
            model[field] = false;
        }
        for (const field of ["snapshotActive", "handoff"]) {
            model[field] = identity;
            check(!model.startNative(action, value, generation), field + " blocks origin");
            model[field] = null;
        }
        model.snapshotKnown = false;
        check(!model.startNative(action, value, generation), "Unknown journal blocks origin");
        model.snapshotKnown = true;
        check(model.startNative(action, value, generation), "Fixed native origin accepted");
        check(!model.startNative(action, value, generation), "Pre-output ownership prevents duplicate origin");
        check(!model.requestCancel(), "Native origin never sends cancellation");
    }

    SystemOperationModel {
        id: model
        onDiscoveryInvalidated: actionId => {
            root.invalidations++;
            root.check(actionId === root.action, "Invalidation retains fixed action identity");
            root.check(!model.startNative(root.action, root.value, root.generation), "Reentrant invalidation cannot overlap owner");
        }
        onSnapshotRequested: {
            root.snapshots++;
            model.acceptSnapshot(model.result === null ? root.identity : null, model.result === null ? null : root.identity);
        }
        onProgressChanged: root.check(!model.canCancel && !model.requestCancel(), "Live native progress is not cancelable")
        onStateChanged: {
            if (state === "verifying") {
                root.verifying = true;
                root.check(model.result === null, "Terminal bytes remain provisional");
            }
        }
        onAcknowledged: Qt.callLater(root.finish)
    }
    Component.onCompleted: Qt.callLater(root.run)
}
