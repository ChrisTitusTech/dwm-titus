import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var powerMenuModel
    required property var panelWindow

    readonly property int cardWidth: Theme.controlCenterWidth
    readonly property int edgeMargin: Theme.rowSpacing
    readonly property string actionOrigin: powerMenuModel.anchorSource || "panel"
    readonly property bool ownsConfirmation: powerMenuModel.confirming
        && powerMenuModel.confirmationOrigin === actionOrigin
    readonly property bool foreignConfirmation: powerMenuModel.confirming && !ownsConfirmation
    readonly property string actionMessage: foreignConfirmation
        ? "Another surface is awaiting confirmation for a session action"
        : powerMenuModel.messageFor(actionOrigin)

    visible: panelWindow !== null && panelWindow.screen !== null && powerMenuModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: powerCard.implicitHeight
    popupX: powerMenuModel.anchorSource === "controlcenter"
        ? Theme.controlCenterX
        : (panelWindow ? Math.max(edgeMargin, panelWindow.width - cardWidth - edgeMargin) : edgeMargin)
    popupY: Theme.panelHeight
    onDismissed: powerMenuModel.close(root.actionOrigin)

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                powerCard.forceActiveFocus();
            });
        } else {
            root.powerMenuModel.close(root.actionOrigin);
        }
    }

    ShellSurface {
        id: powerCard

        anchors.fill: parent
        implicitHeight: powerColumn.implicitHeight + margin * 2
        margin: 10
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.ownsConfirmation) {
                    root.powerMenuModel.cancelConfirmation(root.actionOrigin);
                } else {
                    root.powerMenuModel.close(root.actionOrigin);
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            id: powerColumn

            anchors.fill: parent
            spacing: Theme.listSpacing

            MenuHeader {
                Layout.fillWidth: true
                title: root.ownsConfirmation && root.powerMenuModel.pendingAction
                    ? root.powerMenuModel.pendingAction.label
                    : "Power"
                showBack: root.ownsConfirmation
                titleLetterSpacing: root.ownsConfirmation ? 1 : 2
                onBackRequested: root.powerMenuModel.cancelConfirmation(root.actionOrigin)
                onCloseRequested: root.powerMenuModel.close(root.actionOrigin)
            }

            PanelSeparator {}

            UiText {
                Layout.fillWidth: true
                visible: root.actionMessage.length > 0
                text: root.actionMessage
                color: root.foreignConfirmation ? Theme.warning
                    : (root.powerMenuModel.messageSeverityFor(root.actionOrigin) === "success"
                        ? Theme.success : root.powerMenuModel.messageSeverityFor(root.actionOrigin) === "warning"
                            ? Theme.warning : Theme.danger)
                wrapMode: Text.WordWrap
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.ownsConfirmation
                spacing: 2

                Repeater {
                    model: root.powerMenuModel.sessionActions

                    delegate: MenuRow {
                        required property var modelData

                        Layout.fillWidth: true
                        label: modelData.label
                        detail: modelData.detail
                        navigates: modelData.confirm
                        enabled: !root.powerMenuModel.busy && modelData.available
                            && !root.foreignConfirmation
                        onActivated: root.powerMenuModel.requestAction(modelData, root.actionOrigin)
                    }
                }
            }

            ColumnLayout {
                visible: root.ownsConfirmation
                Layout.fillWidth: true
                spacing: Theme.rowSpacing

                UiText {
                    Layout.fillWidth: true
                    text: root.powerMenuModel.pendingAction ? root.powerMenuModel.pendingAction.detail : ""
                    color: Theme.text
                    elide: Text.ElideRight
                }

                UiText {
                    Layout.fillWidth: true
                    text: "This action will affect the current session or system."
                    color: Theme.textMuted
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.listSpacing

                    ShellButton {
                        Layout.fillWidth: true
                        label: "Cancel"
                        enabled: !root.powerMenuModel.busy
                        onActivated: root.powerMenuModel.cancelConfirmation(root.actionOrigin)
                    }

                    ShellButton {
                        Layout.fillWidth: true
                        label: root.powerMenuModel.busy ? "Requesting..." : "Confirm"
                        enabled: !root.powerMenuModel.busy
                        onActivated: root.powerMenuModel.confirmAction(root.actionOrigin)
                    }
                }
            }
        }
    }
}
