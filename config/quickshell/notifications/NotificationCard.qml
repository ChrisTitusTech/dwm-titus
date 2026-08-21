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
    Layout.preferredHeight: Math.max(82, content.implicitHeight + 28)

    opacity: 1.0
    radius: Theme.largeSurfaceCardRadius
    color: item.urgency === NotificationUrgency.Critical ? Theme.dangerSurface : Theme.surface
    border.color: item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.popupBorder
    border.width: Theme.controlBorderWidth

    Timer {
        interval: root.item.timeoutMs
        running: true
        repeat: false
        onTriggered: root.expired()
    }

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 14
        spacing: Theme.spacingXxl

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
                color: root.item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.menuActionText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontCaptionSize
                font.bold: true
                font.letterSpacing: 0.6
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.item.summary || root.item.urgencyName
                color: Theme.popupText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.item.body || ""
                color: Theme.menuText
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
            radius: Theme.controlRadius
            color: closeMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
            border.color: closeMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
            border.width: Theme.controlBorderWidth

            Text {
                anchors.centerIn: parent
                text: "x"
                color: closeMouse.containsMouse ? Theme.controlHoverText : Theme.menuMutedText
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
