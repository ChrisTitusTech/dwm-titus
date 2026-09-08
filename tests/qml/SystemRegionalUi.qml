import QtQuick
import Quickshell
import qs.core
import qs.settings
import qs.systemmanagement

ShellRoot {
    id: root
    ClockModel { id: clock; timezoneState: model.nativeStates.timezone || null }
    property string action: Quickshell.env("DWM_NATIVE_ACTION")
    property string scenario: Quickshell.env("DWM_NATIVE_ACTION_SCENARIO")
    readonly property string kind: action === "locale-set" ? "locale" : "timezone"
    readonly property string selection: action === "locale-set" ? "en_US.UTF-8" : "America/Chicago"
    readonly property string ntpValue: scenario === "disable" ? "disabled" : "enabled"
    readonly property string origin: action === "ntp-set" ? "prepare-ntp-" + ntpValue : "prepare-" + action
    property bool manual: Quickshell.env("DWM_REGIONAL_UI_MANUAL") === "1"
    property int stage: 0
    property int assertions: 0
    property int layoutTicks: 0
    property int errorLayoutTicks: 0
    property bool done: false
    property var retainedPrompt: null
    readonly property int originalHeight: Number(Quickshell.env("DWM_DELEGATE_UI_HEIGHT") || "580")

    function check(value, detail) {
        assertions++;
        if (!value) {
            done = true;
            console.error("Regional UI FAILED: " + action + "/" + scenario + ": " + detail);
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
        check(target !== null, "Expected component " + name);
        return target;
    }
    function click(name) {
        const target = find(name);
        check(target.visible && target.enabled, "Enabled control " + name);
        target.requestActivation();
    }
    function startPreparation() {
        if (action === "ntp-set") click(origin);
        else click("load-" + kind);
        stage = action === "ntp-set" ? 3 : 2;
        if (scenario === "malformed-read") {
            check(model.regional.ownsPreparation(), "Focus moves while a real read is pending");
            find(action === "ntp-set" ? "regionalOuterPane" : "externalRegionalFocus").forceActiveFocus();
        }
    }
    function settled() { return !model.busy && !model.regional.ownsPreparation(); }
    function checkUnavailableOffer() {
        check(find(origin).enabled, "Valid selection enables the mutation before availability changes");
        const actions = model.actions;
        model.actions = actions.map(value => value.id === action ? Object.assign({}, value,
            {availability: "unavailable", detail: "Fixture unavailable action"}) : value);
        check(!find(origin).enabled, "Unavailable offer disables mutation without hiding state");
        model.actions = actions;
    }
    function checkMessageFocus(names, index, finished) {
        stage = -2;
        if (index === names.length) { finished(); return; }
        const control = find(names[index]);
        check(control.visible && control.enabled, "Focus fixture control is available");
        control.forceActiveFocus();
        model.regional.message = "Fixture asynchronous message for " + names[index];
        Qt.callLater(function() {
            check(control.activeFocus, "Asynchronous message preserves " + names[index] + " focus");
            model.regional.message = "";
            Qt.callLater(function() { root.checkMessageFocus(names, index + 1, finished); });
        });
    }
    function chooseAndPreview() {
        const list = find("choices-" + kind);
        find("search-" + kind).text = "no such reported choice";
        check(list.count === 0, "Search cannot invent choices");
        find("search-" + kind).text = selection;
        check(list.count === 1, "Search retains exact reported identity");
        find("regional-card-" + kind).selected = selection;
        checkUnavailableOffer();
        checkMessageFocus(["reloadSystemStatus", "externalRegionalFocus", "load-" + kind, origin,
            "search-" + kind, "choices-" + kind], 0, function() {
            root.click(root.origin);
            root.check(!root.find("choices-" + root.kind).activeFocus,
                "Mouse-style preview activation leaves the old list focus behind");
            root.stage = 3;
        });
    }
    function checkCatalogRow() {
        const list = find("choices-" + kind);
        check(list.activeFocus && list.height <= pane.height && list.currentItem !== null,
            "Catalog fits short viewport with an active row");
        for (let repeat = 0; repeat < 3; repeat++) {
            pane.revealFocusedControl();
            const position = list.currentItem.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + list.currentItem.height <= pane.height + 1,
                "Current catalog row remains visible through repeated reveal");
        }
    }
    function checkFocused(name) {
        const button = find(name);
        check(button.activeFocus, "Expected focused action " + name);
        for (let repeat = 0; repeat < 3; repeat++) {
            pane.revealFocusedControl();
            const position = button.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + button.height <= pane.height + 1,
                "Repeated geometry reveal keeps " + name + " visible");
        }
    }
    function advance() {
        if (done) return;
        if (stage === 0 && !model.busy && model.operation.canStart) { model.openSettings(); stage = 1; }
        else if (stage === 1 && settled() && model.regional.actionReason(action) === "") {
            check(clock.settingsText.length > 0 && find("systemLocalTime").text.indexOf(clock.settingsText) >= 0,
                "Settings renders the shared local clock");
            check(find("regional-card-" + kind).visible, "Readable regional state is present");
            if (action === "ntp-set") {
                checkUnavailableOffer();
                checkMessageFocus(["reloadSystemStatus", "externalRegionalFocus",
                    "prepare-ntp-enabled", "prepare-ntp-disabled"], 0, function() { root.startPreparation(); });
            } else startPreparation();
        } else if (stage === 2 && settled()) {
            if (scenario === "error-read" || scenario === "malformed-read") { finishReadFailure(); return; }
            const list = find("choices-" + kind);
            check(list.count === (scenario === "large" ? (kind === "timezone" ? 2048 : 4096) : 2), "Bounded catalog rendered");
            check(list.height <= 144 && (scenario !== "large" || list.contentItem.children.length < list.count), "Catalog is virtualized");
            if (manual && Quickshell.env("DWM_REGIONAL_UI_CATALOG") === "1") {
                find("search-" + kind).forceActiveFocus();
                stage = -1;
                console.info("Regional UI catalog fixture ready");
                return;
            }
            if (scenario === "large") {
                window.height = 144;
                list.forceActiveFocus();
                layoutTicks = 0;
                stage = 20;
            } else chooseAndPreview();
        } else if (stage === 20 && ++layoutTicks >= 8) {
            checkCatalogRow();
            const list = find("choices-" + kind);
            list.currentIndex = list.count - 1;
            list.positionViewAtEnd();
            layoutTicks = 0;
            stage = 21;
        } else if (stage === 21 && ++layoutTicks >= 8) {
            checkCatalogRow();
            const list = find("choices-" + kind);
            list.currentIndex = 0;
            list.positionViewAtBeginning();
            layoutTicks = 0;
            stage = 22;
        } else if (stage === 22 && ++layoutTicks >= 8) {
            checkCatalogRow();
            window.height = originalHeight;
            layoutTicks = 0;
            stage = 23;
        } else if (stage === 23 && ++layoutTicks >= 8) {
            layoutTicks = 0;
            chooseAndPreview();
        } else if (stage === 3 && settled()) {
            if (scenario === "error-read" || scenario === "malformed-read") { finishReadFailure(); return; }
            if (model.regional.confirmation === null || !find("discardRegional").activeFocus) return;
            const preview = find("regionalConfirmationPreview");
            check(preview.textFormat === Text.PlainText && preview.text.indexOf("Full fixture detail") >= 0
                && preview.text.indexOf("Target: " + (action === "ntp-set" ? ntpValue : selection)) >= 0,
                "Full fixed preview is plain text");
            check(find("regionalCancellationWarning").text.indexOf("cannot be canceled after it is sent") >= 0,
                "Sent-action cancellation limit is explicit");
            click("discardRegional");
            check(model.regional.confirmation === null && model.operation.result === null, "Cancel sends no action");
            stage = 4;
        } else if (stage === 4 && (find(action === "ntp-set" ? origin : "load-" + kind).activeFocus
                || (scenario === "disable" && find("prepare-ntp-enabled").activeFocus))) {
            const button = find(action === "ntp-set" ? origin : "load-" + kind);
            check(button.activeFocus, "Cancel returns to the exact originating NTP choice");
            const position = button.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + button.height <= pane.height + 1, "Cancel restores visible origin focus");
            if (action === "ntp-set") click(origin);
            else click("load-" + kind);
            stage = action === "ntp-set" ? 6 : 5;
        } else if (stage === 5 && settled() && model.regional.choices(kind).length > 0) {
            find("regional-card-" + kind).selected = selection;
            click(origin);
            stage = 6;
        } else if (stage === 6 && settled() && model.regional.confirmation !== null && find("discardRegional").activeFocus) {
            // The async preview can publish before Qt Quick's next layout pass.
            if (++layoutTicks < 8) return;
            const card = find("regionalConfirmationCard");
            const target = card.height > pane.height ? find("discardRegional") : card;
            const position = target.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + target.height <= pane.height + 1, "Confirmation focus remains visible: "
                + position.y + "/" + target.height + "/" + pane.height);
            if (manual) { stage = -1; console.info("Regional UI manual fixture ready"); return; }
            window.height = 144;
            layoutTicks = 0;
            stage = 60;
        } else if (stage === 60 && ++layoutTicks >= 8) {
            check(find("regionalConfirmationCard").height > pane.height, "Fixture confirmation exceeds its viewport");
            checkFocused("discardRegional");
            find("confirmRegional").forceActiveFocus();
            layoutTicks = 0;
            stage = 61;
        } else if (stage === 61 && ++layoutTicks >= 8) {
            checkFocused("confirmRegional");
            window.height = originalHeight;
            layoutTicks = 0;
            stage = 62;
        } else if (stage === 62 && ++layoutTicks >= 8) {
            checkFocused("confirmRegional");
            if (scenario === "sample-ui") {
                retainedPrompt = model.regional.confirmation;
                model.timeReconciliation.sampleNow();
                stage = 65;
                return;
            }
            if (scenario === "owner") {
                retainedPrompt = model.regional.confirmation;
                model.timeReconciliation.arrived();
                check(action === "locale-set" || !find("confirmRegional").enabled,
                    "Time confirmation is gated during owner reconciliation");
                stage = 63;
                return;
            }
            checkMessageFocus(["discardRegional", "confirmRegional"], 0, function() {
                root.click("confirmRegional");
                root.check(model.operation.streamOwned && !model.operation.canCancel && !root.find("cancelUpdate").visible,
                    "Only fixed native origin owns sent action; no update cancellation");
                if (root.scenario === "success" || root.scenario === "disable") root.stage = 70;
                else if (root.scenario === "denied") {
                    root.find("externalRegionalFocus").forceActiveFocus();
                    root.stage = 71;
                } else {
                    model.closeSettings();
                    root.check(model.operation.streamOwned && model.regional.choices(root.kind).length === 0,
                        "Closure clears catalog but retains operation");
                    root.stage = 7;
                }
            });
        } else if (stage === 63 && !model.timeReconciliation.blocked) {
            check(model.regional.confirmation === retainedPrompt, "Owner arrival preserves matching visible prompt");
            checkFocused("confirmRegional");
            model.timeReconciliation.arrived();
            find("externalRegionalFocus").forceActiveFocus();
            stage = 64;
        } else if (stage === 64 && !model.timeReconciliation.blocked) {
            check(find("externalRegionalFocus").activeFocus, "Reconciliation does not steal deliberately moved focus");
            check(model.operation.result === null, "Reconciliation sends no action");
            model.closeSettings();
            stage = 8;
        } else if (stage === 65 && model.timeReconciliation.sampling) {
            check(!model.timeReconciliation.blocked && model.timeDiscovery.fresh,
                "Routine sampling preserves fresh configuration");
            check(!find("confirmRegional").enabled, "Sample serializes confirmation");
            stage = 66;
        } else if (stage === 66 && !model.timeReconciliation.ownsRead()) {
            if (!find("confirmRegional").activeFocus) return;
            check(model.regional.confirmation === retainedPrompt, "Sample preserves visible prompt identity");
            checkFocused("confirmRegional");
            model.timeReconciliation.sampleNow();
            stage = 67;
        } else if (stage === 67 && model.timeReconciliation.sampling) {
            find("externalRegionalFocus").forceActiveFocus();
            stage = 68;
        } else if (stage === 68 && !model.timeReconciliation.ownsRead()) {
            check(find("externalRegionalFocus").activeFocus, "Sample does not steal deliberately moved focus");
            check(model.operation.result === null, "Sampling sends no action");
            model.closeSettings();
            stage = 8;
        } else if ((stage === 70 || stage === 71) && settled() && !model.operation.busy
                && model.operation.acknowledgedIds.length === 1) {
            const name = action === "ntp-set" ? origin : "load-" + kind;
            if (stage === 70 && !find(name).activeFocus) return;
            if (stage === 70) checkFocused(name);
            else check(find("externalRegionalFocus").activeFocus, "Completion preserves focus moved outside regional controls");
            model.closeSettings();
            stage = 7;
        } else if (stage === 7 && settled() && !model.operation.busy && model.operation.acknowledgedIds.length === 1
                && !model.discoveryModels().some(value => value.monitorOwned)) {
            check(model.operation.result.state === (scenario === "denied" ? "permission-denied"
                : scenario === "unsupported" ? "failed" : "succeeded"), "Only verified terminal result is displayed");
            finish();
        } else if (stage === 8 && settled() && !model.discoveryModels().some(value => value.monitorOwned)) finish();
    }
    function finishReadFailure() {
        const error = find("regionalMessage");
        const moved = scenario === "malformed-read";
        if (!error.visible || (!moved && !error.activeFocus) || ++errorLayoutTicks < 8) return;
        check(error.text === model.regional.message && error.textFormat === Text.PlainText,
            "Read error preserves its complete plaintext explanation");
        if (moved) {
            check(find(action === "ntp-set" ? "regionalOuterPane" : "externalRegionalFocus").activeFocus,
                "A real failed read preserves focus moved outside regional controls");
        } else {
            const position = error.mapToItem(pane, 0, 0);
            check(position.y >= 0 && position.y + error.height <= pane.height + 1,
                "Initiating read error receives focus and is fully visible");
        }
        check(model.regional.confirmation === null && model.regional.message.length > 0
            && model.regional.choices(kind).length === 0 && model.operation.result === null, "Read failure cannot enable confirmation");
        if (manual) { stage = -1; console.info("Regional UI read failure fixture ready"); return; }
        model.closeSettings();
        stage = 8;
    }
    function finish() {
        done = true;
        console.info("Regional UI tests: PASS (" + action + "/" + scenario + ", " + assertions + " assertions)");
        Qt.quit();
    }
    SystemManagementModel { id: model }
    Connections {
        target: model.timeReconciliation
        function onAboutToBlock() {
            if (root.scenario !== "sample-ui" || model.timeReconciliation.sampleClaim.ticket === null) return;
            const prompt = model.regional.confirmation;
            root.check(!model.regional.confirm() && model.regional.confirmation === prompt,
                "Raw sample claim preserves every regional prompt during reentrant confirmation");
        }
    }
    Window {
        id: window
        visible: true
        title: "Phase 6 regional controls fixture"
        width: Number(Quickshell.env("DWM_DELEGATE_UI_WIDTH") || "780")
        height: root.originalHeight
        color: Theme.menuBackground
        SystemSettingsPane { id: pane; objectName: "regionalOuterPane"; anchors.fill: parent; anchors.margins: 12; systemManagementModel: model; capabilities: []; clockText: clock.settingsText }
        Item { objectName: "externalRegionalFocus"; width: 1; height: 1 }
    }
    Timer { interval: 25; running: !root.done; repeat: true; onTriggered: root.advance() }
    Timer { interval: 20000; running: !root.manual; onTriggered: { console.error("Regional UI FAILED: timeout at " + root.stage); Qt.quit(); } }
}
