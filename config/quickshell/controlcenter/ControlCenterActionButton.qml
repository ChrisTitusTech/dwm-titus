import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property string label
    required property string detail
    property bool hovered: mouse.containsMouse

    signal activated

    implicitHeight: 58
    activeFocusOnTab: root.enabled
    color: !root.enabled ? Theme.controlDisabledFill
        : root.activeFocus ? Theme.controlFocusFill
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.activeFocus ? Theme.controlFocusBorder
        : !root.enabled ? Theme.controlDisabledBorder
        : root.hovered ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
    radius: Theme.radius

    Keys.onPressed: function(event) {
        if (!root.enabled || event.isAutoRepeat) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activated();
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: Theme.tightSpacing

        Text {
            Layout.fillWidth: true
            text: root.label
            color: !root.enabled ? Theme.controlDisabledText
                : root.hovered ? Theme.controlHoverText : Theme.textStrong
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            text: root.detail
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
