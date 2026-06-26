import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property var action
    property bool compact: false
    property bool danger: false

    signal activated

    radius: Theme.radius
    color: actionMouse.containsMouse ? Theme.surfaceHover : Theme.surface
    border.color: danger ? "#bf616a" : Theme.border
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
        anchors.leftMargin: compact ? 12 : 14
        anchors.rightMargin: compact ? 12 : 14
        spacing: compact ? 2 : 4

        Text {
            width: parent.width
            text: root.action.label
            color: root.danger ? "#eceff4" : Theme.text
            font.pixelSize: root.compact ? 14 : 15
            font.bold: true
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: root.action.detail || ""
            color: Theme.textMuted
            font.pixelSize: Theme.smallFontSize
            elide: Text.ElideRight
            visible: text.length > 0
        }
    }
}
