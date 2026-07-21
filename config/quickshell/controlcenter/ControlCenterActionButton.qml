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
    opacity: enabled ? 1 : 0.55
    color: Theme.surface
    border.color: Theme.border
    border.width: 1
    radius: Theme.radius

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: Theme.tightSpacing

        Text {
            Layout.fillWidth: true
            text: root.label
            color: Theme.textStrong
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
