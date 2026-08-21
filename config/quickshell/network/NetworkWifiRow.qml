import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property var network
    property bool selected: false
    property bool busy: false
    property bool actionsEnabled: true
    property bool delegated: false
    signal selectedRequested
    signal connectRequested(var network)

    height: 54
    color: root.selected ? Theme.controlSelectedFill
        : rowMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.selected ? Theme.controlSelectedBorder
        : rowMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: Theme.controlBorderWidth
    radius: Theme.radius

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: root.selectedRequested()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.rowSpacing
        anchors.rightMargin: Theme.rowSpacing
        spacing: Theme.rowSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.compactSpacing

            Text {
                Layout.fillWidth: true
                text: root.network.ssid
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: (root.network.security.length > 0 ? root.network.security : "Open") + " - " + root.network.signal + "% - " + root.network.device
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.preferredWidth: 54
            text: root.network.active ? "Active" : ""
            color: Theme.controlSelectedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }

        ShellButton {
            Layout.preferredHeight: Theme.chipHeight
            label: root.delegated ? "Advanced" : root.busy ? "Connecting..." : "Connect"
            enabled: root.actionsEnabled && !root.busy
            onActivated: root.connectRequested(root.network)
        }
    }
}
