import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property string action: Quickshell.env("DWM_NATIVE_ACTION")
    property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    readonly property string kind: action === "locale-set" ? "locale" : "timezone"
    readonly property string argument: action === "locale-set" ? "LANG=en_US.UTF-8"
        : action === "ntp-set" ? "enabled" : "America/Chicago"
    property int stage: 0
    property int assertions: 0
    property bool done: false
    property bool dispatchProbe: false
    property bool publicationProbe: false
    property int priorGeneration: 0

    function check(value, detail) {
        assertions++;
        if (!value) {
            done = true;
            console.error("Regional settings FAILED: " + action + "/" + scenario + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function finish() {
        check(!model.settingsVisible && !model.regional.ownsPreparation(), "Closed preparation is reaped");
        check(model.regional.confirmation === null && Object.keys(model.regional.catalogs).length === 0,
            "Closure retains no prompt or hidden catalogs");
        console.info("Regional settings tests: PASS (" + action + "/" + scenario + ", " + assertions + " assertions)");
        done = true;
        Qt.quit();
    }
    function quiet() {
        return !model.snapshotOwned && !model.snapshotPending && !model.requiredPending
            && model.discoveryModels().every(item => item.fresh) && model.operation.canStart;
    }
    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) {
            check(!model.regional.requestChoices(kind) && !model.regional.prepare(action, argument), "Closed preparation rejected");
            stage = 1;
            model.openSettings();
        } else if (stage === 1 && quiet()) {
            stage = -1;
            check(model.recoveryProvider.status === "partial", "Native preparation independent of update-only recovery");
            check(!model.regional.requestChoices("unknown") && !model.regional.prepare("unknown", ""), "Closed command allowlist");
            if (action !== "ntp-set") check(!model.regional.prepare(action, argument), "Mutation requires exact fresh catalog choice");
            const monitor = model.regional.discovery(action);
            const epoch = monitor.cycle.epoch;
            monitor.cycle.unresolved = true;
            check(!model.regional.requestChoices(kind), "Source dirty cycle blocks before binding publication");
            monitor.cycle.unresolved = false;
            check(monitor.cycle.epoch === epoch, "Guard fixture retains epoch");
            model.nativeConfirmation = { actionId: "accounts-open" };
            check(!model.regional.requestChoices(kind), "Delegated prompt blocks regional read");
            model.nativeConfirmation = null;
            model.updateConfirmation = { actionId: "updates-refresh" };
            check(!model.regional.requestChoices(kind), "Update prompt blocks regional read");
            model.updateConfirmation = null;
            publicationProbe = true;
            const requested = model.regional.requestChoices(kind);
            if (scenario === "close-claim") {
                check(!requested && !model.settingsVisible && !model.regional.ownsPreparation(), "Closure during claim prevents helper launch");
                stage = 9;
                return;
            }
            check(requested, "Explicit catalog read accepted");
            check(!model.prepareDelegate("accounts-open") && !model.prepareUpdate("updates-refresh")
                && !model.regional.requestChoices(kind), "Read owner excludes competing preparations");
            stage = 2;
        } else if (stage === 2) {
            const read = model.regional.preflight.current;
            if (["close-read", "required-read", "stale-read"].indexOf(scenario) >= 0 && read !== null && read.started) {
                stage = 8;
                priorGeneration = model.requestGeneration;
                if (scenario === "close-read") model.closeSettings();
                else if (scenario === "required-read") {
                    model.operation.requestSnapshot();
                    check(model.requiredPending && !model.snapshotOwned && model.regional.ownsPreparation(),
                        "Required recovery waits for retired preflight reaping");
                } else {
                    model.discoveryBatch = true;
                    model.regional.discovery(action).invalidate();
                    model.discoveryBatch = false;
                    check(model.regional.request === null, "Owning event immediately retires request");
                }
            } else if (!model.regional.ownsPreparation()) {
                if (scenario === "close-publish" || scenario === "required-publish") {
                    check(model.regional.choices(kind).length === 0 && model.regional.confirmation === null,
                        "Reentrant publication invalidation retains no catalog or prompt");
                    model.closeSettings();
                    stage = 9;
                } else if (scenario === "error-read" || scenario === "malformed-read") {
                    check(model.regional.message.indexOf(scenario === "error-read" ? "permission-denied" : "malformed") >= 0,
                        "Typed read failure retained");
                    check(model.regional.choices(kind).length === 0 && model.regional.confirmation === null, "Failed read cannot confirm");
                    model.closeSettings();
                    stage = 9;
                } else {
                    check(model.regional.choices(kind).length === 2 && !publicationProbe, "Verified catalog published with owned handoff");
                    check(!model.regional.prepare(action, "not-a-choice"), "Unlisted value rejected");
                    check(model.regional.prepare(action, argument), "Exact selected value requests preview");
                    stage = 3;
                }
            }
        } else if (stage === 3 && scenario === "close-preview" && !model.settingsVisible && !model.regional.ownsPreparation()) {
            check(model.regional.confirmation === null, "Closure during preview publication retires prompt");
            stage = 9;
        } else if (stage === 3 && model.regional.confirmation !== null && !model.regional.ownsPreparation()) {
            stage = -1;
            check(model.regional.confirmation.preview.generation === "c".repeat(64), "Backend generation preserved");
            check(!model.prepareDelegate("accounts-open") && !model.prepareUpdate("updates-refresh"), "Regional prompt excludes other origins");
            const pending = model.regional.confirmation;
            check(!model.regional.matches(Object.assign({}, pending.ticket,
                { requestGeneration: pending.ticket.requestGeneration + 1 })), "Replaced snapshot identity is stale");
            check(!model.regional.matches(Object.assign({}, pending.ticket,
                { epoch: pending.ticket.epoch + 1 })), "Replaced provider epoch is stale");
            model.regional.invalidate("accounts");
            check(model.regional.confirmation === pending, "Unrelated domain preserves regional confirmation");
            model.generation = "e".repeat(64);
            check(!model.regional.confirm() && model.regional.confirmation === null, "Stale generation cannot dispatch");
            model.generation = pending.ticket.generation;
            check(!model.regional.confirm(), "Retired prompt cannot be replayed");
            // Reacquire choices after invalidation; do not restore stale UI state.
            check(model.regional.requestChoices(kind), "Fresh explicit catalog retry");
            stage = 4;
        } else if (stage === 4 && !model.regional.ownsPreparation()) {
            check(model.regional.prepare(action, argument), "Fresh preview retry");
            stage = 5;
        } else if (stage === 5 && model.regional.confirmation !== null && !model.regional.ownsPreparation()) {
            stage = -1;
            dispatchProbe = true;
            const started = model.regional.confirm();
            check(!dispatchProbe && started === (scenario !== "close-dispatch"), "Dispatch rechecks after prompt callbacks");
            check(!model.regional.confirm(), "Duplicate confirmation rejected");
            model.closeSettings();
            if (started) check(model.operation.streamOwned && !model.operation.canCancel, "Closure retains noncancelable sent operation");
            stage = started ? 7 : 9;
        } else if (stage === 7 && !model.operation.busy && model.operation.acknowledgedIds.length === 1) {
            check(model.operation.result.state === (scenario === "denied" ? "permission-denied"
                : scenario === "unsupported" ? "failed" : "succeeded"), "Verified typed operation result");
            stage = 9;
        } else if (stage === 8 && !model.regional.ownsPreparation() && !model.snapshotOwned && !model.requiredPending) {
            if (scenario === "required-read") check(model.requestGeneration > priorGeneration && model.operation.canStart,
                "Recovery snapshot runs after read releases");
            check(model.regional.confirmation === null && model.regional.choices(kind).length === 0, "Retired read never publishes");
            model.closeSettings();
            stage = 9;
        } else if (stage === 9 && !model.snapshotOwned && !model.operation.busy
                && !model.regional.ownsPreparation() && !model.discoveryModels().some(item => item.monitorOwned)) finish();
    }
    SystemManagementModel { id: model }
    Connections {
        target: model.regional
        function onRequestChanged() {
            if (root.scenario === "close-claim" && model.regional.request !== null) model.closeSettings();
        }
        function onCatalogsChanged() {
            if (!root.publicationProbe || model.regional.choices(root.kind).length === 0) return;
            root.publicationProbe = false;
            root.check(model.regional.ownsPreparation() && !model.regional.prepare(root.action, root.argument),
                "Catalog callback cannot overlap publication ownership");
            if (root.scenario === "close-publish") model.closeSettings();
            else if (root.scenario === "required-publish") model.operation.requestSnapshot();
        }
        function onConfirmationChanged() {
            if (model.regional.confirmation !== null) {
                root.check(model.regional.ownsPreparation() && !model.regional.confirm(), "Prompt callback cannot dispatch before handoff");
                if (root.scenario === "close-preview") model.closeSettings();
                return;
            }
            if (!root.dispatchProbe) return;
            root.dispatchProbe = false;
            root.check(model.dispatchingNative && !model.regional.requestChoices(root.kind)
                && !model.regional.confirm() && !model.prepareDelegate("accounts-open"), "Dispatch callback cannot overlap origins");
            if (root.scenario === "close-dispatch") model.closeSettings();
        }
    }
    Timer { interval: 20; running: true; repeat: true; onTriggered: root.advance() }
    Timer { interval: 20000; running: true; onTriggered: { console.error("Regional settings FAILED: timeout at " + root.stage); Qt.quit(); } }
}
