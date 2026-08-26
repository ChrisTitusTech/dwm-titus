import QtQuick
import QtQuick.Layouts
import qs.core
import qs.network

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root

    required property var networkModel
    property string pendingForgetUuid: ""
    spacing: Theme.spacingLg

    onVisibleChanged: if (!visible) pendingForgetUuid = ""

    RowLayout {
        Layout.fillWidth: true

        UiText {
            Layout.fillWidth: true
            text: root.networkModel.providerState === "available"
                ? root.networkModel.statusText + " / NetworkManager"
                : root.networkModel.providerDetail
            color: root.networkModel.providerState === "available" ? Theme.menuText : Theme.warning
            font.bold: true
            elide: Text.ElideRight
        }

        ShellButton {
            label: "Scan"
            enabled: !root.networkModel.busy && root.networkModel.actionsAvailable
            onActivated: root.networkModel.refresh(true, "settings")
        }

        ShellButton {
            label: "Advanced"
            visible: root.networkModel.editorAvailable && root.networkModel.actionsAvailable
            onActivated: root.networkModel.openEditor()
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.networkModel.message.length > 0
        text: root.networkModel.message
        color: root.networkModel.providerState === "failure" ? Theme.danger : Theme.menuMutedText
        elide: Text.ElideRight
    }

    SectionLabel { label: "Active connections" }

    ListView {
        id: activeList
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(92, Math.max(40, contentHeight))
        clip: true
        spacing: Theme.spacingSm
        model: root.networkModel.activeConnections

        delegate: NetworkProfileRow {
            required property var modelData
            width: activeList.width
            profile: modelData
            active: true
            actionsEnabled: root.networkModel.actionsAvailable && !root.networkModel.busy
            onDisconnectRequested: device => root.networkModel.disconnectDevice(device, "settings")
        }
    }

    SectionLabel { label: "Wi-Fi networks" }

    ListView {
        id: wifiList
        Layout.fillWidth: true
        Layout.preferredHeight: 142
        clip: true
        spacing: Theme.spacingSm
        model: root.networkModel.wifiNetworks

        delegate: NetworkWifiRow {
            required property int index
            required property var modelData
            width: wifiList.width
            network: modelData
            selected: index === root.networkModel.selectedWifiIndex
            busy: root.networkModel.busy
            actionsEnabled: root.networkModel.actionsAvailable
            delegated: !root.networkModel.supportsFixedWifiSecurity(modelData.security)
            onSelectedRequested: root.networkModel.selectWifi(index)
            onConnectRequested: network => {
                root.networkModel.selectWifi(index);
                root.networkModel.connectWifi(network, "settings");
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.networkModel.wifiPasswordPromptVisible
            && root.networkModel.wifiPasswordPromptOrigin === "settings"
        spacing: Theme.spacingSm

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Theme.largeSurfaceSearchHeight,
                passwordInput.implicitHeight + 2 * Theme.spacingSm)
            color: Theme.controlNormalFill
            border.color: passwordInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth
            radius: Theme.controlRadius

            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                echoMode: TextInput.Password
                color: Theme.controlNormalText
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.fontFamily
                font.pixelSize: Theme.inputFontSize
                text: root.networkModel.wifiPassword
                onTextChanged: root.networkModel.wifiPassword = text
                onAccepted: root.networkModel.connectSelectedWifi("settings")

                Connections {
                    target: root.networkModel

                    function onWifiPasswordChanged() {
                        if (root.networkModel.wifiPassword.length === 0 && passwordInput.text.length > 0) {
                            passwordInput.clear();
                        }
                    }
                }
            }
        }

        ShellButton {
            label: "Connect"
            enabled: passwordInput.text.length > 0 && root.networkModel.actionsAvailable
                && !root.networkModel.busy
            onActivated: root.networkModel.connectSelectedWifi("settings")
        }

        ShellButton {
            label: "Cancel"
            onActivated: root.networkModel.cancelWifiPasswordPrompt()
        }
    }

    SectionLabel { label: "Saved Ethernet, Wi-Fi, and VPN profiles" }

    ListView {
        id: savedList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Theme.spacingSm
        model: root.networkModel.savedProfiles

        delegate: Rectangle {
            id: profileRow
            required property var modelData
            width: savedList.width
            height: 48
            color: Theme.controlNormalFill
            border.color: Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth
            radius: Theme.controlRadius

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: profileRow.modelData.name + " / " + profileRow.modelData.type
                    color: Theme.controlNormalText
                    elide: Text.ElideRight
                }

                ShellButton {
                    label: "Connect"
                    enabled: root.networkModel.actionsAvailable && !root.networkModel.busy
                    onActivated: root.networkModel.connectProfile(profileRow.modelData, "settings")
                }

                ShellButton {
                    label: root.pendingForgetUuid === profileRow.modelData.uuid ? "Confirm Forget" : "Forget"
                    danger: true
                    enabled: root.networkModel.actionsAvailable && !root.networkModel.busy
                    onActivated: {
                        if (root.pendingForgetUuid === profileRow.modelData.uuid) {
                            root.pendingForgetUuid = "";
                            root.networkModel.forgetProfile(profileRow.modelData, "settings");
                        } else {
                            root.pendingForgetUuid = profileRow.modelData.uuid;
                        }
                    }
                }
            }
        }
    }
}
