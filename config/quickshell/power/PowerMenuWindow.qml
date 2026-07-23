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

    visible: powerMenuModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: powerCard.implicitHeight
    popupX: powerMenuModel.anchorSource === "controlcenter"
        ? Theme.controlCenterX
        : Math.max(edgeMargin, panelWindow.width - cardWidth - edgeMargin)
    popupY: Theme.panelHeight
    onDismissed: powerMenuModel.close()

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                powerCard.forceActiveFocus();
            });
        } else {
            root.powerMenuModel.close();
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
                if (root.powerMenuModel.confirming) {
                    root.powerMenuModel.cancelConfirmation();
                } else {
                    root.powerMenuModel.close();
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
                title: root.powerMenuModel.confirming && root.powerMenuModel.pendingAction
                    ? root.powerMenuModel.pendingAction.label
                    : "Power"
                showBack: root.powerMenuModel.confirming
                titleLetterSpacing: root.powerMenuModel.confirming ? 1 : 2
                onBackRequested: root.powerMenuModel.cancelConfirmation()
                onCloseRequested: root.powerMenuModel.close()
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.powerMenuModel.confirming
                spacing: 2

                Repeater {
                    model: root.powerMenuModel.sessionActions

                    delegate: MenuRow {
                        required property var modelData

                        Layout.fillWidth: true
                        label: modelData.label
                        navigates: modelData.confirm
                        onActivated: root.powerMenuModel.requestAction(modelData)
                    }
                }
            }

            ColumnLayout {
                visible: root.powerMenuModel.confirming
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
                        onActivated: root.powerMenuModel.cancelConfirmation()
                    }

                    ShellButton {
                        Layout.fillWidth: true
                        label: "Confirm"
                        onActivated: root.powerMenuModel.confirmAction()
                    }
                }
            }
        }
    }
}
