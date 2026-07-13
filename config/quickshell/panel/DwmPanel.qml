import QtQuick
import QtQuick.Layouts
import Quickshell
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
                                    onClicked: root.state.switchWorkspace(index)
                                }
                            }
                        }
                    }

                    PanelPill {
                        Layout.preferredWidth: Math.min(280, activeWindowLabel.implicitWidth + Theme.pillHorizontalPadding * 2)
                        Layout.preferredHeight: Theme.pillHeight

                        UiText {
                            id: activeWindowLabel

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.pillHorizontalPadding
                            anchors.rightMargin: Theme.pillHorizontalPadding
                            text: root.state.activeWindowTitle
                            color: Theme.text
                            elide: Text.ElideRight
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

                        delegate: UiText {
                            required property string modelData
                            text: modelData
                            color: Theme.text
                        }
                    }

                    TrayArea {}

                    PanelPill {
                        visible: root.controlCenterModel.showVolumeWidget
                        Layout.preferredWidth: volumeRow.implicitWidth + Theme.pillHorizontalPadding * 2
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.controlsModel.visible
                        hovered: controlsMouse.containsMouse

                        RowLayout {
                            id: volumeRow

                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing + 2

                            Rectangle {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 6
                                radius: 3
                                color: Theme.borderStrong

                                Rectangle {
                                    width: Math.max(4, parent.width * root.controlsModel.volumePercent / 100)
                                    height: parent.height
                                    radius: parent.radius
                                    color: Theme.accentSecondary
                                }
                            }

                            UiText {
                                text: root.controlsModel.volumeMuted ? "Muted" : root.controlsModel.volumePercent.toString() + "%"
                                color: Theme.accentSecondary
                            }
                        }

                        MouseArea {
                            id: controlsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controlsModel.toggle()
                        }
                    }

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

                            IconText { text: "󰂯" }
                            UiText { text: "BT" }
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

                            UiText { text: "NET" }
                            IconText {
                                text: root.networkModel.statusText.indexOf("offline") >= 0
                                    || root.networkModel.statusText.indexOf("unavailable") >= 0 ? "󰤭" : "󰤨"
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
                        visible: root.controlCenterModel.showPowerWidget
                        Layout.preferredWidth: Theme.pillHeight
                        Layout.preferredHeight: Theme.pillHeight
                        active: root.powerMenuModel.visible
                        hovered: powerMouse.containsMouse

                        IconText {
                            anchors.centerIn: parent
                            text: "󰐥"
                            color: Theme.accentSecondary
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.powerMenuModel.toggle()
                        }
                    }
                }
            }
        }
    }
}
