import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var controlsModel

    title: "dwm controls"
    visible: controlsModel.visible
    implicitWidth: 360
    implicitHeight: 374
    color: "#00000000"

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
                root.controlsModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: root.controlsModel.volumeText
                    color: Theme.text
                    font.pixelSize: 18
                    font.bold: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.preferredWidth: refreshText.implicitWidth + 18
                    Layout.preferredHeight: 30
                    color: refreshMouse.containsMouse ? Theme.surfaceHover : Theme.surface
                    radius: Theme.radius

                    Text {
                        id: refreshText

                        anchors.centerIn: parent
                        text: "Refresh"
                        color: Theme.text
                        font.pixelSize: Theme.smallFontSize
                    }

                    MouseArea {
                        id: refreshMouse

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controlsModel.refresh()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.controlsModel.message.length > 0
                text: root.controlsModel.message
                color: Theme.textMuted
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: "Volume"
                color: Theme.textMuted
                font.pixelSize: Theme.smallFontSize
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    label: "Down"
                    enabled: !root.controlsModel.busy
                    onActivated: root.controlsModel.volumeDown()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    label: "Mute"
                    enabled: !root.controlsModel.busy
                    onActivated: root.controlsModel.volumeToggleMute()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 46
                    label: "Up"
                    enabled: !root.controlsModel.busy
                    onActivated: root.controlsModel.volumeUp()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: "Microphone"
                    color: Theme.textMuted
                    font.pixelSize: Theme.smallFontSize
                    font.bold: true
                }

                Text {
                    text: root.controlsModel.micText
                    color: root.controlsModel.micText === "MIC muted" ? "#bf616a" : Theme.text
                    font.pixelSize: Theme.panelFontSize
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Media"
                color: Theme.textMuted
                font.pixelSize: Theme.smallFontSize
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                color: Theme.surface
                radius: Theme.radius
                border.color: Theme.border
                border.width: 1

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.controlsModel.mediaText
                        color: Theme.text
                        font.pixelSize: Theme.panelFontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: root.controlsModel.mediaPlayer.length > 0
                        text: root.controlsModel.mediaPlayer
                        color: Theme.textMuted
                        font.pixelSize: Theme.smallFontSize
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    label: "Previous"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaPrevious()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    label: "Play/Pause"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaPlayPause()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    label: "Next"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaNext()
                }
            }
        }
    }
}
