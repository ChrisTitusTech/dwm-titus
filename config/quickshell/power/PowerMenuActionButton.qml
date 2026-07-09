import QtQuick
import qs.core

Rectangle {
    id: root

    required property var action
    property bool compact: false
    property bool danger: false

    signal activated

    radius: Theme.radius
    color: actionMouse.containsMouse ? Theme.surfaceHover : Theme.surface
    border.color: danger ? Theme.danger : Theme.border
    border.width: 1

    MouseArea {
        id: actionMouse

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.compact ? 12 : 14
        anchors.rightMargin: root.compact ? 12 : 14
        spacing: root.compact ? Theme.compactSpacing : Theme.listSpacing

        Text {
            width: parent.width
            text: root.action.label
            color: root.danger ? Theme.textStrong : Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: root.compact ? Theme.bodyFontSize : Theme.bodyFontSize + 1
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.action.detail || ""
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            elide: Text.ElideRight
            visible: text.length > 0
        }
    }
}
