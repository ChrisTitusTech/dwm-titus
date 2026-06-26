import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.core

PanelWindow {
    id: root

    required property var state
    required property var clock

    implicitHeight: Theme.panelHeight
    color: Theme.bg
    exclusiveZone: Theme.panelHeight
    aboveWindows: true

    anchors {
        top: true
        left: true
        right: true
    }

    function openTrayMenu(trayItem, anchorItem) {
        if (!trayItem || !trayItem.hasMenu) {
            return;
        }

        const point = anchorItem.mapToItem(root.contentItem, anchorItem.width / 2, anchorItem.height);

        trayItem.display(root, Math.round(point.x), Math.round(point.y));
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        spacing: 10

        Text {
            text: "dwm"
            color: Theme.text
            font.pixelSize: Theme.panelFontSize
            font.bold: true
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: root.state.workspaceNames

            delegate: WorkspaceButton {
                required property int index
                required property string modelData

                label: modelData
                selected: index === root.state.currentWorkspace
                onClicked: root.state.switchWorkspace(index)
            }
        }

        Text {
            Layout.maximumWidth: 360
            text: root.state.activeWindowTitle
            color: Theme.text
            elide: Text.ElideRight
            font.pixelSize: Theme.panelFontSize
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: root.state.statusSegments

            delegate: Text {
                required property string modelData

                text: modelData
                color: Theme.text
                font.pixelSize: Theme.panelFontSize
                verticalAlignment: Text.AlignVCenter
            }
        }

        TrayArea {
            onOpenMenu: (trayItem, anchorItem) => root.openTrayMenu(trayItem, anchorItem)
        }

        Text {
            text: Qt.formatDateTime(root.clock.date, "ddd MMM dd  hh:mm")
            color: Theme.accent
            font.pixelSize: Theme.panelFontSize
            verticalAlignment: Text.AlignVCenter
        }
    }
}
