import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var bluetoothModel
    required property var panelWindow

    readonly property int popupWidth: 360
    readonly property int popupHeight: 420
    property bool receivedFocus: false

    visible: bluetoothModel.visible
    implicitWidth: popupWidth
    implicitHeight: popupHeight
    anchor.window: panelWindow
    anchor.rect.x: Math.max(Theme.rowSpacing, panelWindow.width - popupWidth - Theme.rowSpacing)
    anchor.rect.y: Theme.panelHeight
    grabFocus: true
    color: Theme.transparent

    onActiveChanged: {
        if (active) root.receivedFocus = true;
        else if (visible && root.receivedFocus) root.bluetoothModel.close();
    }

    onVisibleChanged: if (!visible) receivedFocus = false

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.bluetoothModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true
                UiText { Layout.fillWidth: true; text: root.bluetoothModel.statusText; color: Theme.textStrong; font.pixelSize: Theme.titleFontSize; font.bold: true }
                ShellButton { label: "Scan"; onActivated: root.bluetoothModel.refresh(true) }
            }

            RowLayout {
                Layout.fillWidth: true
                ShellButton { Layout.fillWidth: true; label: "Bluetooth On"; onActivated: root.bluetoothModel.action("bluetooth-power", ["on"]) }
                ShellButton { Layout.fillWidth: true; label: "Bluetooth Off"; onActivated: root.bluetoothModel.action("bluetooth-power", ["off"]) }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.bluetoothModel.devices

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: 58
                    radius: Theme.smallRadius
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: Theme.pillBorderWidth

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        UiText {
                            Layout.fillWidth: true
                            text: modelData.name.length > 0 ? modelData.name : modelData.address
                            elide: Text.ElideRight
                        }
                        ShellButton {
                            label: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                            onActivated: root.bluetoothModel.action(modelData.connected ? "bluetooth-disconnect" : (modelData.paired ? "bluetooth-connect" : "bluetooth-pair"), [modelData.address])
                        }
                    }
                }
            }
        }
    }
}
