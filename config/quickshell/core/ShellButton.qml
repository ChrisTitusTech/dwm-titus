import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property bool danger: false
    property bool compact: true
    property bool hovered: buttonMouse.containsMouse

    signal activated

    implicitWidth: buttonLabel.implicitWidth + 18
    implicitHeight: Theme.buttonHeight
    color: hovered ? Theme.surfaceHover : Theme.surface
    border.color: danger ? Theme.danger : hovered ? Theme.borderStrong : Theme.border
    border.width: 1
    radius: Theme.radius

    Text {
        id: buttonLabel

        anchors.centerIn: parent
        text: root.label
        color: root.danger ? Theme.textStrong : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: root.compact ? Theme.smallFontSize : Theme.panelFontSize
        font.bold: true
        elide: Text.ElideRight
    }

    MouseArea {
        id: buttonMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
