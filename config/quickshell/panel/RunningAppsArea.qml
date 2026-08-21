import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

RowLayout {
    id: root

    required property var dwmState
    spacing: Theme.panelGap

    Repeater {
        model: root.dwmState.runningApps

        delegate: RunningAppItem {
            required property var modelData
            app: modelData
            active: modelData.appClass === root.dwmState.activeWindowClass
            onFocusRequested: windowId => root.dwmState.focusWindow(windowId)
        }
    }
}
