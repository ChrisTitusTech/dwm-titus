import QtQuick
import Quickshell
import qs.core
import qs.settings
import qs.systemmanagement

ShellRoot {
    id: root
    property string action: Quickshell.env("DWM_NATIVE_ACTION")
    property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    property bool manual: Quickshell.env("DWM_DELEGATE_UI_MANUAL") === "1"
    property int stage: 0
    property int assertions: 0
    property bool done: false
    readonly property int accountCount: scenario === "large" ? 256 : 1
    readonly property int repositoryCount: scenario === "large" ? 512 : 1

    function check(value, detail) {
        assertions++;
        if (!value) {
            done = true;
            console.error("Delegate UI FAILED: " + action + "/" + scenario + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function item(name, parent) {
        if (parent.objectName === name) return parent;
        for (const child of parent.children || []) {
            const found = item(name, child);
            if (found !== null) return found;
        }
        return null;
    }
    function find(name) {
        const target = item(name, window.contentItem);
        check(target !== null, "Expected visible component " + name);
        return target;
    }
    function click(name) {
        const target = find(name);
        check(target.visible && target.enabled, "Enabled action " + name);
        target.requestActivation();
    }
    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) {
            stage = 1;
            model.openSettings();
        } else if (stage === 1 && !model.busy && model.delegateActionReason(action) === "") {
            stage = -1;
            check(find("nativeAccounts").count === accountCount && find("nativeRepositories").count === repositoryCount,
                "Readable account and source inventories render");
            if (scenario === "large") {
                check(find("nativeAccounts").height <= 180 && find("nativeRepositories").height <= 180,
                    "Maximum inventories retain bounded viewports");
                check(find("nativeAccounts").contentItem.children.length < 256
                    && find("nativeRepositories").contentItem.children.length < 512, "Maximum inventories remain virtualized");
            }
            for (const id of ["accounts-open", "password-open", "printers-open", "sources-open"])
                check(find("prepare-" + id).enabled, "All fixed delegated controls available");
            const actions = model.actions;
            model.actions = actions.map(value => value.id === action ? Object.assign({}, value,
                {availability: "unavailable", detail: "Fixture tool unavailable"}) : value);
            check(!find("prepare-" + action).enabled && find("nativeAccounts").count === accountCount,
                "Unavailable tool preserves readable inventory");
            model.actions = actions;
            click("prepare-" + action);
            check(find("delegateConfirmationTarget").text.indexOf("Open ") === 0,
                "Visible confirmation names the selected tool");
            click("discardDelegate");
            check(model.nativeConfirmation === null && model.operation.result === null, "Cancel does not launch");
            stage = 4;
        } else if (stage === 4 && find("prepare-" + action).activeFocus) {
            check(model.nativeConfirmation === null, "Cancel restores focus to the originating control");
            const card = find("delegate-card-" + action);
            const position = card.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + card.height <= pane.height + 1, "Originating card remains fully revealed");
            click("prepare-" + action);
            stage = 2;
        } else if (stage === 2 && find("discardDelegate").activeFocus) {
            const card = find("delegateConfirmationCard");
            const position = card.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + card.height <= pane.height + 1,
                "Confirmation keyboard focus is revealed within the viewport: y=" + position.y
                + ", card=" + card.height + ", viewport=" + pane.height + ", scroll=" + pane.contentY);
            if (manual) {
                stage = -1;
                console.info("Delegate UI manual fixture ready");
                return;
            }
            click("confirmDelegate");
            check(!find("cancelUpdate").visible && !model.operation.canCancel,
                "Native launch never exposes update cancellation");
            check(find("operationOwnerNote").text.indexOf("PackageKit") < 0, "Native busy copy does not misidentify owner");
            model.closeSettings();
            check(model.operation.streamOwned, "Closing preserves operation ownership");
            stage = 3;
        } else if (stage === 3 && !model.busy && !model.operation.busy && model.operation.acknowledgedIds.length === 1
                && !model.discoveryModels().some(value => value.monitorOwned)) {
            check(model.operation.result.state === (scenario === "denied" ? "permission-denied"
                : scenario === "unsupported" ? "failed" : "succeeded"), "Typed terminal UI result preserved");
            check(model.accounts.length === accountCount && model.repositories.length === repositoryCount, "Outcome preserves readable state");
            done = true;
            console.info("Delegate UI tests: PASS (" + action + "/" + scenario + ", " + assertions + " assertions)");
            Qt.quit();
        }
    }
    SystemManagementModel { id: model }
    Window {
        id: window
        visible: true
        title: "Phase 6 delegated controls fixture"
        width: Number(Quickshell.env("DWM_DELEGATE_UI_WIDTH") || "780")
        height: Number(Quickshell.env("DWM_DELEGATE_UI_HEIGHT") || "580")
        color: Theme.menuBackground
        SystemSettingsPane { id: pane; anchors.fill: parent; anchors.margins: 12; systemManagementModel: model; capabilities: [] }
    }
    Timer { interval: 25; running: true; repeat: true; onTriggered: root.advance() }
    Timer { interval: 15000; running: !root.manual; onTriggered: { console.error("Delegate UI FAILED: timeout at " + root.stage); Qt.quit(); } }
}
