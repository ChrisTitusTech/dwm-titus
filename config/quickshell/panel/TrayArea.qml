import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray

RowLayout {
    id: root

    signal openMenu(var trayItem, var anchorItem)

    visible: SystemTray.items.values.length > 0
    spacing: 2

    Repeater {
        model: SystemTray.items.values

        delegate: TrayItem {
            required property var modelData

            trayItem: modelData
            onOpenMenu: trayItem => root.openMenu(trayItem, this)
        }
    }
}
