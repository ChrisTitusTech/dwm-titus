import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

// Join form for networks that do not broadcast their SSID. The title matches
// the existing "dwm network password" window rule (floating, always on top).
FloatingWindow {
    id: root

    required property var networkModel
    property string origin: "panel"
    property bool revealPassword: false

    readonly property var securityOptions: {
        const options = [
            { value: "wpa-psk", label: "WPA2 Personal" },
            { value: "sae", label: "WPA3 Personal" },
            { value: "wep", label: "WEP" },
            { value: "none", label: "Open" }
        ];
        if (root.networkModel.editorAvailable) options.push({ value: "enterprise", label: "Enterprise (802.1X)" });
        return options;
    }
    readonly property bool needsPassword: root.networkModel.hiddenSecurity !== "none"
        && root.networkModel.hiddenSecurity !== "enterprise"

    title: "dwm network password"
    visible: root.networkModel.hiddenPromptVisible && root.networkModel.hiddenPromptOrigin === root.origin
    implicitWidth: Math.min(Theme.scaledSize(440), screen ? screen.width : Theme.scaledSize(440))
    implicitHeight: Math.min(Math.max(Theme.scaledSize(300),
        hiddenColumn.implicitHeight + Theme.sectionSpacing * 2),
        screen ? screen.height : Theme.scaledSize(300))
    color: Theme.transparent

    onClosed: root.networkModel.cancelHiddenPrompt()

    onVisibleChanged: {
        if (visible) {
            revealPassword = false;
            Qt.callLater(function() {
                hiddenViewport.contentY = 0;
                if (root.networkModel.hiddenSsid.length > 0 && root.needsPassword) passwordInput.forceActiveFocus();
                else ssidInput.forceActiveFocus();
            });
        }
    }

    function submit() {
        if (root.networkModel.hiddenFormValid && !root.networkModel.busy) root.networkModel.connectHidden(root.origin);
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            root.networkModel.cancelHiddenPrompt();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        focus: true
        color: Theme.popupBackground
        border.color: Theme.popupBorder
        border.width: Theme.controlBorderWidth
        radius: Theme.radius

        Keys.onPressed: function(event) {
            root.handleKey(event);
        }

        Flickable {
            id: hiddenViewport
            objectName: "hiddenViewport"
            anchors.fill: parent
            anchors.margins: Theme.sectionSpacing
            contentWidth: Math.max(width, Theme.scaledSize(440) - Theme.sectionSpacing * 2)
            contentHeight: Math.max(height, hiddenColumn.implicitHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.AutoFlickIfNeeded

            ColumnLayout {
                id: hiddenColumn
                width: hiddenViewport.contentWidth
                height: hiddenViewport.contentHeight
                spacing: Theme.popupSpacing

                Text {
                    Layout.fillWidth: true
                    text: "Join a hidden network"
                    color: Theme.textStrong
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: "Enter the exact network name and security type."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.scaledSize(44)
                    color: Theme.controlNormalFill
                    border.color: ssidInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                    border.width: ssidInput.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                    radius: Theme.radius

                    TextInput {
                        id: ssidInput

                        anchors.fill: parent
                        anchors.leftMargin: Theme.rowSpacing
                        anchors.rightMargin: Theme.rowSpacing
                        text: root.networkModel.hiddenSsid
                        color: Theme.textStrong
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        enabled: !root.networkModel.busy
                        activeFocusOnTab: true
                        Accessible.role: Accessible.EditableText
                        Accessible.name: "Network name"

                        onTextChanged: root.networkModel.hiddenSsid = text
                        Keys.onPressed: function(event) {
                            root.handleKey(event);
                        }
                        onAccepted: root.submit()
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.rowSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        visible: ssidInput.text.length === 0
                        text: "Network name"
                        color: Theme.placeholder
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: ssidInput.text.length > 0 && root.networkModel.hiddenSsidError.length > 0
                    text: root.networkModel.hiddenSsidError
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    text: "Security"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.rowSpacing

                    Repeater {
                        model: root.securityOptions

                        delegate: ShellButton {
                            required property var modelData

                            height: Theme.chipHeight
                            label: modelData.label
                            primary: root.networkModel.hiddenSecurity === modelData.value
                            accessibleDescription: primary ? "Selected security type" : "Security type"
                            enabled: !root.networkModel.busy
                            onActivated: {
                                if (root.networkModel.hiddenSecurity !== modelData.value) {
                                    root.networkModel.wifiPassword = "";
                                    root.networkModel.hiddenSecurity = modelData.value;
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.networkModel.editorAvailable
                    text: "Enterprise (802.1X) networks need nm-connection-editor, which is not installed."
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.networkModel.wifiDevices.length > 1
                    text: "Wi-Fi device"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                }

                Flow {
                    Layout.fillWidth: true
                    visible: root.networkModel.wifiDevices.length > 1
                    spacing: Theme.rowSpacing

                    Repeater {
                        model: root.networkModel.wifiDevices.length > 1 ? root.networkModel.wifiDevices : []

                        delegate: ShellButton {
                            required property var modelData

                            height: Theme.chipHeight
                            label: modelData.device
                            primary: root.networkModel.hiddenDevice === modelData.device
                            accessibleDescription: primary ? "Selected Wi-Fi device" : "Wi-Fi device"
                            enabled: !root.networkModel.busy
                            onActivated: root.networkModel.hiddenDevice = modelData.device
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.networkModel.hiddenSecurity === "enterprise"
                    spacing: Theme.popupSpacing

                    Text {
                        Layout.fillWidth: true
                        text: "Enterprise networks are configured in Advanced NetworkManager settings."
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                        wrapMode: Text.WordWrap
                    }

                    ShellButton {
                        Layout.preferredHeight: Theme.buttonHeight
                        label: "Open editor"
                        enabled: root.networkModel.editorAvailable
                        onActivated: root.networkModel.openEditorForHidden()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.scaledSize(44)
                    visible: root.needsPassword
                    spacing: Theme.rowSpacing

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.controlNormalFill
                        border.color: passwordInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                        border.width: passwordInput.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                        radius: Theme.radius

                        TextInput {
                            id: passwordInput

                            anchors.fill: parent
                            anchors.leftMargin: Theme.rowSpacing
                            anchors.rightMargin: Theme.rowSpacing
                            text: root.networkModel.wifiPassword
                            echoMode: root.revealPassword ? TextInput.Normal : TextInput.Password
                            color: Theme.textStrong
                            selectionColor: Theme.accent
                            selectedTextColor: Theme.accentText
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.inputFontSize
                            clip: true
                            verticalAlignment: TextInput.AlignVCenter
                            enabled: !root.networkModel.busy
                            activeFocusOnTab: root.needsPassword
                            Accessible.role: Accessible.EditableText
                            Accessible.name: "Password"

                            onTextChanged: root.networkModel.wifiPassword = text
                            Keys.onPressed: function(event) {
                                root.handleKey(event);
                            }
                            onAccepted: root.submit()
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.rowSpacing
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text.length === 0
                            text: "Password"
                            color: Theme.placeholder
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.inputFontSize
                        }
                    }

                    ShellButton {
                        Layout.preferredWidth: Theme.scaledSize(62)
                        Layout.fillHeight: true
                        label: root.revealPassword ? "Hide" : "Show"
                        enabled: !root.networkModel.busy
                        onActivated: {
                            root.revealPassword = !root.revealPassword;
                            passwordInput.forceActiveFocus();
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.needsPassword && root.networkModel.hiddenPasswordError.length > 0
                    text: root.networkModel.hiddenPasswordError
                    color: passwordInput.text.length > 0 ? Theme.danger : Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.networkModel.hiddenError.length > 0
                    text: root.networkModel.hiddenError
                    color: Theme.danger
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    wrapMode: Text.WordWrap
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
                        onActivated: root.networkModel.cancelHiddenPrompt()
                    }

                    ShellButton {
                        Layout.preferredWidth: implicitWidth
                        Layout.preferredHeight: Theme.buttonHeight
                        label: "Connect"
                        primary: true
                        enabled: root.networkModel.hiddenFormValid && !root.networkModel.busy
                            && root.networkModel.actionsAvailable
                        onActivated: root.submit()
                    }
                }
            }
        }
    }
}
