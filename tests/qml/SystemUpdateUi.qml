import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.settings
import qs.systemmanagement

ShellRoot {
    id: root
    property int stage: 0
    property int assertions: 0
    property bool reentrantProbe: false
    property bool dispatchProbe: false
    property bool done: false
    property var captured: null
    property var reloadedStages: []
    property bool manual: Quickshell.env("DWM_UPDATE_UI_MANUAL") === "1"

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Update UI FAILED: " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function button(name, parent) {
        if (parent.objectName === name) return parent;
        for (const child of parent.children || []) {
            const found = root.button(name, child);
            if (found !== null) return found;
        }
        return null;
    }
    function click(name) {
        const target = root.button(name, window.contentItem);
        root.check(target !== null && target.enabled && target.visible, "Visible enabled control: " + name);
        target.requestActivation();
    }
    function control(value, next) {
        root.stage = next;
        controlProcess.command = Commands.systemManagementCommand("fixture-control", [value]);
        controlProcess.running = true;
    }
    function fresh() { return model.updateActionReason("updates-install-all") === ""; }

    function advance() {
        if (root.done || controlProcess.running) return;
        if ([13, 17, 19].indexOf(root.stage) >= 0 && !model.busy && model.operation.canStart
                && model.discovery.phase === "blocked" && root.reloadedStages.indexOf(root.stage) < 0) {
            root.check(model.operation.result !== null && model.updates.length === 1 && !root.fresh(),
                "A completion burst preserves results and inventory without an automatic third read");
            root.reloadedStages = root.reloadedStages.concat([root.stage]);
            root.click("reloadSystemStatus");
            return;
        }
        if (root.stage === 0 && model.snapshotState === "ready" && !model.busy) {
            root.check(!model.prepareUpdate("updates-refresh") && !model.confirmUpdate(), "Closed startup cannot mutate");
            model.openSettings();
            root.stage = 1;
        } else if (root.stage === 1 && root.fresh()) {
            if (root.manual) {
                root.stage = -1;
                model.discardUpdate();
                console.info("Update UI manual fixture ready");
                return;
            }
            root.check(model.operation.result === null && !model.operation.busy, "Opening and passive discovery do not start updates");
            root.check(!model.prepareUpdate("timezone-set"), "Confirmation action allowlist is closed");
            root.click("prepareInstall");
            root.captured = model.updateConfirmation;
            root.check(root.captured.changes.length === 3 && root.captured.changes[1].action === "install"
                && root.captured.changes[2].action === "remove", "Confirmation captures dependency additions and removals");
            root.check(root.captured.changes !== model.packageChanges && root.captured.changes[0] !== model.packageChanges[0], "Preview is copied, not a live inventory reference");
            const availableActions = model.actions;
            model.actions = availableActions.map(action => action.id === "updates-install-all"
                ? Object.assign({}, action, {availability: "unavailable", detail: ""}) : action);
            root.check(!model.confirmUpdate() && !model.operation.busy,
                "Confirm rechecks unavailable action even when its explanation is empty");
            model.actions = availableActions;
            root.click("prepareInstall");
            root.click("declineUpdate");
            root.check(model.updateConfirmation === null && !model.confirmUpdate(), "Declining cannot dispatch");
            root.click("prepareInstall");
            root.reentrantProbe = true;
            root.control("event", 2);
        } else if (root.stage === 2 && root.fresh() && model.updateConfirmation === null) {
            root.check(!root.reentrantProbe && !model.operation.busy, "Global change invalidates without admitting a reentrant origin");
            root.click("prepareInstall");
            model.refresh();
            root.check(model.updateConfirmation === null && !model.confirmUpdate(), "Replacement read invalidates confirmation immediately");
            root.stage = 3;
        } else if (root.stage === 3 && root.fresh()) {
            root.click("prepareInstall");
            model.generation = "d".repeat(64);
            root.check(!model.confirmUpdate(), "Changed generation rejects captured confirmation");
            model.refresh();
            root.stage = 4;
        } else if (root.stage === 4 && root.fresh()) {
            root.click("prepareInstall");
            model.closeSettings();
            root.check(model.updateConfirmation === null && !model.confirmUpdate(), "Closing invalidates the pending prompt");
            root.control("unavailable", 5);
        } else if (root.stage === 5) {
            model.openSettings();
            root.stage = 6;
        } else if (root.stage === 6 && model.discovery.fresh && !model.busy) {
            root.check(!model.prepareUpdate("updates-refresh") && model.updates.length === 1,
                "Unavailable backend action preserves readable inventory");
            root.control("partial", 7);
        } else if (root.stage === 7) {
            model.refresh();
            root.stage = 8;
        } else if (root.stage === 8 && model.discovery.fresh && !model.busy) {
            root.check(!model.prepareUpdate("updates-install-all") && model.recoveryProvider.status === "partial",
                "Incomplete recovery cannot admit an origin");
            model.closeSettings();
            root.control("monitorfail", 9);
        } else if (root.stage === 9) {
            model.openSettings();
            root.stage = 10;
        } else if (root.stage === 10 && model.discovery.failed && !model.busy) {
            root.check(!model.prepareUpdate("updates-install-all") && model.updates.length === 1,
                "Failed monitor prevents mutation without hiding readable inventory");
            root.control("deny", 11);
        } else if (root.stage === 11) {
            model.refresh();
            root.stage = 12;
        } else if (root.stage === 12 && root.fresh()) {
            root.click("prepareRefresh");
            root.dispatchProbe = true;
            root.click("confirmUpdate");
            root.check(!model.confirmUpdate() && !model.prepareUpdate("updates-install-all"), "Confirmed owner rejects duplicate or overlapping origins");
            root.stage = 13;
        } else if (root.stage === 13 && model.operation.result !== null && root.fresh()) {
            root.check(model.operation.result.state === "permission-denied" && model.updates.length === 1
                && model.operation.audit !== null && !root.dispatchProbe, "Denial preserves inventory and a verified audit");
            root.control("quiet", 14);
        } else if (root.stage === 14 && root.fresh()) {
            root.click("prepareInstall");
            root.click("confirmUpdate");
            root.stage = 15;
        } else if (root.stage === 15 && model.operation.canCancel) {
            model.closeSettings();
            root.check(model.operation.streamOwned, "Closing Settings retains the root-owned origin");
            model.openSettings();
            root.control("revoke", 16);
        } else if (root.stage === 16 && model.operation.progress !== null && !model.operation.progress.cancelable) {
            root.check(!model.operation.canCancel && !model.operation.requestCancel(), "Revoked cancellation cannot dispatch through a stale UI");
            root.control("finish", 17);
        } else if (root.stage === 17 && model.operation.result !== null && root.fresh()) {
            root.check(model.operation.result.state === "succeeded" && model.operation.audit.actionId === "updates-install-all",
                "Confirmed generation-bound install verifies its result after close/reopen");
            root.check(model.operation.log[model.operation.log.length - 1].state === "succeeded", "Visible log includes only a verified terminal result");
            root.click("prepareRefresh");
            root.click("confirmUpdate");
            root.stage = 18;
        } else if (root.stage === 18 && model.operation.canCancel) {
            root.click("cancelUpdate");
            root.check(model.operation.result === null && model.operation.streamOwned, "Cancellation UI requests without fabricating completion");
            root.stage = 19;
        } else if (root.stage === 19 && model.operation.result !== null && root.fresh()) {
            root.check(model.operation.result.state === "canceled" && model.operation.audit !== null,
                "Cancellation UI waits for the verified canceled result");
            root.done = true;
            console.info("Update UI native tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }

    SystemManagementModel {
        id: model
        onUpdateConfirmationChanged: {
            if (updateConfirmation !== null) return;
            if (root.reentrantProbe) {
                root.reentrantProbe = false;
                root.check(!model.prepareUpdate("updates-install-all") && !model.confirmUpdate(), "Invalidation publishes nonfresh state before prompt callbacks");
            }
            if (root.dispatchProbe) {
                root.dispatchProbe = false;
                root.check(!model.prepareUpdate("updates-refresh") && !model.confirmUpdate(), "Prompt clearing cannot reenter confirmed dispatch");
            }
        }
    }
    Window {
        id: window
        visible: true
        title: "Phase 6 update confirmation fixture"
        width: 780
        height: 580
        color: Theme.menuBackground
        SystemSettingsPane { anchors.fill: parent; anchors.margins: 12; systemManagementModel: model; capabilities: [] }
    }
    Process { id: controlProcess; onExited: (code, status) => root.check(code === 0 && status === 0, "Private control succeeded") }
    Timer { interval: 25; repeat: true; running: true; onTriggered: root.advance() }
    Timer {
        interval: 30000
        running: !root.manual
        onTriggered: root.check(false, "Timed out at stage " + root.stage + ": " + model.message
            + " / " + model.updateActionReason("updates-install-all") + " / discovery=" + model.discovery.phase
            + " / operation=" + model.operation.state + ":" + model.operation.detail
            + " / result=" + JSON.stringify(model.operation.result))
    }
}
