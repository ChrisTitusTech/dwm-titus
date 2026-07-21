import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.core

RowLayout {
    id: root

    visible: SystemTray.items.values.length > 0
    spacing: Theme.compactSpacing

    Repeater {
        model: SystemTray.items.values

        delegate: TrayItem {
            required property var modelData
            trayItem: modelData
        }
    }
}
