import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label

    signal activated

    radius: Theme.radius
    color: Theme.surface
    border.color: Theme.border
    border.width: 1

    Text {
        anchors.centerIn: parent
        text: root.label
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.panelFontSize
        font.bold: true
        elide: Text.ElideRight
    }

    MouseArea {
        id: controlMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
