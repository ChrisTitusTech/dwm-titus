import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property int stage: 0
    property int assertions: 0
    property int generation: 0
    property int serial: 0
    property var catalog: null
    property var prompt: null
    property bool injectArrival: false
    property bool pendingArrival: false
    property bool done: false
    readonly property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")

    function check(value, detail) {
        assertions++;
        if (!value) {
            done = true;
            console.error("Time reconciliation FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function quiet() {
        return !model.snapshotOwned && !model.snapshotPending && !model.requiredPending
            && model.discoveryModels().every(item => item.fresh) && model.operation.canStart;
    }
    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) {
            stage = 1;
            model.openSettings();
        } else if (stage === 1 && quiet()) {
            check(model.timeReconciliation.baseline !== null, "Complete baseline precedes time admission");
            const providers = model.nativeProviders;
            model.nativeProviders = {};
            model.timeReconciliation.arrived();
            check(!model.timeReconciliation.blocked, "Legacy snapshot without regional offers ignores owner arrival");
            model.nativeProviders = providers;
            if (scenario === "owner-gain") check(model.timeReconciliation.reader.serial === 2
                && model.actions.find(item => item.id === "ntp-set").availability === "available",
                "Initial capability gain requests bounded cumulative recovery of the stale offer");
            if (scenario === "owner-blocked") {
                check(model.timeReconciliation.reader.serial === 1
                    && model.actions.find(item => item.id === "ntp-set").availability === "unavailable",
                    "Shared admission blocker is neither capability absence nor permission to enable an offer");
                stage = 6;
                model.closeSettings();
                return;
            }
            generation = model.requestGeneration;
            stage = 2;
            check(model.regional.requestChoices("timezone"), "Catalog admitted after reconciliation");
        } else if (stage === 2 && !model.regional.ownsPreparation()) {
            catalog = model.regional.catalogs.timezone;
            check(catalog !== undefined && catalog.values.length === 2, "Verified catalog loaded");
            stage = 20;
            check(model.regional.prepare("timezone-set", "America/Chicago"), "Fresh preview requested");
        } else if (stage === 20 && !model.regional.ownsPreparation()) {
            prompt = model.regional.confirmation;
            check(prompt !== null, "Verified preview published");
            if (scenario === "owner-pending") check(pendingArrival && !model.timeReconciliation.blocked,
                "Arrival during preview is reconciled before publishing confirmation");
            serial = model.timeReconciliation.reader.serial;
            stage = 3;
            model.timeDiscovery.event("time-event\towner-arrived");
            check(!model.timeDiscovery.fresh && !model.regional.confirm(),
                "Owner arrival immediately gates time actions");
        } else if (stage === 3 && scenario === "owner-required" && model.timeReconciliation.reader.current !== null
                && model.timeReconciliation.reader.current.started) {
            stage = 30;
            model.operation.requestSnapshot();
            check(model.timeReconciliation.request === null, "Required recovery immediately retires optional identity");
        } else if (stage === 30 && quiet()) {
            check(model.requestGeneration === generation + 1, "Required snapshot follows optional reaping");
            check(model.regional.confirmation === null, "Required recovery retires old preview");
            stage = 6;
            model.closeSettings();
        } else if (stage === 3 && model.timeReconciliation.unresolved) {
            check(["owner-change", "owner-capability", "owner-fail"].indexOf(scenario) >= 0,
                "Only genuine mismatch or read failure remains unresolved");
            check(model.requestGeneration === generation + (scenario === "owner-fail" ? 0 : 1),
                "Configuration mismatch permits only one cumulative recovery");
            check(model.timeReconciliation.reader.serial === serial + (scenario === "owner-fail" ? 1 : 2),
                "Failed or mismatched baseline stops boundedly");
            stage = 6;
            model.closeSettings();
        } else if (stage === 3 && quiet()) {
            check(model.timeReconciliation.reader.serial === serial + 1, "One scoped reconciliation read");
            check(model.requestGeneration === generation, "Unchanged owner does not reread PackageKit snapshot");
            check(model.regional.catalogs.timezone === catalog, "Unchanged owner retains catalog identity");
            check(model.regional.confirmation === (scenario === "owner-preview" ? null : prompt),
                "Only a matching preview retains its identity");
            if (scenario === "owner-sync") check(model.nativeStates["ntp-synchronized"].value === "yes",
                "Synchronization-only change is published without configuration invalidation");
            serial = model.timeReconciliation.reader.serial;
            stage = 4;
            injectArrival = true;
            model.timeReconciliation.arrived();
        } else if (stage === 4 && model.timeReconciliation.unresolved) {
            check(model.timeReconciliation.reader.serial === serial + 2, "Reentrant arrivals stop after settling read");
            check(model.requestGeneration === generation, "Unresolved owner churn does not read unrelated providers");
            check(!model.regional.prepare("timezone-set", "America/Chicago"), "Unresolved reconciliation rejects mutation");
            check(model.regional.confirmation === null, "Unresolved reconciliation retires confirmation");
            injectArrival = false;
            stage = 5;
            model.refresh();
        } else if (stage === 5 && quiet()) {
            check(model.timeReconciliation.failure === "" && !model.timeReconciliation.unresolved,
                "Explicit refresh recovers reconciliation");
            stage = 6;
            model.timeReconciliation.arrived();
            model.closeSettings();
        } else if (stage === 6 && !model.timeReconciliation.ownsRead()
                && model.discoveryModels().every(item => !item.monitorOwned)) {
            check(model.timeReconciliation.baseline === null && !model.timeReconciliation.blocked,
                "Close retires baseline and reaps optional ownership");
            done = true;
            console.info("Time reconciliation tests: PASS (" + scenario + ", " + assertions + " assertions)");
            Qt.quit();
        }
    }
    SystemManagementModel { id: model }
    Connections {
        target: model
        function onNativeStatesChanged() {
            if (root.injectArrival) model.timeReconciliation.arrived();
        }
    }
    Connections {
        target: model.regional.preflight
        function onCurrentChanged() {
            const read = model.regional.preflight.current;
            if (root.scenario === "owner-pending" && !root.pendingArrival
                    && read !== null && read.command === "regional-preview") {
                root.pendingArrival = true;
                model.timeReconciliation.arrived();
            }
        }
    }
    Timer { interval: 20; repeat: true; running: !root.done; onTriggered: root.advance() }
    Timer {
        interval: 15000; running: !root.done
        onTriggered: { root.check(false, "Timed out at stage " + root.stage); }
    }
}
