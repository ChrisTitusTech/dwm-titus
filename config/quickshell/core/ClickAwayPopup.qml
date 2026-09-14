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
    grabFocus: true
    implicitWidth: targetWindow ? targetWindow.width : 0
    // Keep the transparent click-away surface below the panel so compositors
    // cannot blur the bar through this popup. Content coordinates stay panel-relative.
    readonly property int panelOffset: targetWindow ? targetWindow.height : 0
    implicitHeight: targetWindow && targetWindow.screen ? Math.max(0, targetWindow.screen.height - panelOffset) : 0

    anchor {
        window: targetWindow
        rect.x: 0
        rect.y: root.panelOffset
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Item {
        id: popupHost

        x: root.popupX
        y: root.popupY - root.panelOffset
        width: root.popupWidth
        height: root.popupHeight
        opacity: 1.0
        z: 1

        MouseArea {
            anchors.fill: parent
        }
    }
}
