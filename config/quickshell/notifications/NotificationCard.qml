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
    color: item.urgency === NotificationUrgency.Critical ? Theme.dangerSurface : Theme.surface
    border.color: item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.border
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
        spacing: Theme.rowSpacing

        Rectangle {
            Layout.preferredWidth: Theme.notificationAccentWidth
            Layout.fillHeight: true
            radius: Theme.notificationAccentRadius
            color: root.item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.accent
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.tightSpacing

            Text {
                Layout.fillWidth: true
                text: root.item.appName
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.item.summary || root.item.urgencyName
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.item.body || ""
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: Theme.closeButtonSize - Theme.listSpacing
            Layout.preferredHeight: Theme.closeButtonSize - Theme.listSpacing
            radius: Theme.radius
            color: closeMouse.containsMouse ? Theme.surfaceHover : Theme.transparent
            border.color: Theme.border
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: "x"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
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
