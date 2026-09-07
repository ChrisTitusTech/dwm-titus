import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    signal revealRequested(var target)
    readonly property var confirmation: model.nativeConfirmation
    property string preparedAction: ""
    readonly property var tools: [
        {id: "accounts-open", owner: "accounts", label: "Manage accounts", target: "LXQt User Settings (lxqt-admin-user)",
            detail: "Review and administer user accounts in the trusted Fedora tool."},
        {id: "password-open", owner: "accounts", label: "Change my password", target: "passwd in your configured supported terminal",
            detail: "Enter passwords only in the terminal prompt. Settings never reads your password."},
        {id: "printers-open", owner: "printers", label: "Manage printers", target: "Print Settings (system-config-printer)",
            detail: "Configure printers and queues in the trusted Fedora tool."},
        {id: "sources-open", owner: "sources", label: "Manage software sources", target: "DNFDragora (dnfdragora)",
            detail: "Review repositories in the trusted Fedora tool. Source changes can affect future updates."}
    ]
    Layout.fillWidth: true
    spacing: Theme.spacingMd

    function definition(action) { return root.tools.find(item => item.id === action) || null; }
    function revealFocusedControl() {
        if (root.confirmation !== null && (discardButton.activeFocus || confirmButton.activeFocus)) {
            root.revealRequested(confirmationCard);
            return;
        }
        for (let index = 0; index < toolRepeater.count; index++) {
            const card = toolRepeater.itemAt(index);
            if (card !== null && card.launchFocused) root.revealRequested(card);
        }
    }
    // Layout publication can move the prompt after it first receives focus.
    // Follow geometry changes rather than polling or leaving focus off-screen.
    onYChanged: Qt.callLater(root.revealFocusedControl)
    onImplicitHeightChanged: Qt.callLater(root.revealFocusedControl)
    onConfirmationChanged: {
        if (confirmation !== null) {
            preparedAction = confirmation.actionId;
            Qt.callLater(function() { if (root.confirmation !== null) discardButton.forceActiveFocus(); });
        } else {
            const action = preparedAction;
            preparedAction = "";
            Qt.callLater(function() {
                if (root.confirmation !== null) return;
                const index = root.tools.findIndex(item => item.id === action);
                const card = index < 0 ? null : toolRepeater.itemAt(index);
                if (card !== null) card.focusLaunch();
            });
        }
    }

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }
    component ActionButton: ShellButton {
        id: actionButton
        required property var revealTarget
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(revealTarget); }
    }
    component Inventory: ListView {
        id: inventory
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 180)
        clip: true
        spacing: Theme.spacingXs
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: count > 0
        keyNavigationEnabled: true
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(inventory); }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) { currentIndex = 0; positionViewAtBeginning(); }
            else if (event.key === Qt.Key_End) { currentIndex = count - 1; positionViewAtEnd(); }
            else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp)
                contentY = Math.max(originY, Math.min(originY + Math.max(0, contentHeight - height),
                    contentY + (event.key === Qt.Key_PageDown ? height : -height)));
            else return;
            root.revealRequested(inventory);
            event.accepted = true;
        }
    }

    SectionLabel { label: "Accounts, printers and software sources" }
    PlainText {
        text: "These tools manage their own authorization and changes. Settings records launch acceptance, not completion of administration inside the tool."
        color: Theme.menuMutedText
    }
    Repeater {
        id: toolRepeater
        model: root.tools
        delegate: Rectangle {
            id: toolCard
            required property var modelData
            objectName: "delegate-card-" + modelData.id
            readonly property bool launchFocused: launchButton.activeFocus
            readonly property var provider: root.model.nativeProviderView(modelData.owner)
            readonly property string reason: root.model.delegateActionReason(modelData.id)
            function focusLaunch() { if (launchButton.enabled) launchButton.forceActiveFocus(); }
            Layout.fillWidth: true
            implicitHeight: toolContent.implicitHeight + Theme.spacingMd * 2
            radius: Theme.controlRadius
            color: Theme.controlNormalFill
            border.color: Theme.controlNormalBorder
            ColumnLayout {
                id: toolContent
                anchors.fill: parent
                anchors.margins: Theme.spacingMd
                spacing: Theme.spacingSm
                PlainText { text: toolCard.modelData.label; font.bold: true; color: Theme.menuText }
                PlainText { text: toolCard.modelData.detail; color: Theme.menuMutedText }
                PlainText {
                    text: toolCard.provider.status.toUpperCase() + " / " + toolCard.provider.detail
                    color: toolCard.provider.status === "available" ? Theme.menuMutedText : Theme.warning
                }
                ActionButton {
                    id: launchButton
                    revealTarget: toolCard
                    objectName: "prepare-" + toolCard.modelData.id
                    label: toolCard.modelData.label + "..."
                    accessibleDescription: toolCard.modelData.target
                    enabled: root.confirmation === null && toolCard.reason === ""
                    onActivated: root.model.prepareDelegate(toolCard.modelData.id)
                }
                PlainText {
                    visible: toolCard.reason.length > 0
                    text: toolCard.reason
                    color: Theme.menuMutedText
                }
            }
        }
    }

    Rectangle {
        id: confirmationCard
        objectName: "delegateConfirmationCard"
        onYChanged: Qt.callLater(root.revealFocusedControl)
        onHeightChanged: Qt.callLater(root.revealFocusedControl)
        readonly property var target: root.confirmation === null ? null : root.definition(root.confirmation.actionId)
        visible: target !== null
        Layout.fillWidth: true
        implicitHeight: confirmationContent.implicitHeight + Theme.spacingMd * 2
        radius: Theme.controlRadius
        color: Theme.controlNormalFill
        border.color: Theme.warning
        ColumnLayout {
            id: confirmationContent
            anchors.fill: parent
            anchors.margins: Theme.spacingMd
            spacing: Theme.spacingMd
            PlainText {
                objectName: "delegateConfirmationTarget"
                text: confirmationCard.target === null ? "" : "Open " + confirmationCard.target.target + "?"
                font.bold: true
                color: Theme.menuText
            }
            PlainText {
                text: "This opens a separate administration tool. Confirm any changes and authorization there. Closing Settings will not close the tool or undo its changes. A launch result does not verify work performed inside it."
                color: Theme.warning
            }
            RowLayout {
                ActionButton {
                    id: discardButton
                    revealTarget: confirmationCard
                    objectName: "discardDelegate"
                    label: "Cancel"
                    onActivated: root.model.discardDelegate()
                }
                ActionButton {
                    id: confirmButton
                    revealTarget: confirmationCard
                    objectName: "confirmDelegate"
                    label: "Open tool"
                    primary: true
                    enabled: root.confirmation !== null && root.model.delegateActionReason(root.confirmation.actionId) === ""
                    onActivated: root.model.confirmDelegate()
                }
            }
        }
    }
    PlainText {
        visible: text.length > 0
        text: root.model.nativeConfirmationMessage
        color: Theme.warning
    }

    SectionLabel { label: "Reported accounts" }
    PlainText {
        text: "Validated account rows reported by AccountsService; partial results may omit accounts."
        color: Theme.menuMutedText
    }
    Inventory {
        objectName: "nativeAccounts"
        model: root.model.accounts
        delegate: PlainText {
            required property var modelData
            width: ListView.view.width
            text: modelData.displayName + " / " + modelData.loginName + (modelData.scope === "current" ? " (current user)" : "")
            color: Theme.menuText
        }
    }
    PlainText { visible: root.model.accounts.length === 0; text: "No account rows reported."; color: Theme.menuMutedText }
    SectionLabel { label: "Reported software sources" }
    PlainText { text: "Enabled and disabled sources are read-only here."; color: Theme.menuMutedText }
    Inventory {
        objectName: "nativeRepositories"
        model: root.model.repositories
        delegate: PlainText {
            required property var modelData
            width: ListView.view.width
            text: modelData.id + " / " + modelData.state + " / " + modelData.description
            color: Theme.menuText
        }
    }
    PlainText { visible: root.model.repositories.length === 0; text: "No software-source rows reported."; color: Theme.menuMutedText }
}
