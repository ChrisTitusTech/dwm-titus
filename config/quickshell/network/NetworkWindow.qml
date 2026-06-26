import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var networkModel

    title: "dwm network"
    visible: networkModel.visible
    implicitWidth: 520
    implicitHeight: 560
    color: Theme.transparent

    Rectangle {
        id: content

        anchors.fill: parent
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        radius: Theme.radius
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.networkModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.popupMargin
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

                Rectangle {
                    Layout.preferredWidth: refreshText.implicitWidth + 18
                    Layout.preferredHeight: Theme.buttonHeight
                    color: refreshMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    radius: Theme.radius

                    Text {
                        id: refreshText

                        anchors.centerIn: parent
                        text: "Refresh"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                    }

                    MouseArea {
                        id: refreshMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.networkModel.refresh()
                    }
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

            Text {
                Layout.fillWidth: true
                text: "Active"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                font.bold: true
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

            Text {
                Layout.fillWidth: true
                text: "Saved"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                font.bold: true
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.networkModel.editorAvailable ? 36 : 0
                visible: root.networkModel.editorAvailable
                color: editorMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                radius: Theme.radius

                Text {
                    anchors.centerIn: parent
                    text: "Edit Connections"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.panelFontSize
                }

                MouseArea {
                    id: editorMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.networkModel.openEditor()
                }
            }
        }
    }
}
