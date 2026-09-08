import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    readonly property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    property int stage: 0
    property int assertions: 0
    property int generation: 0
    property int serial: 0
    property int sampleRuns: 0
    property int quietTicks: 0
    property real openedAt: 0
    property var catalog: null
    property var prompt: null
    property bool claimProbed: false
    property bool done: false

    function check(value, detail) {
        assertions++;
        if (!value) {
            done = true;
            console.error("NTP sampling FAILED: " + scenario + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function quiet() {
        return !model.snapshotOwned && !model.snapshotPending && !model.requiredPending
            && model.discoveryModels().every(item => item.fresh) && model.operation.canStart
            && !model.timeReconciliation.ownsRead() && !model.timeReconciliation.sampleDue;
    }
    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) {
            stage = 1;
            openedAt = Date.now();
            model.openSettings();
        } else if (stage === 1 && quiet()) {
            stage = 2;
            check(model.regional.requestChoices("timezone"), "Catalog read admitted");
        } else if (stage === 2 && !model.regional.ownsPreparation()) {
            catalog = model.regional.catalogs.timezone;
            check(catalog !== undefined && catalog.values.length === 2, "Catalog available before sampling");
            stage = 3;
            check(model.regional.prepare("ntp-set", "enabled"), "Fresh NTP preview requested");
        } else if (stage === 3 && !model.regional.ownsPreparation()) {
            prompt = model.regional.confirmation;
            check(prompt !== null, "Verified preview published");
            generation = model.requestGeneration;
            serial = model.timeReconciliation.reader.serial;
            stage = 4;
            if (scenario === "sample-action") {
                stage = 40;
                check(model.regional.confirm(), "Explicit NTP action dispatched to private fixture");
            } else if (scenario !== "sample-periodic") model.timeReconciliation.sampleNow();
        } else if (stage === 4 && model.timeReconciliation.sampling
                && model.timeReconciliation.reader.current !== null && model.timeReconciliation.reader.current.started) {
            check(!model.timeReconciliation.blocked && model.timeDiscovery.fresh,
                "Routine sampling does not mark configuration uncertain");
            check(!model.regional.confirm() && model.regional.confirmation === prompt,
                "Sampling holds confirmation without dismissing it");
            check(!model.regional.requestChoices("locale"), "Finite reader ownership prevents overlap");
            stage = 5;
            if (scenario === "sample-periodic") check(Date.now() - openedAt >= 30000,
                "Real periodic timer does not sample early");
            if (scenario === "sample-arrival") {
                model.timeDiscovery.event("time-event\towner-arrived");
                check(model.timeReconciliation.blocked, "Arrival during sample reserves configuration reconciliation");
            } else if (scenario === "sample-close") {
                model.closeSettings();
                stage = 7;
            } else if (scenario === "sample-required") {
                model.operation.requestSnapshot();
                check(model.timeReconciliation.request === null, "Required recovery retires sample identity");
            }
        } else if (stage === 5 && quiet()) {
            const changed = scenario === "sample-capability" || scenario === "sample-required";
            check(model.requestGeneration === generation + (changed ? 1 : 0),
                "Only capability change or explicit recovery reads the cumulative snapshot");
            if (changed) {
                check(model.regional.confirmation === null, "Configuration recovery retires old preview");
                if (scenario === "sample-capability") check(!model.timeReconciliation.baseline.canNtp,
                    "Fresh full baseline records capability loss");
            } else {
                check(model.regional.confirmation === prompt && model.regional.catalogs.timezone === catalog,
                    "Sample preserves matching preview and catalog identity");
                if (scenario === "sample-error") {
                    check(model.nativeStates["ntp-synchronized"].status === "partial"
                        && model.nativeStates["ntp-synchronized"].value === "no", "Failure retains last reported synchronization");
                    check(model.regional.contextReason("timezone-set", true) === ""
                        && model.regional.contextReason("ntp-set", true) === "", "Sample error does not disable unrelated fresh configuration");
                } else if (scenario !== "sample-arrival") check(model.nativeStates["ntp-synchronized"].value === "yes",
                    "Verified synchronization sample published");
                if (scenario === "sample-arrival") check(model.timeReconciliation.reader.serial === serial + 2,
                    "Arrival waits for sample reaping then makes one complete time read");
            }
            check(sampleRuns >= 1, "A fixed two-property sample ran");
            model.closeSettings();
            stage = 7;
        } else if (stage === 40 && quiet() && model.operation.acknowledgedIds.length === 1 && sampleRuns > 0) {
            check(model.operation.result.state === "succeeded", "Private operation result is verified");
            check(model.timeReconciliation.sampledOperation === model.operation.result.id,
                "Verified NTP result requests immediate sampling");
            serial = model.timeReconciliation.reader.serial;
            model.timeReconciliation.sampleAfterOperation(model.operation.result);
            stage = 41;
        } else if (stage === 41 && ++quietTicks >= 5) {
            check(model.timeReconciliation.reader.serial === serial, "Same retained result cannot request duplicate sample");
            model.closeSettings();
            stage = 7;
        } else if (stage === 7 && !model.timeReconciliation.ownsRead()
                && model.discoveryModels().every(item => !item.monitorOwned)) {
            model.timeReconciliation.sampleNow();
            check(!model.timeReconciliation.sampleDue && model.timeReconciliation.baseline === null,
                "Closed sampler retains no queued read or baseline");
            if (scenario === "sample-close-claim") check(sampleRuns === 0, "Reentrant closure prevents sample launch");
            done = true;
            console.info("NTP sampling tests: PASS (" + scenario + ", " + assertions + " assertions)");
            Qt.quit();
        }
    }
    SystemManagementModel { id: model }
    Connections {
        target: model.timeReconciliation
        function onAboutToBlock() {
            if (model.timeReconciliation.sampleClaim.ticket === null) return;
            root.check(model.timeReconciliation.ownsRead() && !model.regional.confirm(),
                "Sample claim guards reentrant admission before focus publication");
            if (root.scenario === "sample-close-claim" && !root.claimProbed) {
                root.claimProbed = true;
                model.closeSettings();
                root.stage = 7;
            }
        }
    }
    Connections {
        target: model.timeReconciliation.reader
        function onCurrentChanged() {
            const current = model.timeReconciliation.reader.current;
            if (current !== null && current.command === "ntp-sample") root.sampleRuns++;
        }
    }
    Connections {
        target: model
        function onNativeStatesChanged() {
            if (root.scenario === "sample-close-publish" && model.timeReconciliation.sampling) {
                model.closeSettings();
                root.stage = 7;
            }
        }
    }
    Timer { interval: 20; repeat: true; running: !root.done; onTriggered: root.advance() }
    Timer { interval: 40000; running: !root.done; onTriggered: root.check(false, "Timed out at stage " + root.stage) }
}
