import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var powerMenuModel

    title: "dwm power menu"
    visible: powerMenuModel.visible
    implicitWidth: 520
    implicitHeight: powerMenuModel.confirming ? 250 : 520
    color: "#00000000"

    readonly property var cancelAction: {
        "label": "Cancel",
        "detail": "Return to menu"
    }

    readonly property var confirmButtonAction: {
        "label": "Confirm",
        "detail": powerMenuModel.pendingAction ? powerMenuModel.pendingAction.label : ""
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(content.forceActiveFocus);
        }
    }

    Rectangle {
        id: content

        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius
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
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Text {
                text: root.powerMenuModel.confirming ? "Confirm Action" : "Power Menu"
                color: Theme.text
                font.pixelSize: 18
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            ColumnLayout {
                visible: !root.powerMenuModel.confirming
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: "Session"
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallFontSize
                    font.bold: true
                }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 8
                        rowSpacing: 8

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        action: root.powerMenuModel.sessionActions[0]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        action: root.powerMenuModel.sessionActions[1]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        action: root.powerMenuModel.sessionActions[2]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        action: root.powerMenuModel.sessionActions[3]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Quick Actions"
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallFontSize
                    font.bold: true
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        compact: true
                        action: root.powerMenuModel.quickActions[0]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        compact: true
                        action: root.powerMenuModel.quickActions[1]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        compact: true
                        action: root.powerMenuModel.quickActions[2]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        compact: true
                        action: root.powerMenuModel.quickActions[3]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        compact: true
                        action: root.powerMenuModel.quickActions[4]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }
                }
            }

            ColumnLayout {
                visible: root.powerMenuModel.confirming
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 14

                Text {
                    Layout.fillWidth: true
                    text: root.powerMenuModel.pendingAction ? root.powerMenuModel.pendingAction.label : ""
                    color: Theme.textStrong
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: "This action will affect the current session or system."
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: 8

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        action: root.cancelAction
                        compact: true
                        onActivated: root.powerMenuModel.cancelConfirmation()
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 48
                        action: root.confirmButtonAction
                        compact: true
                        danger: true
                        onActivated: root.powerMenuModel.confirmAction()
                    }
                }
            }
        }
    }
}
