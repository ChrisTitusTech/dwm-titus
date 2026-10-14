import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    property bool busy: false
    property bool actionsEnabled: true
    signal joinRequested

    height: Theme.scaledSize(54)
    color: rowMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: rowMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth
    radius: Theme.radius

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        enabled: root.actionsEnabled && !root.busy
        onClicked: root.joinRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.rowSpacing
        anchors.rightMargin: Theme.rowSpacing
        spacing: Theme.rowSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.compactSpacing

            Text {
                Layout.fillWidth: true
                text: "Hidden network..."
                color: Theme.readableText(Theme.textStrong, String(root.color))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: "Join a network that does not broadcast its name"
                color: Theme.readableText(Theme.textMuted, String(root.color))
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }
        }

        ShellButton {
            Layout.preferredHeight: Theme.chipHeight
            label: "Join"
            accessibleDescription: "Join a hidden Wi-Fi network"
            enabled: root.actionsEnabled && !root.busy
            onActivated: root.joinRequested()
        }
    }
}
