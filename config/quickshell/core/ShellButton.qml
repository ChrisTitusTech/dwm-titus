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
    color: !root.enabled ? Theme.barBackground : root.hovered ? Theme.surfaceHover : Theme.surface
    border.color: !root.enabled ? Theme.border : root.danger ? Theme.danger : root.hovered ? Theme.borderStrong : Theme.border
    border.width: 1
    radius: Theme.radius

    Text {
        id: buttonLabel

        anchors.centerIn: parent
        text: root.label
        color: !root.enabled ? Theme.textMuted : root.danger ? Theme.textStrong : Theme.text
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
