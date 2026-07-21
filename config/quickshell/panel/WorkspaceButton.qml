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
    color: Theme.transparent
    border.color: selected ? Theme.accent : Theme.transparent
    border.width: selected ? Theme.pillBorderWidth : 0

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.accent : Theme.textMuted
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
