import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property bool danger: false
    property bool primary: false
    property bool compact: true
    property bool hovered: buttonMouse.containsMouse

    signal activated

    implicitWidth: buttonLabel.implicitWidth + (Theme.controlPaddingX * 2)
    implicitHeight: Theme.controlHeight
    activeFocusOnTab: root.enabled
    color: !root.enabled ? Theme.controlDisabledFill
        : root.danger ? (root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill)
        : root.primary ? (root.hovered ? Theme.accentSecondary : Theme.accent)
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.activeFocus ? (root.primary ? Theme.textStrong : Theme.controlFocusBorder)
        : !root.enabled ? Theme.controlDisabledBorder
        : root.danger ? Theme.danger
        : root.primary ? Theme.accent
        : root.hovered ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
    radius: Theme.controlRadius

    Keys.onPressed: event => {
        if (root.enabled && !event.isAutoRepeat
                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.activated();
            event.accepted = true;
        }
    }

    Text {
        id: buttonLabel

        anchors.centerIn: parent
        text: root.label
        color: !root.enabled ? Theme.controlDisabledText
            : root.danger ? Theme.textStrong
            : root.primary ? Theme.accentText
            : root.hovered ? Theme.controlHoverText : Theme.controlNormalText
        font.family: Theme.fontFamily
        font.pixelSize: root.compact ? Theme.fontBodySmallSize : Theme.fontBodySize
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
