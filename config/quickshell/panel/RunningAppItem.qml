import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var app
    required property var trayItems
    required property bool active
    readonly property var nativeMenuItem: findNativeMenuItem()
    signal focusRequested(string windowId)

    function normalized(value) {
        return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    }

    function findNativeMenuItem() {
        const appName = normalized(root.app.appClass);
        if (appName.length === 0) return null;

        for (let index = 0; index < root.trayItems.length; index++) {
            const item = root.trayItems[index];
            const names = [item.id, item.title, item.tooltipTitle];
            for (let nameIndex = 0; nameIndex < names.length; nameIndex++) {
                const candidate = normalized(names[nameIndex]);
                if (candidate === appName || (candidate.length >= 4 && (candidate.indexOf(appName) >= 0 || appName.indexOf(candidate) >= 0))) {
                    return item;
                }
            }
        }
        return null;
    }

    Layout.preferredWidth: Theme.pillHeight
    Layout.preferredHeight: Theme.pillHeight
    radius: Theme.pillRadius
    color: appMouse.containsMouse ? Theme.surfaceHover : Theme.surface
    border.color: active ? Theme.accent : appMouse.containsMouse ? Theme.borderStrong : Theme.border
    border.width: Theme.pillBorderWidth

    QsMenuAnchor {
        id: nativeMenu
        menu: root.nativeMenuItem && root.nativeMenuItem.hasMenu ? root.nativeMenuItem.menu : null
        anchor.item: root
    }

    IconImage {
        anchors.centerIn: parent
        width: Theme.trayIconSize
        height: Theme.trayIconSize
        source: root.nativeMenuItem ? Icons.trayIconSource(root.nativeMenuItem) : Icons.launcherIcon(root.app.appClass)
    }

    MouseArea {
        id: appMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) root.focusRequested(root.app.windowId);
            else if (root.nativeMenuItem && root.nativeMenuItem.hasMenu) nativeMenu.open();
        }
    }
}
