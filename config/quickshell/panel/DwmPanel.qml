import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core

pragma ComponentBehavior: Bound

// qmllint disable uncreatable-type
PanelWindow {
    id: root

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel
    required property var bluetoothModel
    required property var controlCenterModel
    required property var powerMenuModel

    implicitHeight: Theme.panelHeight
    color: Theme.transparent
    exclusiveZone: Theme.panelHeight
    aboveWindows: true

    anchors {
        top: true
        left: true
        right: true
    }

    Rectangle {
        id: island

        anchors.fill: parent
        anchors.leftMargin: Theme.panelEdgeMargin
        anchors.rightMargin: Theme.panelEdgeMargin
        anchors.topMargin: Theme.panelMargin
        anchors.bottomMargin: Theme.panelMargin
        opacity: 1.0
        color: Theme.barBackground
        border.color: Theme.border
        border.width: Theme.pillBorderWidth
        radius: Theme.barRadius

        PillShadow { cornerRadius: island.radius }

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
                        onActivated: root.controlCenterModel.toggle()
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showWorkspaceWidget
                        Layout.preferredWidth: workspaceRow.implicitWidth + 8
                        Layout.preferredHeight: Theme.pillHeight

                        RowLayout {
                            id: workspaceRow

                            anchors.centerIn: parent
                            spacing: 1

                            Repeater {
                                model: root.state.workspaceNames

                                delegate: WorkspaceButton {
                                    required property int index
                                    required property string modelData

                                    label: modelData
                                    selected: index === root.state.currentWorkspace
                                    occupied: root.state.workspaceOccupied(index)
                                    onClicked: root.state.switchWorkspace(index)
                                }
                            }
                        }
                    }

                    PanelPill {
                        Layout.preferredWidth: Math.min(activeTitle.implicitWidth + Theme.pillHorizontalPadding * 2, 260)
                        Layout.preferredHeight: Theme.pillHeight

                        UiText {
                            id: activeTitle
                            anchors.fill: parent
                            anchors.leftMargin: Theme.pillHorizontalPadding
                            anchors.rightMargin: Theme.pillHorizontalPadding
                            text: root.state.activeWindowTitle
                            color: Theme.text
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                }
            }

            PanelPill {
                Layout.preferredWidth: clockLabel.implicitWidth + Theme.pillHorizontalPadding * 2
                Layout.preferredHeight: Theme.pillHeight

                UiText {
                    id: clockLabel

                    anchors.centerIn: parent
                    text: Qt.formatDateTime(root.clock.date, "ddd dd MMM  HH:mm")
                    color: Theme.textStrong
                    font.bold: true
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0

                RowLayout {
                    anchors.fill: parent
                    spacing: Theme.panelGap

                    Item { Layout.fillWidth: true }

                    Repeater {
                        model: root.state.statusSegments

                        delegate: PanelPill {
                            required property string modelData
                            Layout.preferredWidth: statusLabel.implicitWidth + Theme.pillHorizontalPadding * 2
                            Layout.preferredHeight: Theme.pillHeight

                            UiText {
                                id: statusLabel
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: Theme.text
                            }
                        }
                    }

                    RunningAppsArea { state: root.state }

                    PanelPill {
                        visible: root.controlCenterModel.showBluetoothWidget
                        Layout.preferredWidth: bluetoothRow.implicitWidth + Theme.pillHorizontalPadding * 2
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.bluetoothModel.visible
                        hovered: bluetoothMouse.containsMouse

                        RowLayout {
                            id: bluetoothRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: "󰂯"
                                color: Theme.textStrong
                            }
                        }

                        MouseArea {
                            id: bluetoothMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.bluetoothModel.toggle()
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showNetworkWidget
                        Layout.preferredWidth: networkRow.implicitWidth + Theme.pillHorizontalPadding * 2
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.networkModel.visible
                        hovered: networkMouse.containsMouse

                        RowLayout {
                            id: networkRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: root.networkModel.statusText.indexOf("offline") >= 0
                                    || root.networkModel.statusText.indexOf("unavailable") >= 0 ? "󰤭" : "󰤨"
                                color: Theme.textStrong
                            }
                        }

                        MouseArea {
                            id: networkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.networkModel.toggle()
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showVolumeWidget
                        Layout.preferredWidth: Theme.pillHeight
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.controlsModel.visible
                        hovered: controlsMouse.containsMouse

                        IconText {
                            anchors.centerIn: parent
                            text: root.controlsModel.volumeMuted ? "󰝟" : "󰕾"
                            color: Theme.textStrong
                        }

                        MouseArea {
                            id: controlsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controlsModel.toggle()
                            onWheel: function(wheel) {
                                if (wheel.angleDelta.y > 0) {
                                    root.controlsModel.volumeUp();
                                } else if (wheel.angleDelta.y < 0) {
                                    root.controlsModel.volumeDown();
                                }
                                wheel.accepted = true;
                            }
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showPowerWidget
                        Layout.preferredWidth: Theme.pillHeight
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.powerMenuModel.visible
                        hovered: powerMouse.containsMouse

                        IconText {
                            anchors.centerIn: parent
                            text: "󰐥"
                            color: Theme.textStrong
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.powerMenuModel.toggle("panel")
                        }
                    }
                }
            }
        }
    }

    PanelTooltip {
        visible: logoButton.hovered
        anchorWindow: root
        label: "Control Center"
        anchorX: logoButton.mapToItem(island, 0, 0).x
        anchorY: Theme.panelHeight
    }

    PanelTooltip {
        visible: bluetoothMouse.containsMouse
        anchorWindow: root
        label: root.bluetoothModel.statusText
        anchorX: bluetoothMouse.mapToItem(island, bluetoothMouse.width / 2, 0).x
        anchorY: Theme.panelHeight
    }

    PanelTooltip {
        visible: networkMouse.containsMouse
        anchorWindow: root
        label: root.networkModel.statusText
        anchorX: networkMouse.mapToItem(island, networkMouse.width / 2, 0).x
        anchorY: Theme.panelHeight
    }

    PanelTooltip {
        visible: controlsMouse.containsMouse
        anchorWindow: root
        label: root.controlsModel.volumeDisplayText
        anchorX: controlsMouse.mapToItem(island, controlsMouse.width / 2, 0).x
        anchorY: Theme.panelHeight
    }

    PanelTooltip {
        visible: powerMouse.containsMouse
        anchorWindow: root
        label: "Power"
        anchorX: powerMouse.mapToItem(island, powerMouse.width / 2, 0).x
        anchorY: Theme.panelHeight
    }
}
