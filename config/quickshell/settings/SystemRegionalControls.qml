import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    required property real viewportHeight
    readonly property var regional: model.regional
    readonly property var confirmation: regional.confirmation
    property string preparedAction: ""
    property string preparedArgument: ""
    property var readOrigin: null
    property var focusReturn: null
    property var reconciliationFocus: null
    property var reconciliationPrompt: null
    readonly property var focusedItem: root.Window.activeFocusItem
    signal revealRequested(var target)
    Layout.fillWidth: true
    spacing: Theme.spacingMd

    function beginRead(control) {
        root.readOrigin = control;
        control.forceActiveFocus();
    }
    function focusAvailable(origin) {
        if (focusedItem === null || focusedItem === root.Window.contentItem || focusedItem === errorMessage) return true;
        // Disabling/hiding an origin can return focus to an ancestor scope.
        // A different control anywhere in Settings retains the user's focus.
        for (let item = origin; item !== null; item = item.parent)
            if (item === focusedItem) return item === origin || !item.activeFocusOnTab;
        return false;
    }
    function restoreFocus() {
        if (focusReturn === null) return;
        if (!model.settingsVisible || (!focusAvailable(confirmButton)
                && !focusAvailable(discardButton) && !focusAvailable(focusReturn))) {
            focusReturn = null;
            return;
        }
        if (confirmation !== null || !focusReturn.enabled) return;
        const target = focusReturn;
        focusReturn = null;
        target.forceActiveFocus();
    }
    function restoreReconciliationFocus() {
        const target = reconciliationFocus;
        if (target === null) return;
        if (!model.settingsVisible || confirmation !== reconciliationPrompt || !focusAvailable(target)) {
            reconciliationFocus = null;
            reconciliationPrompt = null;
            return;
        }
        if (model.timeReconciliation.blocked || !target.enabled) return;
        reconciliationFocus = null;
        reconciliationPrompt = null;
        target.forceActiveFocus();
    }
    onFocusedItemChanged: {
        if (focusReturn !== null) Qt.callLater(root.restoreFocus);
        if (reconciliationFocus !== null) Qt.callLater(root.restoreReconciliationFocus);
    }
    Connections {
        target: root.model.timeReconciliation
        function onAboutToBlock() {
            const focused = root.focusedItem;
            for (let item = focused; item !== null; item = item.parent) {
                if (item === root) {
                    root.reconciliationFocus = focused;
                    root.reconciliationPrompt = root.confirmation;
                    return;
                }
            }
        }
        function onBlockedChanged() { Qt.callLater(root.restoreReconciliationFocus); }
        function onReleased() { Qt.callLater(root.restoreReconciliationFocus); }
    }
    Connections {
        target: root.reconciliationFocus
        function onEnabledChanged() { Qt.callLater(root.restoreReconciliationFocus); }
    }
    Connections {
        target: root.focusReturn
        function onEnabledChanged() { Qt.callLater(root.restoreFocus); }
    }
    Connections {
        target: root.model
        function onSettingsVisibleChanged() {
            if (!root.model.settingsVisible) {
                root.focusReturn = null;
                root.reconciliationFocus = null;
                root.reconciliationPrompt = null;
            }
        }
    }
    function revealFocusedControl() {
        if (errorMessage.visible && errorMessage.activeFocus) root.revealRequested(errorMessage);
        else if (discardButton.activeFocus) root.revealRequested(focusTarget(confirmationCard, discardButton));
        else if (confirmButton.activeFocus) root.revealRequested(focusTarget(confirmationCard, confirmButton));
        else if (enableButton.activeFocus) root.revealRequested(focusTarget(ntpCard, enableButton));
        else if (disableButton.activeFocus) root.revealRequested(focusTarget(ntpCard, disableButton));
        else {
            for (let index = 0; index < catalogRepeater.count; index++) {
                const item = catalogRepeater.itemAt(index);
                // An asynchronous pane can have a count before its delegates exist.
                if (item !== null) item.revealFocus();
            }
        }
    }
    function focusTarget(card, button) { return card.height > viewportHeight ? button : card; }
    onYChanged: Qt.callLater(root.revealFocusedControl)
    onImplicitHeightChanged: Qt.callLater(root.revealFocusedControl)
    onConfirmationChanged: {
        if (confirmation !== null) {
            focusReturn = null;
            preparedAction = confirmation.ticket.action;
            preparedArgument = confirmation.ticket.argument;
            Qt.callLater(function() {
                if (root.confirmation !== null && root.focusAvailable(root.readOrigin)) discardButton.forceActiveFocus();
            });
        } else {
            const action = preparedAction;
            const argument = preparedArgument;
            preparedAction = "";
            preparedArgument = "";
            if (action === "ntp-set") focusReturn = argument === "disabled" ? disableButton : enableButton;
            else for (let index = 0; index < catalogRepeater.count; index++) {
                const card = catalogRepeater.itemAt(index);
                if (card.action === action) focusReturn = card.originControl;
            }
            Qt.callLater(root.restoreFocus);
        }
    }

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: Theme.menuText
    }
    component ActionButton: ShellButton {
        required property var revealTarget
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(revealTarget); }
    }
    component StateText: PlainText {
        required property string identifier
        required property string label
        readonly property var reported: root.model.nativeStateView(identifier)
        text: label + ": " + reported.value + " / " + reported.status + "\n" + reported.detail
        color: reported.status === "available" ? Theme.menuMutedText : Theme.warning
    }

    SectionLabel { label: "Timezone and system locale" }
    PlainText {
        text: "Load reported choices, select a value, then review a fresh preview. System locale changes apply to new sessions; Settings will not log you out."
        color: Theme.menuMutedText
    }
    Repeater {
        id: catalogRepeater
        model: [{kind: "timezone", label: "Timezone"}, {kind: "locale", label: "System locale"}]
        delegate: Rectangle {
            id: catalogCard
            required property var modelData
            readonly property string action: modelData.kind === "timezone" ? "timezone-set" : "locale-set"
            readonly property var choices: root.regional.choices(modelData.kind)
            readonly property var filtered: choices.filter(value => value.toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
            property string selected: ""
            readonly property string reason: root.regional.actionReason(action)
            readonly property bool canRead: root.confirmation === null && !root.regional.ownsPreparation()
                && !root.model.dispatchingNative && !root.model.dispatchingUpdate
                && root.model.nativeConfirmation === null && root.model.updateConfirmation === null
                && root.regional.contextReason(action, false) === ""
            objectName: "regional-card-" + modelData.kind
            Layout.fillWidth: true
            implicitHeight: catalogContent.implicitHeight + Theme.spacingMd * 2
            radius: Theme.controlRadius
            color: Theme.controlNormalFill
            border.color: Theme.controlNormalBorder
            onChoicesChanged: { selected = ""; search.clear(); }
            readonly property var originControl: loadButton
            function revealFocus() {
                if (loadButton.activeFocus) root.revealRequested(loadButton);
                else if (previewButton.activeFocus) root.revealRequested(previewButton);
                else if (search.activeFocus) root.revealRequested(searchBox);
                else if (choiceList.activeFocus) root.revealRequested(choiceList);
            }
            ColumnLayout {
                id: catalogContent
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm
                PlainText { text: catalogCard.modelData.label; font.bold: true }
                StateText { identifier: catalogCard.modelData.kind; label: "Current" }
                ActionButton {
                    id: loadButton
                    objectName: "load-" + catalogCard.modelData.kind
                    revealTarget: loadButton
                    label: catalogCard.choices.length > 0 ? "Reload choices" : "Load choices"
                    enabled: catalogCard.canRead
                    onActivated: {
                        root.beginRead(loadButton);
                        root.regional.requestChoices(catalogCard.modelData.kind);
                    }
                }
                Rectangle {
                    id: searchBox
                    visible: catalogCard.choices.length > 0
                    Layout.fillWidth: true
                    implicitHeight: Theme.controlHeight
                    color: Theme.controlNormalFill
                    border.color: search.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                    radius: Theme.controlRadius
                    TextInput {
                        id: search
                        objectName: "search-" + catalogCard.modelData.kind
                        anchors.fill: parent
                        anchors.margins: Theme.spacingSm
                        clip: true
                        selectByMouse: true
                        activeFocusOnTab: true
                        maximumLength: 255
                        color: Theme.menuText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                        Accessible.name: "Filter " + catalogCard.modelData.label + " choices"
                        onActiveFocusChanged: { if (activeFocus) root.revealRequested(searchBox); }
                    }
                }
                PlainText {
                    visible: catalogCard.choices.length > 0
                    text: "Filter choices above. " + catalogCard.filtered.length + " matches. Select with click or Enter."
                    color: Theme.menuMutedText
                }
                ListView {
                    id: choiceList
                    objectName: "choices-" + catalogCard.modelData.kind
                    visible: catalogCard.choices.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 144, Math.max(0, root.viewportHeight))
                    model: catalogCard.filtered
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    activeFocusOnTab: count > 0
                    keyNavigationEnabled: true
                    onActiveFocusChanged: { if (activeFocus) root.revealRequested(choiceList); }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Home) { currentIndex = 0; positionViewAtBeginning(); }
                        else if (event.key === Qt.Key_End) { currentIndex = count - 1; positionViewAtEnd(); }
                        else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                            currentIndex = Math.max(0, Math.min(count - 1, currentIndex
                                + (event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(1, Math.floor(height / Theme.controlHeight))));
                            positionViewAtIndex(currentIndex, ListView.Contain);
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                                && currentIndex >= 0 && currentIndex < count) catalogCard.selected = catalogCard.filtered[currentIndex];
                        else return;
                        event.accepted = true;
                    }
                    delegate: PlainText {
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: Math.max(Theme.controlHeight, implicitHeight)
                        text: (catalogCard.selected === modelData ? "Selected: " : "") + modelData
                        color: choiceList.currentIndex === index ? Theme.accent : Theme.menuText
                        MouseArea {
                            anchors.fill: parent
                            onClicked: { choiceList.currentIndex = parent.index; catalogCard.selected = parent.modelData; choiceList.forceActiveFocus(); }
                        }
                    }
                }
                PlainText { visible: catalogCard.selected.length > 0; text: "Selected: " + catalogCard.selected }
                ActionButton {
                    id: previewButton
                    objectName: "prepare-" + catalogCard.action
                    revealTarget: previewButton
                    label: "Review change..."
                    enabled: root.confirmation === null && catalogCard.reason === "" && catalogCard.selected.length > 0
                        && catalogCard.choices.indexOf(catalogCard.selected) >= 0
                    onActivated: {
                        root.beginRead(previewButton);
                        root.regional.prepare(catalogCard.action,
                            (catalogCard.modelData.kind === "locale" ? "LANG=" : "") + catalogCard.selected);
                    }
                }
                PlainText { visible: text.length > 0; text: catalogCard.reason; color: Theme.menuMutedText }
            }
        }
    }
    Rectangle {
        id: ntpCard
        Layout.fillWidth: true
        implicitHeight: ntpContent.implicitHeight + Theme.spacingMd * 2
        radius: Theme.controlRadius
        color: Theme.controlNormalFill
        border.color: Theme.controlNormalBorder
        readonly property string reason: root.regional.actionReason("ntp-set")
        ColumnLayout {
            id: ntpContent
            anchors.fill: parent
            anchors.margins: Theme.spacingMd
            spacing: Theme.spacingSm
            PlainText { text: "Automatic network time"; font.bold: true }
            StateText { identifier: "ntp-enabled"; label: "Enabled" }
            StateText { identifier: "ntp-synchronized"; label: "Synchronization (30-second samples while open)" }
            RowLayout {
                ActionButton {
                    id: enableButton
                    objectName: "prepare-ntp-enabled"
                    revealTarget: root.focusTarget(ntpCard, enableButton)
                    label: "Review enable..."
                    enabled: root.confirmation === null && ntpCard.reason === ""
                    onActivated: { root.beginRead(enableButton); root.regional.prepare("ntp-set", "enabled"); }
                }
                ActionButton {
                    id: disableButton
                    objectName: "prepare-ntp-disabled"
                    revealTarget: root.focusTarget(ntpCard, disableButton)
                    label: "Review disable..."
                    enabled: enableButton.enabled
                    onActivated: { root.beginRead(disableButton); root.regional.prepare("ntp-set", "disabled"); }
                }
            }
            PlainText { visible: text.length > 0; text: ntpCard.reason; color: Theme.menuMutedText }
        }
    }
    Rectangle {
        id: confirmationCard
        objectName: "regionalConfirmationCard"
        readonly property var preview: root.confirmation === null ? null : root.confirmation.preview
        visible: preview !== null
        Layout.fillWidth: true
        implicitHeight: confirmationContent.implicitHeight + Theme.spacingMd * 2
        radius: Theme.controlRadius
        color: Theme.controlNormalFill
        border.color: Theme.warning
        onYChanged: Qt.callLater(root.revealFocusedControl)
        onHeightChanged: Qt.callLater(root.revealFocusedControl)
        ColumnLayout {
            id: confirmationContent
            anchors.fill: parent
            anchors.margins: Theme.spacingMd
            spacing: Theme.spacingSm
            PlainText { text: "Confirm system change"; font.bold: true }
            PlainText {
                objectName: "regionalConfirmationPreview"
                text: confirmationCard.preview === null ? "" : confirmationCard.preview.actionId
                    + "\nCurrent: " + confirmationCard.preview.current + "\nTarget: " + confirmationCard.preview.target
                    + "\n" + confirmationCard.preview.detail
            }
            PlainText {
                objectName: "regionalCancellationWarning"
                text: "This change cannot be canceled after it is sent. Cancel below only dismisses this preview. Closing Settings does not undo a sent change. An uncertain result requires fresh status and new confirmation; it is not retried automatically."
                color: Theme.warning
            }
            RowLayout {
                ActionButton {
                    id: discardButton
                    objectName: "discardRegional"
                    revealTarget: root.focusTarget(confirmationCard, discardButton)
                    label: "Cancel"
                    onActivated: root.regional.discard()
                }
                ActionButton {
                    id: confirmButton
                    objectName: "confirmRegional"
                    revealTarget: root.focusTarget(confirmationCard, confirmButton)
                    label: "Apply change"
                    primary: true
                    enabled: root.confirmation !== null && root.regional.actionReason(root.confirmation.ticket.action) === ""
                    onActivated: root.regional.confirm()
                }
            }
        }
    }
    PlainText {
        id: errorMessage
        objectName: "regionalMessage"
        visible: text.length > 0
        text: root.regional.message
        color: Theme.warning
        // Failed optional reads have no prompt to receive focus. Make their
        // explanation visible after publication and subsequent layout passes,
        // without taking focus from a control the user is already using.
        onTextChanged: {
            const origin = root.regional.ownsPreparation() ? root.readOrigin : null;
            const message = errorMessage.text;
            Qt.callLater(function() {
                if (errorMessage.visible && errorMessage.text === message && root.model.settingsVisible
                        && root.focusAvailable(origin)) {
                    errorMessage.forceActiveFocus();
                    root.revealRequested(errorMessage);
                }
            });
        }
        onYChanged: Qt.callLater(root.revealFocusedControl)
        onHeightChanged: Qt.callLater(root.revealFocusedControl)
    }
}
