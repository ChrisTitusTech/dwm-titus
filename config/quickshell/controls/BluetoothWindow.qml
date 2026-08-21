import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var bluetoothModel
    required property var panelWindow

    readonly property int cardWidth: 360
    readonly property int cardHeight: 420

    visible: panelWindow !== null && panelWindow.screen !== null && bluetoothModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: cardHeight
    popupX: panelWindow
        ? Math.max(Theme.rowSpacing, panelWindow.width - cardWidth - Theme.rowSpacing)
        : Theme.rowSpacing
    popupY: Theme.panelHeight
    onDismissed: bluetoothModel.close()

    onVisibleChanged: if (!visible) root.bluetoothModel.close()

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.bluetoothModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            PanelHero {
                Layout.fillWidth: true
                iconText: "󰂯"
                iconColor: root.bluetoothModel.powered ? Theme.popupText : Theme.menuMutedText
                title: "Bluetooth"
                subtitle: root.bluetoothModel.statusText

                ShellButton {
                    label: "Scan"
                    enabled: root.bluetoothModel.powered && root.bluetoothModel.actionsAvailable
                        && !root.bluetoothModel.busy
                    onActivated: root.bluetoothModel.refresh(true)
                }

                PanelToggleSwitch {
                    checked: root.bluetoothModel.powered
                    busy: root.bluetoothModel.busy
                    enabled: root.bluetoothModel.available && root.bluetoothModel.actionsAvailable
                    onToggled: root.bluetoothModel.action("bluetooth-power", [checked ? "off" : "on"])
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.bluetoothModel.message.length > 0
                text: root.bluetoothModel.message
                color: Theme.menuMutedText
                elide: Text.ElideRight
            }

            PanelSeparator {}

            SectionLabel { label: "Devices" }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.bluetoothModel.devices

                delegate: Rectangle {
                    id: deviceRow

                    required property var modelData
                    width: ListView.view.width
                    height: 58
                    radius: Theme.smallRadius
                    color: deviceMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
                    border.color: deviceMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
                    border.width: Theme.controlBorderWidth

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        ColumnLayout {
                            Layout.fillWidth: true

                            UiText {
                                Layout.fillWidth: true
                                text: deviceRow.modelData.name.length > 0 ? deviceRow.modelData.name : deviceRow.modelData.address
                                color: Theme.textStrong
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: deviceRow.modelData.connected ? "Connected"
                                    : deviceRow.modelData.paired ? "Paired" : deviceRow.modelData.address
                                color: Theme.menuMutedText
                                font.pixelSize: Theme.fontCaptionSize
                                elide: Text.ElideRight
                            }
                        }
                        ShellButton {
                            label: deviceRow.modelData.connected ? "Disconnect" : (deviceRow.modelData.paired ? "Connect" : "Pair")
                            enabled: root.bluetoothModel.actionsAvailable && !root.bluetoothModel.busy
                            onActivated: root.bluetoothModel.action(deviceRow.modelData.connected ? "bluetooth-disconnect" : (deviceRow.modelData.paired ? "bluetooth-connect" : "bluetooth-pair"), [deviceRow.modelData.address])
                        }
                    }

                    MouseArea {
                        id: deviceMouse
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        hoverEnabled: true
                    }
                }
            }

            UiText {
                Layout.fillWidth: true
                visible: root.bluetoothModel.devices.length === 0
                text: root.bluetoothModel.powered ? "No Bluetooth devices found" : "Turn Bluetooth on to scan"
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }
    }
}
