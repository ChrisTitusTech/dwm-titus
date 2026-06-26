import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.core

Rectangle {
    id: root

    required property var item

    signal dismiss
    signal expired

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(72, content.implicitHeight + 24)

    radius: Theme.radius
    color: item.urgency === NotificationUrgency.Critical ? "#4a2f35" : Theme.surface
    border.color: item.urgency === NotificationUrgency.Critical ? "#bf616a" : Theme.border
    border.width: 1

    Timer {
        interval: root.item.timeoutMs
        running: true
        repeat: false
        onTriggered: root.expired()
    }

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 12
        spacing: 10

        Rectangle {
            Layout.preferredWidth: 4
            Layout.fillHeight: true
            radius: 2
            color: root.item.urgency === NotificationUrgency.Critical ? "#bf616a" : Theme.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            Text {
                Layout.fillWidth: true
                text: root.item.appName
                color: Theme.textMuted
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.item.summary || root.item.urgencyName
                color: Theme.textStrong
                font.pixelSize: 14
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.item.body || ""
                color: Theme.text
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 26
            radius: Theme.radius
            color: closeMouse.containsMouse ? Theme.surfaceHover : "#00000000"
            border.color: Theme.border
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "x"
                color: Theme.text
                font.pixelSize: 13
                font.bold: true
            }

            MouseArea {
                id: closeMouse

                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
            }
        }
    }
}
