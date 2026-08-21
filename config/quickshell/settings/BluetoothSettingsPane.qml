import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root

    required property var bluetoothModel
    property string pendingRemoveAddress: ""
    spacing: Theme.spacingLg

    onVisibleChanged: if (!visible) pendingRemoveAddress = ""

    RowLayout {
        Layout.fillWidth: true

        UiText {
            Layout.fillWidth: true
            text: root.bluetoothModel.providerState === "available"
                ? root.bluetoothModel.statusText + " / BlueZ"
                : root.bluetoothModel.providerDetail
            color: root.bluetoothModel.providerState === "available" ? Theme.menuText : Theme.warning
            font.bold: true
            elide: Text.ElideRight
        }

        ShellButton {
            label: root.bluetoothModel.powered ? "Power Off" : "Power On"
            enabled: root.bluetoothModel.available && root.bluetoothModel.actionsAvailable
                && !root.bluetoothModel.busy
            onActivated: root.bluetoothModel.action("bluetooth-power",
                [root.bluetoothModel.powered ? "off" : "on"], "settings")
        }

        ShellButton {
            label: "Discover"
            enabled: root.bluetoothModel.powered && root.bluetoothModel.actionsAvailable
                && !root.bluetoothModel.busy
            onActivated: root.bluetoothModel.refresh(true, "settings")
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.bluetoothModel.message.length > 0
        text: root.bluetoothModel.message
        color: root.bluetoothModel.providerState === "failure" ? Theme.danger : Theme.menuMutedText
        elide: Text.ElideRight
    }

    SectionLabel { label: "Known and discovered devices" }

    ListView {
        id: deviceList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Theme.spacingSm
        model: root.bluetoothModel.devices

        delegate: Rectangle {
            id: deviceRow
            required property var modelData
            readonly property bool thisBusy: root.bluetoothModel.busy
                && root.bluetoothModel.actionAddress === modelData.address
            width: deviceList.width
            height: 68
            color: Theme.controlNormalFill
            border.color: thisBusy ? Theme.accent : Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth
            radius: Theme.controlRadius

            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacingSm
                spacing: Theme.spacingSm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXxs

                    UiText {
                        Layout.fillWidth: true
                        text: deviceRow.modelData.name || deviceRow.modelData.address
                        color: Theme.controlNormalText
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    UiText {
                        Layout.fillWidth: true
                        text: deviceRow.thisBusy ? "Working on " + deviceRow.modelData.address
                            : deviceRow.modelData.address + " / "
                                + (deviceRow.modelData.connected ? "connected"
                                    : deviceRow.modelData.paired ? "paired" : "not paired")
                                + (deviceRow.modelData.trusted ? " / trusted" : "")
                        color: Theme.menuMutedText
                        font.pixelSize: Theme.fontCaptionSize
                        elide: Text.ElideRight
                    }
                }

                ShellButton {
                    label: !deviceRow.modelData.paired ? "Pair"
                        : !deviceRow.modelData.trusted ? "Trust"
                        : deviceRow.modelData.connected ? "Disconnect" : "Connect"
                    enabled: root.bluetoothModel.actionsAvailable && !root.bluetoothModel.busy
                    onActivated: {
                        const action = !deviceRow.modelData.paired ? "bluetooth-pair"
                            : !deviceRow.modelData.trusted ? "bluetooth-trust"
                            : deviceRow.modelData.connected ? "bluetooth-disconnect" : "bluetooth-connect";
                        root.bluetoothModel.action(action, [deviceRow.modelData.address], "settings");
                    }
                }

                ShellButton {
                    label: root.pendingRemoveAddress === deviceRow.modelData.address ? "Confirm Remove" : "Remove"
                    danger: true
                    visible: deviceRow.modelData.paired
                    enabled: root.bluetoothModel.actionsAvailable && !root.bluetoothModel.busy
                    onActivated: {
                        if (root.pendingRemoveAddress === deviceRow.modelData.address) {
                            root.pendingRemoveAddress = "";
                            root.bluetoothModel.action("bluetooth-remove",
                                [deviceRow.modelData.address], "settings");
                        } else {
                            root.pendingRemoveAddress = deviceRow.modelData.address;
                        }
                    }
                }
            }
        }
    }

    UiText {
        Layout.fillWidth: true
        visible: root.bluetoothModel.devices.length === 0
        text: root.bluetoothModel.powered ? "No Bluetooth devices are known or visible"
            : "Turn Bluetooth on to discover devices"
        color: Theme.menuMutedText
        horizontalAlignment: Text.AlignHCenter
    }
}
