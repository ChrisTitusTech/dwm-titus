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
    color: Theme.transparent

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

    ShellSurface {
        id: content

        anchors.fill: parent
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
            spacing: Theme.popupSpacing

            Text {
                text: root.powerMenuModel.confirming ? "Confirm Action" : "Power Menu"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleFontSize
                font.bold: true
                verticalAlignment: Text.AlignVCenter
            }

            ColumnLayout {
                visible: !root.powerMenuModel.confirming
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.sectionSpacing

                SectionLabel {
                    label: "Session"
                }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.listSpacing * 2
                        rowSpacing: Theme.listSpacing * 2

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

                SectionLabel {
                    label: "Quick Actions"
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.listSpacing

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.compactButtonHeight
                        compact: true
                        action: root.powerMenuModel.quickActions[0]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.compactButtonHeight
                        compact: true
                        action: root.powerMenuModel.quickActions[1]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.compactButtonHeight
                        compact: true
                        action: root.powerMenuModel.quickActions[2]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.compactButtonHeight
                        compact: true
                        action: root.powerMenuModel.quickActions[3]
                        onActivated: root.powerMenuModel.requestAction(action)
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.compactButtonHeight
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
                spacing: Theme.sectionSpacing

                Text {
                    Layout.fillWidth: true
                    text: root.powerMenuModel.pendingAction ? root.powerMenuModel.pendingAction.label : ""
                    color: Theme.textStrong
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: "This action will affect the current session or system."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Theme.listSpacing * 2

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.confirmButtonHeight
                        action: root.cancelAction
                        compact: true
                        onActivated: root.powerMenuModel.cancelConfirmation()
                    }

                    PowerMenuActionButton {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.confirmButtonHeight
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
