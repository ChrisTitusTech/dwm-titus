import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var powerMenuModel
    required property var panelWindow

    readonly property int cardWidth: 240
    readonly property int menuHeight: 292
    readonly property int confirmHeight: 210
    readonly property int edgeMargin: Theme.rowSpacing
    readonly property int controlCenterX: 6
    readonly property int controlCenterWidth: 276
    readonly property int controlCenterGap: 8

    visible: powerMenuModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: powerMenuModel.confirming ? confirmHeight : menuHeight
    popupX: powerMenuModel.anchorSource === "controlcenter"
        ? controlCenterX + controlCenterWidth + controlCenterGap
        : Math.max(edgeMargin, panelWindow.width - cardWidth - edgeMargin)
    popupY: Theme.panelHeight
    onDismissed: powerMenuModel.close()

    onVisibleChanged: if (!visible) root.powerMenuModel.close()

    readonly property var cancelAction: {
        "label": "Cancel",
        "detail": "Return to power menu"
    }

    readonly property var confirmButtonAction: {
        "label": "Confirm",
        "detail": powerMenuModel.pendingAction ? powerMenuModel.pendingAction.label : ""
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
            spacing: Theme.listSpacing

            Repeater {
                model: root.powerMenuModel.confirming ? [] : root.powerMenuModel.sessionActions

                delegate: PowerMenuActionButton {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 58
                    action: modelData
                    onActivated: root.powerMenuModel.requestAction(modelData)
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
                    spacing: Theme.listSpacing

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
                        onActivated: root.powerMenuModel.confirmAction()
                    }
                }
            }
        }
    }
}
