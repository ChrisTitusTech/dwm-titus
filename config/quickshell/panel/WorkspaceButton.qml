import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property string label
    required property bool selected
    signal clicked()

    Layout.preferredWidth: 22
    Layout.preferredHeight: 22
    radius: 3
    color: selected ? Theme.surface : "transparent"

    Text {
        anchors.centerIn: parent
        text: root.label
        color: root.selected ? Theme.accent : Theme.text
        font.pixelSize: Theme.panelFontSize
        font.bold: root.selected
        verticalAlignment: Text.AlignVCenter
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
