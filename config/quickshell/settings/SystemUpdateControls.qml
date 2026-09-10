import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root
    required property var model
    signal revealRequested(var target)
    readonly property var confirmation: model.updateConfirmation
    readonly property bool updateOperation: model.operation.progress !== null
        && (model.operation.progress.kind === "update" || model.operation.progress.kind === "refresh")
    readonly property var active: updateOperation && model.operation.streamOwned && !model.operation.streamFailed
        ? model.operation.progress : null
    readonly property var item: model.operation.currentItem || null
    Layout.fillWidth: true
    spacing: Theme.spacingMd

    component PlainText: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
    }

    component ActionButton: ShellButton {
        id: actionButton
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(actionButton); }
    }

    component ScrollList: ListView {
        id: scrollList
        Layout.fillWidth: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        activeFocusOnTab: true
        keyNavigationEnabled: true
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(scrollList); }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) {
                currentIndex = 0;
                positionViewAtBeginning();
            } else if (event.key === Qt.Key_End) {
                currentIndex = count - 1;
                positionViewAtEnd();
            } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
                contentY = Math.max(originY, Math.min(originY + Math.max(0, contentHeight - height),
                    contentY + (event.key === Qt.Key_PageDown ? height : -height)));
            } else return;
            root.revealRequested(scrollList);
            event.accepted = true;
        }
    }

    RowLayout {
        Layout.fillWidth: true
        ActionButton {
            objectName: "prepareRefresh"
            label: "Refresh metadata..."
            enabled: root.confirmation === null && root.model.updateActionReason("updates-refresh") === ""
            onActivated: root.model.prepareUpdate("updates-refresh")
        }
        ActionButton {
            objectName: "prepareInstall"
            label: "Install updates..."
            enabled: root.confirmation === null && root.model.updateActionReason("updates-install-all") === ""
            onActivated: root.model.prepareUpdate("updates-install-all")
        }
        Item { Layout.fillWidth: true }
    }
    PlainText {
        visible: text.length > 0
        readonly property string reason: root.model.updateActionReason("updates-refresh")
        text: reason ? "Metadata refresh: " + reason : ""
        color: Theme.menuMutedText
    }
    PlainText {
        visible: text.length > 0
        readonly property string reason: root.model.updateActionReason("updates-install-all")
        text: reason ? "Update installation: " + reason : ""
        color: Theme.menuMutedText
    }
    PlainText {
        visible: text.length > 0
        text: root.model.confirmationMessage
        color: Theme.warning
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: confirmationContent.implicitHeight + Theme.spacingLg * 2
        visible: root.confirmation !== null
        color: Theme.controlNormalFill
        border.color: Theme.warning
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius
        ColumnLayout {
            id: confirmationContent
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingMd
            PlainText {
                text: root.confirmation !== null && root.confirmation.actionId === "updates-install-all"
                    ? "Confirm package updates" : "Confirm metadata refresh"
                font.bold: true
                color: Theme.controlNormalText
            }
            PlainText {
                text: "PackageKit owns this system change and may ask for administrator authorization. "
                    + "Closing Settings does not cancel it. Cancellation is available only while PackageKit says it is safe; "
                    + "a request is not a completed cancellation. If interrupted, reload status to recover the recorded operation."
                color: Theme.menuText
            }
            PlainText {
                text: root.confirmation !== null && root.confirmation.actionId === "updates-install-all"
                    ? "Review every change below, including dependency additions and removals. This is the current preview, "
                        + "not an atomic frozen plan: PackageKit may resolve differently before execution. "
                        + "The helper rechecks the preview generation before starting."
                    : "Refresh downloads repository metadata and changes the package cache. It does not install package updates. "
                        + "Use Reload status for a read-only status request."
                color: Theme.warning
            }
            PlainText {
                visible: root.confirmation !== null && root.confirmation.changes.length > 0
                text: root.confirmation === null ? "" : root.confirmation.changes.length + " package changes / scroll to inspect all rows"
                color: Theme.menuText
            }
            ScrollList {
                objectName: "confirmedPackageChanges"
                Layout.preferredHeight: Math.min(contentHeight, 280)
                visible: count > 0
                model: root.confirmation === null ? [] : root.confirmation.changes
                spacing: Theme.spacingSm
                delegate: ColumnLayout {
                    id: change
                    required property var modelData
                    width: ListView.view.width
                    spacing: Theme.spacingXs
                    PlainText {
                        text: change.modelData.action.toUpperCase() + " / " + change.modelData.name + " " + change.modelData.version
                        color: change.modelData.action === "remove" || change.modelData.action === "obsolete" ? Theme.danger : Theme.accent
                        font.bold: true
                    }
                    PlainText { text: change.modelData.packageId; color: Theme.menuText }
                    PlainText { text: change.modelData.summary; color: Theme.menuMutedText }
                }
            }
            RowLayout {
                ActionButton {
                    objectName: "declineUpdate"
                    label: "Not now"
                    onActivated: root.model.discardUpdate()
                }
                ActionButton {
                    objectName: "confirmUpdate"
                    label: "Confirm"
                    danger: true
                    enabled: root.confirmation !== null && root.model.updateActionReason(root.confirmation.actionId) === ""
                    onActivated: root.model.confirmUpdate()
                }
            }
        }
    }

    PlainText {
        objectName: "operationOwnerNote"
        visible: root.model.operation.busy
        text: "The active system operation remains owned. Keep watching here or close Settings and return later."
        color: Theme.menuMutedText
    }
    ActionButton {
        objectName: "cancelUpdate"
        visible: root.model.operation.streamOwned && root.updateOperation
        label: "Request cancellation"
        enabled: root.model.operation.canCancel
        onActivated: root.model.operation.requestCancel()
    }
    PlainText {
        visible: root.model.operation.streamOwned && root.updateOperation && !root.model.operation.canCancel
            && root.model.operation.cancelDetail.length === 0
        text: "Cancellation is not currently safe or available. Wait for PackageKit's verified result."
        color: Theme.menuMutedText
    }
    PlainText {
        visible: text.length > 0
        text: root.model.operation.cancelDetail
        color: Theme.warning
    }
    PlainText {
        readonly property var error: root.model.operation.operationError
        visible: error !== null
        text: error === null ? "" : error.provider + " / " + error.code + ": " + error.detail
        color: Theme.danger
    }
    ColumnLayout {
        objectName: "updateProgress"
        Layout.fillWidth: true
        visible: root.active !== null
        spacing: Theme.spacingSm
        PlainText {
            objectName: "currentPackageLabel"
            text: root.model.operation.terminalPending ? "Verifying the update result..."
                : root.item !== null && root.item.name.length > 0
                    ? root.item.phase.charAt(0).toUpperCase() + root.item.phase.slice(1) + ": " + root.item.name
                    : root.active !== null && root.active.state === "authorizing" ? "Waiting for authorization..."
                    : root.active !== null && root.active.kind === "refresh" ? "Refreshing repository metadata..."
                    : "Preparing package updates..."
            font.bold: true
        }
        Controls.ProgressBar {
            objectName: "currentPackageProgress"
            Layout.fillWidth: true
            from: 0
            to: 100
            indeterminate: visible && !Theme.reducedMotion && (root.item === null || root.item.percent === "unknown")
            value: root.item !== null && root.item.percent !== "unknown" ? Number(root.item.percent) : 0
            Accessible.name: "Current package progress"
        }
        PlainText {
            text: root.item !== null && root.item.percent !== "unknown" ? "Current item: " + root.item.percent + "%"
                : "Waiting for package progress from PackageKit"
            color: Theme.menuMutedText
        }
        PlainText {
            text: "Overall transaction: " + (root.active !== null && root.active.percent !== "unknown"
                ? root.active.percent + "%" : "in progress")
            color: Theme.menuMutedText
        }
    }
}
