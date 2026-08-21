import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property string label
    property string detail: ""
    property bool active: false
    property bool danger: false
    property bool hovered: optionMouse.containsMouse

    signal activated

    implicitWidth: Math.max(76, optionLabel.implicitWidth + 22)
    implicitHeight: root.detail.length > 0 ? 48 : Theme.buttonHeight
    activeFocusOnTab: root.enabled
    color: !root.enabled ? Theme.controlDisabledFill
        : root.active ? Theme.controlSelectedFill
        : root.activeFocus ? Theme.controlFocusFill
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.activeFocus ? Theme.controlFocusBorder
        : !root.enabled ? Theme.controlDisabledBorder
        : root.danger ? Theme.danger
        : root.active ? Theme.controlSelectedBorder
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
        anchors.margins: 8
        spacing: Theme.compactSpacing

        Text {
            id: optionLabel

            Layout.fillWidth: true
            Layout.fillHeight: root.detail.length === 0
            text: root.label
            color: !root.enabled ? Theme.controlDisabledText
                : root.active ? Theme.controlSelectedText
                : root.hovered ? Theme.controlHoverText : Theme.textStrong
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.detail.length > 0
            text: root.detail
            color: root.active ? Theme.controlSelectedText : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.tinyFontSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: optionMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
