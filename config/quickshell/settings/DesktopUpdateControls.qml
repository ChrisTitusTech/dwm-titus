import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core

pragma ComponentBehavior: Bound

Rectangle {
    id: root
    required property var model
    signal revealRequested(var target)
    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + Theme.spacingLg * 2
    color: Theme.controlNormalFill
    radius: Theme.controlRadius
    border.width: Theme.controlBorderWidth
    border.color: model && (model.status.state === "failed" || model.status.state === "interrupted")
        ? Theme.danger : Theme.controlNormalBorder

    component Label: UiText {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
    }
    component Button: ShellButton {
        id: button
        onActiveFocusChanged: { if (activeFocus) root.revealRequested(button); }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Theme.spacingLg
        spacing: Theme.spacingMd

        Label { text: "Desktop updates"; font.bold: true; color: Theme.controlNormalText }
        Label {
            objectName: "desktopUpdateStatus"
            text: root.model ? root.model.status.detail : "Desktop update support is unavailable"
            color: Theme.menuText
        }
        Label {
            visible: root.model !== null
            text: !root.model ? "" : "Installed: " + root.model.status.installed.slice(0, 12)
                + "   Available: " + root.model.status.available.slice(0, 12)
                + (root.model.status.checkedAt > 0 ? "   Checked: "
                    + new Date(root.model.status.checkedAt * 1000).toLocaleString() : "")
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
        }
        RowLayout {
            Layout.fillWidth: true
            Button {
                objectName: "checkDesktopUpdates"
                label: root.model && root.model.status.state === "checking" ? "Checking..." : "Check again"
                enabled: root.model !== null && !root.model.busy && !root.model.confirming
                onActivated: root.model.check(true)
            }
            Button {
                objectName: "prepareDesktopUpdate"
                label: "Update desktop"
                enabled: root.model !== null && root.model.canUpdate && !root.model.confirming
                onActivated: root.model.prepare()
            }
            Item { Layout.fillWidth: true }
        }
        Label {
            objectName: "desktopUpdateStatusChecked"
            visible: root.model !== null && root.model.statusCheckedAt > 0
            text: root.model ? "Status checked: " + new Date(root.model.statusCheckedAt).toLocaleTimeString() : ""
            color: Theme.menuMutedText
        }
        Button {
            objectName: "revealDesktopUpdateAuthorization"
            visible: root.model !== null && root.model.authorization.length > 0
            label: "Hide Settings to show authorization"
            onActivated: root.model.authorizationRequested()
        }
        Label {
            visible: root.model !== null && root.model.systemBusy
            text: "Finish the active system operation before updating the desktop."
            color: Theme.warning
        }
        Controls.ProgressBar {
            objectName: "desktopUpdateProgress"
            Layout.fillWidth: true
            visible: root.model !== null && (root.model.active || root.model.status.state === "checking")
            from: 0
            to: 100
            value: root.model ? Math.max(0, root.model.status.percent) : 0
            indeterminate: visible && root.model.status.percent < 0 && !Theme.reducedMotion
            Accessible.name: "Desktop update progress"
        }
        Label {
            visible: root.model !== null && root.model.active
            text: "Follow the separate progress window or reopen it from the panel. The update continues if you hide it."
            color: Theme.menuMutedText
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: root.model !== null && root.model.confirming
            spacing: Theme.spacingMd
            Label {
                text: "Update the desktop from official main?"
                font.bold: true
                color: Theme.controlNormalText
            }
            Label {
                text: "This builds and installs the selected revision, replaces managed Quickshell files, and keeps recovery copies. "
                    + "Your personal settings are preserved. Settings closes when administrator authorization is requested so the password dialog is visible. "
                    + "A separate progress window stays open through the update and shell restart. Administrator authorization is required for system-file repairs. "
                    + "Changes to system files require the source installer. "
                    + "You may need to log out afterward. Installation cannot be canceled safely once it starts."
                color: Theme.menuText
            }
            Label {
                visible: root.model !== null && root.model.status.packages.length > 0
                text: root.model ? "Required packages: " + root.model.status.packages.join(", ") : ""
                color: Theme.warning
            }
            RowLayout {
                Button { label: "Not now"; onActivated: root.model.confirming = false }
                Button {
                    objectName: "confirmDesktopUpdate"
                    label: "Confirm update"
                    enabled: root.model !== null && root.model.canUpdate
                    onActivated: root.model.confirm()
                }
            }
        }
        Label {
            visible: root.model !== null && root.model.progressError.length > 0
            text: root.model ? root.model.progressError : ""
            color: Theme.danger
        }
        Label {
            visible: root.model !== null && root.model.commandError.length > 0
            text: root.model ? root.model.commandError : ""
            color: Theme.danger
        }
        Label {
            visible: root.model !== null && root.model.status.log.length > 0
                && (root.model.active || root.model.status.state === "failed" || root.model.status.state === "interrupted")
            text: root.model ? "Update log: " + root.model.status.log : ""
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
        }
        Label {
            visible: root.model !== null && root.model.status.state === "interrupted"
            text: root.model ? "Recovery record: " + root.model.status.backup
                + "\nFollow Desktop update recovery in the installation guide before trying another update." : ""
            color: Theme.warning
        }
    }
}
