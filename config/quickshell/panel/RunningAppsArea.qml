import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.core

RowLayout {
    id: root

    required property var state
    spacing: Theme.panelGap

    Repeater {
        model: root.state.runningApps

        delegate: RunningAppItem {
            required property var modelData
            app: modelData
            trayItems: SystemTray.items.values
            active: modelData.appClass === root.state.activeWindowClass
            onFocusRequested: windowId => root.state.focusWindow(windowId)
        }
    }
}
