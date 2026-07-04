import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var trayItem

    function openContextMenu() {
        if (root.trayItem && root.trayItem.hasMenu) {
            trayMenu.open();
        }
    }

    function handleClick(button) {
        if (button === Qt.LeftButton) {
            if (!root.trayItem.onlyMenu) {
                root.trayItem.activate();
            } else if (root.trayItem.hasMenu) {
                root.openContextMenu();
            }
        } else if (button === Qt.MiddleButton) {
            root.trayItem.secondaryActivate();
        }
    }

    Layout.preferredWidth: Theme.trayItemSize
    Layout.preferredHeight: Theme.trayItemSize
    radius: Theme.smallRadius
    color: trayMouse.containsMouse ? Theme.surface : "transparent"

    QsMenuAnchor {
        id: trayMenu

        menu: root.trayItem ? root.trayItem.menu : null
        anchor.item: root
    }

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
        font.family: Theme.fontFamily
        font.pixelSize: Theme.tinyFontSize
        font.bold: true
    }

    MouseArea {
        id: trayMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                root.openContextMenu();
                mouse.accepted = true;
            }
        }

        onClicked: mouse => {
            if (mouse.button !== Qt.RightButton) {
                root.handleClick(mouse.button);
            }
        }
    }
}
