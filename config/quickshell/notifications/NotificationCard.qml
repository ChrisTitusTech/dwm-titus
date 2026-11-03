import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs.core

Rectangle {
    id: root

    required property var item

    signal dismiss
    signal expired
    signal actionInvoked(string identifier)

    Layout.fillWidth: true
    Layout.preferredHeight: Math.max(Theme.scaledSize(82), content.implicitHeight + Theme.scaledSize(28))

    opacity: 1.0
    radius: Theme.popupRadius
    color: item.urgency === NotificationUrgency.Critical ? Theme.dangerSurface : Theme.surface
    border.color: item.urgency === NotificationUrgency.Critical ? Theme.danger : Theme.popupBorder
    border.width: Theme.controlBorderWidth

    Timer {
        interval: Math.max(1, root.item.timeoutMs)
        running: root.item.timeoutMs > 0
        repeat: false
        onTriggered: root.expired()
    }

    // Clicking the body runs the client's default action, when it has one.
    MouseArea {
        anchors.fill: parent
        enabled: root.item.hasDefaultAction === true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.actionInvoked("default")
    }

    RowLayout {
        id: content

        anchors.fill: parent
        anchors.margins: Theme.scaledSize(14)
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

            NotificationActions {
                Layout.topMargin: Theme.tightSpacing
                actions: root.item.actions || []
                critical: root.item.urgency === NotificationUrgency.Critical
                onInvoked: identifier => root.actionInvoked(identifier)
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.dismiss()
            }
        }
    }
}
