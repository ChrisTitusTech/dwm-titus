import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property string action: Quickshell.env("DWM_NATIVE_ACTION")
    property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    property int stage: 0
    property int assertions: 0
    property bool dispatchProbe: false
    property bool done: false

    function check(value, detail) {
        assertions++;
        if (!value) {
            console.error("Delegate confirmation FAILED: " + action + "/" + scenario + ": " + detail);
            throw new Error(detail);
        }
    }

    function finish() {
        if (done) return;
        done = true;
        check(!model.settingsVisible && !model.operation.busy, "Closed fixture releases completed ownership");
        check(!model.discoveryModels().some(item => item.monitorOwned), "Closed fixture stops subscriptions");
        if (scenario !== "close-dispatch") {
            check(model.operation.result !== null && model.operation.audit !== null, "Result requires verified audit");
            check(model.operation.result.state === (scenario === "denied" ? "permission-denied"
                : scenario === "unsupported" ? "failed" : "succeeded"), "Typed result preserved");
            if (scenario === "success")
                check(model.operation.result.detail.indexOf("not verified") >= 0, "Launch acceptance is not completed administration");
        } else check(model.operation.result === null, "Reentrant closure prevents dispatch");
        console.info("Delegate confirmation tests: PASS (" + action + "/" + scenario + ", " + assertions + " assertions)");
        Qt.quit();
    }

    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) {
            check(!model.prepareDelegate(action) && !model.confirmDelegate(), "Closed startup cannot dispatch");
            stage = 1;
            model.openSettings();
        } else if (stage === 1 && !model.busy && model.discoveryModels().every(item => item.fresh)) {
            stage = -1;
            check(model.recoveryProvider.status === "partial" && model.delegateActionReason(action) === "",
                "Native offers admit independently of update-only recovery limitations");
            for (const invalid of ["unknown", "updates-refresh", "timezone-set", "ntp-set", "locale-set", "watch-operation"])
                check(!model.prepareDelegate(invalid), "Closed delegated action allowlist");
            for (const field of ["snapshotOwned", "snapshotPending", "requiredPending", "discoveryBatch"]) {
                model[field] = true;
                check(!model.prepareDelegate(action), field + " blocks preparation");
                model[field] = false;
            }
            model.operation.snapshotKnown = false;
            check(!model.prepareDelegate(action), "Unknown journal blocks preparation");
            model.operation.snapshotKnown = true;
            const monitor = model.delegateDiscovery(action);
            for (const field of ["ready", "failed"]) {
                const previous = monitor[field];
                monitor[field] = field === "failed";
                check(!model.prepareDelegate(action), "Unavailable monitor " + field + " blocks preparation");
                monitor[field] = previous;
            }
            for (const change of [["enabled", false], ["unresolved", true], ["phase", "initial-pending"]]) {
                const previous = monitor.cycle[change[0]];
                monitor.cycle[change[0]] = change[1];
                check(!model.prepareDelegate(action), "Source cycle " + change[0] + " blocks before binding publication");
                monitor.cycle[change[0]] = previous;
            }
            const actions = model.actions;
            model.actions = actions.map(item => item.id === action ? Object.assign({}, item, {availability: "unavailable", detail: ""}) : item);
            check(!model.prepareDelegate(action), "Unavailable offer blocks without requiring detail");
            model.actions = actions;
            model.updateConfirmation = {actionId: "updates-refresh"};
            check(!model.prepareDelegate(action), "Update prompt blocks delegated preparation");
            model.updateConfirmation = null;
            check(model.prepareDelegate(action), "Fixed action prepares without dispatch");
            check(!model.prepareDelegate(action) && !model.prepareUpdate("updates-refresh"), "Prompt rejects replacement and update overlap");
            check(model.confirmationMessage === "Finish or dismiss the current confirmation first.",
                "Visible prompt conflict does not ask to reopen Settings");
            check(model.operation.result === null && !model.operation.busy, "Preparation is passive");
            model.discardDelegate();
            check(!model.confirmDelegate(), "Discarded prompt cannot dispatch");
            check(model.prepareDelegate(action), "Prepare generation check");
            const generation = model.generation;
            model.generation = "e".repeat(64);
            check(!model.confirmDelegate() && model.nativeConfirmation === null, "Changed generation retires prompt");
            model.generation = generation;
            check(model.prepareDelegate(action), "Prepare request identity check");
            model.requestGeneration++;
            check(!model.confirmDelegate(), "Changed request identity blocks dispatch");
            check(model.prepareDelegate(action), "Prepare epoch check");
            model.delegateDiscovery(action).cycle.epoch++;
            check(!model.confirmDelegate(), "Changed provider epoch blocks dispatch");
            check(model.prepareDelegate(action), "Prepare invalidation check");
            model.invalidateNativeConfirmation("locale");
            check(model.nativeConfirmation !== null, "Unrelated optional domain does not retire prompt");
            model.discoveryBatch = true;
            model.delegateDiscovery(action).invalidate();
            check(model.nativeConfirmation === null && !model.confirmDelegate(), "Owning event immediately retires prompt");
            model.discoveryBatch = false;
            stage = 2;
            model.refresh();
        } else if (stage === 2 && !model.busy && model.delegateActionReason(action) === "") {
            stage = -1;
            check(model.prepareDelegate(action), "Fresh explicit confirmation available");
            dispatchProbe = true;
            const started = model.confirmDelegate();
            check(!dispatchProbe && started === (scenario !== "close-dispatch"), "Dispatch guard survives prompt callbacks");
            check(!model.confirmDelegate(), "Duplicate confirmation cannot dispatch");
            model.closeSettings();
            if (started) check(model.operation.streamOwned, "Pane closure retains started owner");
            stage = 3;
        } else if (stage === 3 && !model.busy && !model.operation.busy
                && !model.discoveryModels().some(item => item.monitorOwned)
                && (scenario === "close-dispatch" || model.operation.acknowledgedIds.length === 1)) finish();
    }

    SystemManagementModel {
        id: model
        onNativeConfirmationChanged: {
            if (nativeConfirmation !== null || !root.dispatchProbe) return;
            root.dispatchProbe = false;
            root.check(dispatchingNative && !model.prepareDelegate(root.action)
                && !model.prepareUpdate("updates-refresh") && !model.confirmDelegate(), "Reentrant callback cannot overlap dispatch");
            if (root.scenario === "close-dispatch") model.closeSettings();
        }
    }
    Timer { interval: 20; running: true; repeat: true; onTriggered: root.advance() }
    Timer { interval: 15000; running: true; onTriggered: { console.error("Delegate confirmation FAILED: timeout"); Qt.quit(); } }
}
