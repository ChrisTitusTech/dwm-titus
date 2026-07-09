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
    opacity: enabled ? 1 : 0.52
    color: root.active ? Theme.accent : root.hovered && enabled ? Theme.surfaceHover : Theme.surface
    border.color: root.danger ? Theme.danger : root.active ? Theme.accent : Theme.border
    border.width: 1
    radius: Theme.radius

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: Theme.compactSpacing

        Text {
            id: optionLabel

            Layout.fillWidth: true
            Layout.fillHeight: root.detail.length === 0
            text: root.label
            color: root.active ? Theme.accentText : Theme.textStrong
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
            color: root.active ? Theme.accentText : Theme.textMuted
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
