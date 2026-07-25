import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var networkModel
    required property var panelWindow

    readonly property int cardWidth: 620
    readonly property int cardHeight: 680
    readonly property int edgeMargin: Theme.rowSpacing

    visible: networkModel.visible
    grabFocus: false
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: cardHeight
    popupX: Math.max(edgeMargin, panelWindow.width - cardWidth - edgeMargin)
    popupY: Theme.panelHeight
    onDismissed: networkModel.close()

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                content.forceActiveFocus();
            });
        }
    }

    ShellSurface {
        id: content

        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.networkModel.wifiPasswordPromptVisible) {
                    root.networkModel.cancelWifiPasswordPrompt();
                } else {
                    root.networkModel.close();
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            enabled: !root.networkModel.wifiPasswordPromptVisible
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

        FloatingWindow {
            id: passwordPrompt

            property bool revealPassword: false

            title: "dwm network password"
            visible: root.networkModel.wifiPasswordPromptVisible
            implicitWidth: 440
            implicitHeight: 210
            color: Theme.transparent

            onVisibleChanged: {
                if (visible) {
                    revealPassword = false;
                    Qt.callLater(function() {
                        wifiPasswordInput.forceActiveFocus();
                    });
                } else if (root.visible) {
                    Qt.callLater(function() {
                        content.forceActiveFocus();
                    });
                }
            }

            Rectangle {
                anchors.fill: parent
                focus: true
                color: Theme.surface
                border.color: Theme.accent
                border.width: 1
                radius: Theme.radius

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        root.networkModel.cancelWifiPasswordPrompt();
                        event.accepted = true;
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.sectionSpacing
                    spacing: Theme.popupSpacing

                    Text {
                        Layout.fillWidth: true
                        text: {
                            const network = root.networkModel.selectedWifiNetwork();
                            return network ? "Connect to " + network.ssid : "Connect to Wi-Fi";
                        }
                        color: Theme.textStrong
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.titleFontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Enter the network password."
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        spacing: Theme.rowSpacing

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: Theme.bg
                            border.color: wifiPasswordInput.activeFocus ? Theme.accent : Theme.border
                            border.width: 1
                            radius: Theme.radius

                            TextInput {
                                id: wifiPasswordInput

                                anchors.fill: parent
                                anchors.leftMargin: Theme.rowSpacing
                                anchors.rightMargin: Theme.rowSpacing
                                text: root.networkModel.wifiPassword
                                echoMode: passwordPrompt.revealPassword ? TextInput.Normal : TextInput.Password
                                color: Theme.textStrong
                                selectionColor: Theme.accent
                                selectedTextColor: Theme.accentText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.inputFontSize
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter
                                enabled: !root.networkModel.busy

                                onTextChanged: root.networkModel.wifiPassword = text
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.networkModel.cancelWifiPasswordPrompt();
                                        event.accepted = true;
                                    }
                                }
                                onAccepted: {
                                    if (text.length > 0) {
                                        root.networkModel.connectSelectedWifi();
                                    }
                                }
                            }

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.rowSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                visible: wifiPasswordInput.text.length === 0
                                text: "Password"
                                color: Theme.placeholder
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.inputFontSize
                            }
                        }

                        ShellButton {
                            Layout.preferredWidth: 62
                            Layout.fillHeight: true
                            label: passwordPrompt.revealPassword ? "Hide" : "Show"
                            enabled: !root.networkModel.busy
                            onActivated: {
                                passwordPrompt.revealPassword = !passwordPrompt.revealPassword;
                                wifiPasswordInput.forceActiveFocus();
                            }
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.rowSpacing

                        Item {
                            Layout.fillWidth: true
                        }

                        ShellButton {
                            Layout.preferredWidth: implicitWidth
                            Layout.preferredHeight: Theme.buttonHeight
                            label: "Cancel"
                            enabled: !root.networkModel.busy
                            onActivated: root.networkModel.cancelWifiPasswordPrompt()
                        }

                        ShellButton {
                            Layout.preferredWidth: implicitWidth
                            Layout.preferredHeight: Theme.buttonHeight
                            label: "Connect"
                            enabled: !root.networkModel.busy && wifiPasswordInput.text.length > 0
                            onActivated: root.networkModel.connectSelectedWifi()
                        }
                    }
                }
            }
        }
    }
}
