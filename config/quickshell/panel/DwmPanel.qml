import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core

pragma ComponentBehavior: Bound

// qmllint disable uncreatable-type
PanelWindow {
    id: root

    signal popupRequested(var panelWindow, string popupId)

    function batteryIcon(percent, status) {
        if (status.toLowerCase() === "charging") {
            return "󰂄";
        }

        if (percent >= 90) return "󰁹";
        if (percent >= 80) return "󰂂";
        if (percent >= 70) return "󰂁";
        if (percent >= 60) return "󰂀";
        if (percent >= 50) return "󰁿";
        if (percent >= 40) return "󰁾";
        if (percent >= 30) return "󰁽";
        if (percent >= 20) return "󰁼";
        if (percent >= 10) return "󰁻";
        return "󰂎";
    }

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel
    required property var bluetoothModel
    required property var controlCenterModel
    required property var powerMenuModel
    required property bool primaryPanel

    implicitHeight: Theme.panelHeight
    color: Theme.barBackground
    exclusiveZone: Theme.panelHeight
    aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(
        root.state.screenIndex(root.screen)) === -1

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
                        onActivated: {
                            root.popupRequested(root, "controlcenter");
                            root.controlCenterModel.toggle();
                        }
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
                    text: Qt.formatDateTime(root.clock.date, "ddd dd MMM - HH:mm")
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

                    Loader {
                        active: root.primaryPanel
                        sourceComponent: TrayArea {}
                    }

                    PanelPill {
                        id: batteryPill
                        visible: root.state.batteryAvailable
                        Layout.preferredWidth: batteryRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize

                        RowLayout {
                            id: batteryRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: root.batteryIcon(root.state.batteryPercent, root.state.batteryStatus)
                                color: Theme.textStrong
                                font.pixelSize: Math.round((Theme.panelFontSize + 1) * 1.1)
                            }

                            UiText {
                                text: root.state.batteryPercent.toString() + "%"
                                color: Theme.textStrong
                                font.pixelSize: Theme.panelFontSize
                            }
                        }

                        MouseArea {
                            id: batteryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showBluetoothWidget
                        Layout.preferredWidth: bluetoothRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.bluetoothModel.visible
                        hovered: bluetoothMouse.containsMouse

                        RowLayout {
                            id: bluetoothRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: "󰂯"
                                color: Theme.textStrong
                                font.pixelSize: Math.round((Theme.panelFontSize + 1) * 0.9)
                            }
                        }

                        MouseArea {
                            id: bluetoothMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.popupRequested(root, "bluetooth");
                                root.bluetoothModel.toggle();
                            }
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showNetworkWidget
                        Layout.preferredWidth: networkRow.implicitWidth + Theme.networkWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
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
                                font.pixelSize: Math.round((Theme.panelFontSize + 1) * 1.2)
                            }
                        }

                        MouseArea {
                            id: networkMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.popupRequested(root, "network");
                                root.networkModel.toggle();
                            }
                        }
                    }

                    PanelPill {
                        visible: root.controlCenterModel.showVolumeWidget
                        Layout.preferredWidth: volumeRow.implicitWidth + Theme.compactWidgetHorizontalPadding * 2
                        Layout.preferredHeight: Theme.compactWidgetSize
                        active: root.controlsModel.visible
                        hovered: controlsMouse.containsMouse

                        RowLayout {
                            id: volumeRow
                            anchors.centerIn: parent
                            spacing: Theme.compactSpacing

                            IconText {
                                text: root.controlsModel.volumeMuted ? "󰝟" : "󰕾"
                                color: Theme.textStrong
                                font.pixelSize: Math.round((Theme.panelFontSize + 1) * 1.5)
                            }

                            UiText {
                                visible: root.controlsModel.volumeText !== "VOL unavailable"
                                text: root.controlsModel.volumePercent.toString() + "%"
                                color: Theme.textStrong
                                font.pixelSize: Theme.panelFontSize
                            }
                        }

                        MouseArea {
                            id: controlsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.popupRequested(root, "controls");
                                root.controlsModel.toggle();
                            }
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
                            font.pixelSize: Math.round((Theme.panelFontSize + 1) * 1.08)
                        }

                        MouseArea {
                            id: powerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.popupRequested(root, "power");
                                root.powerMenuModel.toggle("panel");
                            }
                        }
                    }
                }
            }
        }
    }

}
