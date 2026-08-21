import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// qmllint disable uncreatable-type
PanelWindow {
    id: root

    signal popupRequested(var panelWindow, string popupId)

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel
    required property var bluetoothModel
    required property var controlCenterModel
    required property var powerMenuModel
    required property bool primaryPanel

    readonly property color barForeground: Theme.omarchyBarForeground
    readonly property color barInactive: Theme.omarchyBarInactive
    readonly property color barActive: Theme.omarchyBarActive
    readonly property color barUrgent: Theme.omarchyBarUrgent

    implicitHeight: 30
    color: Theme.omarchyBarBackground
    exclusiveZone: 30
    aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(
        root.state.screenIndex(root.screen)) === -1

    anchors {
        top: true
        left: true
        right: true
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.panelGap
        anchors.rightMargin: Theme.panelGap
        spacing: Theme.panelGap

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            RowLayout {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width)
                height: parent.height
                spacing: Theme.panelGap

                LogoButton {
                    id: logoButton

                    onActivated: {
                        root.popupRequested(root, "controlcenter");
                        root.controlCenterModel.toggle();
                    }
                }

                RowLayout {
                    id: workspaceRow

                    spacing: 1

                    Repeater {
                        model: root.state.barWorkspaceIndexes(root.screen, root.primaryPanel)

                        delegate: WorkspaceButton {
                            required property int modelData

                            label: root.state.workspaceNames[modelData]
                            selected: modelData === root.state.currentWorkspaceForScreen(root.screen)
                            occupied: root.state.workspaceOccupied(modelData)
                            onClicked: root.state.switchWorkspaceForScreen(root.screen, modelData)
                        }
                    }
                }
            }
        }

        UiText {
            id: clockLabel

            text: Qt.formatDateTime(root.clock.date, "ddd, d MMM | hh:mm")
            color: root.barForeground
            font.pixelSize: Theme.omarchyBarFontSize
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: 0

            RowLayout {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width)
                height: parent.height
                spacing: Theme.panelGap

                RunningAppsArea { state: root.state }

                // Bluetooth
                BarIconButton {
                    id: bluetooth

                    active: root.bluetoothModel.visible
                    glyph: "󰂯"
                    onActivated: {
                        root.popupRequested(root, "bluetooth");
                        root.bluetoothModel.toggle();
                    }
                }

                NetworkBarModule {
                    networkModel: root.networkModel
                    onPopupRequested: root.popupRequested(root, "network")
                }

                VolumeBarModule {
                    controlsModel: root.controlsModel
                    onPopupRequested: root.popupRequested(root, "controls")
                }
            }
        }
    }
}
