import QtQuick
import Quickshell
import qs.core

PopupWindow {
    id: root

    default property alias popupContent: popupHost.data
    required property var targetWindow
    property int popupX: 0
    property int popupY: Theme.panelHeight
    property int popupWidth: 320
    property int popupHeight: 320

    signal dismissed

    color: Theme.transparent
    implicitWidth: targetWindow.width
    implicitHeight: targetWindow.screen.height

    anchor {
        window: targetWindow
        rect.x: 0
        rect.y: 0
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Item {
        id: popupHost

        x: root.popupX
        y: root.popupY
        width: root.popupWidth
        height: root.popupHeight
        z: 1

        MouseArea {
            anchors.fill: parent
        }
    }
}
