import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var trayItem
    signal openMenu(var trayItem)

    function handleClick(button) {
        if (button === Qt.LeftButton) {
            if (!root.trayItem.onlyMenu) {
                root.trayItem.activate();
            } else if (root.trayItem.hasMenu) {
                root.openMenu(root.trayItem);
            }
        } else if (button === Qt.MiddleButton) {
            root.trayItem.secondaryActivate();
        } else if (button === Qt.RightButton && root.trayItem.hasMenu) {
            root.openMenu(root.trayItem);
        }
    }

    Layout.preferredWidth: Theme.trayItemSize
    Layout.preferredHeight: Theme.trayItemSize
    radius: 3
    color: trayMouse.containsMouse ? Theme.surface : "transparent"

    IconImage {
        id: trayIcon

        anchors.centerIn: parent
        width: Theme.trayIconSize
        height: Theme.trayIconSize
        source: Icons.trayIconSource(root.trayItem)
        asynchronous: true
        smooth: true
        mipmap: true
        visible: status === Image.Ready
    }

    Text {
        anchors.centerIn: parent
        visible: !trayIcon.visible
        text: {
            const title = root.trayItem.tooltipTitle || root.trayItem.title || root.trayItem.id || "?";
            return title.length > 0 ? title.charAt(0).toUpperCase() : "?";
        }
        color: Theme.text
        font.pixelSize: 10
        font.bold: true
    }

    MouseArea {
        id: trayMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onClicked: mouse => root.handleClick(mouse.button)
    }
}
