import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.core

RowLayout {
    id: root

    readonly property var visibleItems: SystemTray.items.values.filter(function(item) {
        return item.id !== "blueman" && item.id !== "blueman-applet";
    })
    visible: visibleItems.length > 0
    spacing: Theme.compactSpacing

    Repeater {
        model: root.visibleItems

        delegate: TrayItem {
            required property var modelData

            trayItem: modelData
        }
    }
}
