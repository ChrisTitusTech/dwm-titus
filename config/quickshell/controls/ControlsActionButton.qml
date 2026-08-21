import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label

    signal activated

    activeFocusOnTab: root.enabled
    radius: Theme.radius
    color: !root.enabled ? Theme.controlDisabledFill
        : root.activeFocus ? Theme.controlFocusFill
        : controlMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.activeFocus ? Theme.controlFocusBorder
        : !root.enabled ? Theme.controlDisabledBorder
        : controlMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth

    Keys.onPressed: function(event) {
        if (!root.enabled || event.isAutoRepeat) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activated();
            event.accepted = true;
        }
    }

    Text {
        anchors.centerIn: parent
        text: root.label
        color: !root.enabled ? Theme.controlDisabledText
            : controlMouse.containsMouse ? Theme.controlHoverText : Theme.controlNormalText
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
