import QtQuick
import qs.core

Item {
    id: root

    required property string glyph
    property bool active: false
    property int iconPixelSize: Theme.omarchyBarFontSize
    signal activated()
    signal wheelUp()
    signal wheelDown()

    implicitWidth: Theme.pillHeight
    implicitHeight: Theme.pillHeight

    IconText {
        anchors.centerIn: parent
        text: root.glyph
        color: root.active ? Theme.omarchyBarActive : Theme.omarchyBarForeground
        font.pixelSize: root.iconPixelSize
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) {
                root.wheelUp();
            } else if (wheel.angleDelta.y < 0) {
                root.wheelDown();
            }
            wheel.accepted = true;
        }
    }
}
