import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property var network
    property bool selected: false
    property bool busy: false
    signal selectedRequested
    signal connectRequested(var network)

    height: 54
    color: root.selected ? Theme.surfaceHover : (rowMouse.containsMouse ? Theme.surfaceHover : Theme.surface)
    border.color: root.selected ? Theme.accent : Theme.border
    border.width: root.selected ? 1 : 0
    radius: Theme.radius

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.selectedRequested()
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
                text: root.network.ssid
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: (root.network.security.length > 0 ? root.network.security : "Open") + " - " + root.network.signal + "% - " + root.network.device
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.preferredWidth: 54
            text: root.network.active ? "Active" : ""
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.preferredWidth: actionText.implicitWidth + 18
            Layout.preferredHeight: Theme.chipHeight
            color: actionMouse.containsMouse && !root.busy ? Theme.accent : Theme.border
            radius: Theme.radius
            opacity: root.busy ? 0.5 : 1

            Text {
                id: actionText

                anchors.centerIn: parent
                text: "Connect"
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            MouseArea {
                id: actionMouse

                anchors.fill: parent
                enabled: !root.busy
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.connectRequested(root.network)
            }
        }
    }
}
