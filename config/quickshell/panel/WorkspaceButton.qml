import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property string label
    required property bool selected
    required property bool occupied
    signal clicked()

    Layout.preferredWidth: Theme.workspaceButtonSize
    Layout.preferredHeight: Theme.workspaceButtonSize
    radius: Theme.smallRadius
    color: selected ? Theme.controlSelectedFill
        : workspaceMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
    border.color: selected ? Theme.controlSelectedBorder
        : workspaceMouse.containsMouse ? Theme.controlHoverBorder : Theme.transparent
    border.width: selected || workspaceMouse.containsMouse ? Theme.pillBorderWidth : 0

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.controlSelectedText
            : workspaceMouse.containsMouse ? Theme.controlHoverText : Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.panelFontSize
        font.bold: root.selected
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        id: workspaceMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
