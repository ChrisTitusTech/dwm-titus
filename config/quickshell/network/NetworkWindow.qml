import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var networkModel
    required property var panelWindow

    readonly property int popupWidth: 620
    readonly property int popupHeight: 680
    readonly property int edgeMargin: Theme.rowSpacing

    visible: networkModel.visible
    implicitWidth: popupWidth
    implicitHeight: popupHeight
    anchor.window: panelWindow
    anchor.rect.x: Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
    anchor.rect.y: Theme.panelHeight
    grabFocus: true
    color: Theme.transparent

    ShellSurface {
        id: content

        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.networkModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.rowSpacing

                Text {
                    Layout.fillWidth: true
                    text: root.networkModel.statusText
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                ShellButton {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: Theme.buttonHeight
                    label: "Scan"
                    enabled: !root.networkModel.busy
                    onActivated: root.networkModel.refresh(true)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.networkModel.message.length > 0
                text: root.networkModel.message
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            SectionLabel {
                label: "Active"
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(150, Math.max(42, contentHeight))
                clip: true
                spacing: Theme.listSpacing
                model: root.networkModel.activeConnections

                delegate: NetworkProfileRow {
                    required property var modelData

                    width: ListView.view.width
                    profile: modelData
                    active: true
                    onDisconnectRequested: device => root.networkModel.disconnectDevice(device)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.networkModel.activeConnections.length === 0
                text: "No active connections"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            SectionLabel {
                label: "Wi-Fi"
            }

            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(220, Math.max(64, contentHeight))
                clip: true
                spacing: Theme.listSpacing
                model: root.networkModel.wifiNetworks

                delegate: NetworkWifiRow {
                    required property int index
                    required property var modelData

                    width: ListView.view.width
                    network: modelData
                    selected: index === root.networkModel.selectedWifiIndex
                    busy: root.networkModel.busy
                    onSelectedRequested: root.networkModel.selectWifi(index)
                    onConnectRequested: network => {
                        root.networkModel.selectWifi(index);
                        root.networkModel.connectWifi(network);
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.networkModel.wifiNetworks.length === 0
                text: "No visible Wi-Fi networks"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.networkModel.selectedWifiNetwork() !== null && root.networkModel.selectedWifiNetwork().secured ? 44 : 0
                visible: root.networkModel.selectedWifiNetwork() !== null && root.networkModel.selectedWifiNetwork().secured
                color: Theme.surface
                radius: Theme.radius

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.rowSpacing
                    anchors.rightMargin: Theme.rowSpacing
                    spacing: Theme.rowSpacing

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TextInput {
                            id: wifiPasswordInput

                            anchors.fill: parent
                            text: root.networkModel.wifiPassword
                            echoMode: TextInput.Password
                            color: Theme.textStrong
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.inputFontSize
                            clip: true
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: !root.networkModel.busy

                            onTextChanged: root.networkModel.wifiPassword = text
                            onAccepted: root.networkModel.connectSelectedWifi()
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            visible: wifiPasswordInput.text.length === 0
                            text: "Password"
                            color: Theme.placeholder
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.inputFontSize
                        }
                    }

                    ShellButton {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: Theme.buttonHeight
                        label: "Connect"
                        enabled: !root.networkModel.busy
                        onActivated: root.networkModel.connectSelectedWifi()
                    }
                }
            }

            SectionLabel {
                label: "Saved"
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.networkModel.savedProfiles

                delegate: NetworkProfileRow {
                    required property var modelData

                    width: ListView.view.width
                    profile: modelData
                    active: false
                    onConnectRequested: profile => root.networkModel.connectProfile(profile)
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.networkModel.savedProfiles.length === 0
                text: "No saved Ethernet, Wi-Fi, or VPN profiles"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            ShellButton {
                Layout.fillWidth: true
                Layout.preferredHeight: root.networkModel.editorAvailable ? 36 : 0
                visible: root.networkModel.editorAvailable
                label: "Edit Connections"
                compact: false
                onActivated: root.networkModel.openEditor()
            }
        }
    }
}
