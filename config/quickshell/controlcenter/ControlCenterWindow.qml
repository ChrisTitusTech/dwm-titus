import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var controlCenterModel
    required property var panelWindow
    required property var powerMenuModel

    readonly property int cardWidth: 276
    readonly property int gap: 8
    property string sidePanel: "widgets"

    function sideTitle() {
        if (sidePanel === "utilities") return "Utilities";
        if (sidePanel === "actions") return "Quick Actions";
        if (sidePanel === "appearance") return "Appearance";
        return "Widgets";
    }

    visible: controlCenterModel.visible
    implicitWidth: cardWidth * 2 + gap
    implicitHeight: Math.max(controlCard.implicitHeight, sideCard.implicitHeight)
    anchor.window: panelWindow
    anchor.rect.x: 6
    anchor.rect.y: Theme.panelHeight
    grabFocus: true
    color: Theme.transparent

    component Tile: Rectangle {
        id: tile

        property string label: ""
        property bool active: false
        signal activated()

        implicitHeight: 26
        radius: Theme.smallRadius
        color: active ? Theme.surfaceActive : (tileMouse.containsMouse ? Theme.surfaceHover : Theme.surface)
        border.color: active || tileMouse.containsMouse ? Theme.accentSecondary : Theme.border
        border.width: Theme.pillBorderWidth

        UiText {
            anchors.centerIn: parent
            text: tile.label
            color: tile.active || tileMouse.containsMouse ? Theme.accentSecondary : Theme.text
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            root.controlCenterModel.close();
            event.accepted = true;
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.gap

        ShellSurface {
            id: controlCard

            Layout.preferredWidth: root.cardWidth
            Layout.alignment: Qt.AlignTop
            margin: 12
            implicitHeight: controlColumn.implicitHeight + margin * 2

            ColumnLayout {
                id: controlColumn
                width: parent.width
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true

                    UiText {
                        Layout.fillWidth: true
                        text: "Control"
                        color: Theme.textStrong
                        font.letterSpacing: 2
                    }

                    UiText {
                        text: "×"
                        color: closeMouse.containsMouse ? Theme.accent : Theme.textMuted

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.controlCenterModel.close()
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                UiText { text: "Actions"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: "Reload QS-Config"
                    onActivated: root.controlCenterModel.runAction("restart-quickshell")
                }
                Tile {
                    Layout.fillWidth: true
                    label: "Power  ▸"
                    onActivated: {
                        root.controlCenterModel.close();
                        root.powerMenuModel.open();
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Bar Color"; color: Theme.textMuted; font.letterSpacing: 1 }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    Repeater {
                        model: ["Red", "Accent", "Color 02", "Color 03"]
                        delegate: Tile {
                            required property string modelData
                            Layout.fillWidth: true
                            label: modelData
                            active: modelData === "Accent"
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Splits"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile { Layout.fillWidth: true; label: "Splits  ▸" }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Bar Functions"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: root.sidePanel === "widgets" ? "Bar Functions  ◂" : "Bar Functions  ▸"
                    active: root.sidePanel === "widgets"
                    onActivated: root.sidePanel = "widgets"
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Utilities"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: root.sidePanel === "utilities" ? "Utilities  ◂" : "Utilities  ▸"
                    active: root.sidePanel === "utilities"
                    onActivated: root.sidePanel = "utilities"
                }
            }
        }

        ShellSurface {
            id: sideCard

            Layout.preferredWidth: root.cardWidth
            Layout.alignment: Qt.AlignTop
            margin: 12
            implicitHeight: sideColumn.implicitHeight + margin * 2

            ColumnLayout {
                id: sideColumn
                width: parent.width
                spacing: 8

                UiText {
                    text: root.sideTitle()
                    color: Theme.textStrong
                    font.letterSpacing: 2
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                GridLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "widgets"
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        model: ["Volume", "Bluetooth", "Network", "Power", "Workspaces"]
                        delegate: Tile {
                            required property string modelData
                            Layout.fillWidth: true
                            label: modelData
                            active: true
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "utilities"
                    spacing: 8

                    Tile {
                        Layout.fillWidth: true
                        label: "System Health  ›"
                        onActivated: root.controlCenterModel.openHealth()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Quick Actions  ›"
                        onActivated: {
                            root.controlCenterModel.openActions();
                            root.sidePanel = "actions";
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Appearance  ›"
                        onActivated: {
                            root.controlCenterModel.openAppearance();
                            root.sidePanel = "appearance";
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Keybinds  ›"
                        onActivated: root.controlCenterModel.openKeybinds()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "System Info  ›"
                        onActivated: root.controlCenterModel.openInfo()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "actions"
                    spacing: 8

                    Repeater {
                        model: root.controlCenterModel.actions
                        delegate: Tile {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.label
                            onActivated: root.controlCenterModel.runAction(modelData.id)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "appearance"
                    spacing: 8

                    Repeater {
                        model: root.controlCenterModel.themeRows
                        delegate: Tile {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.name
                            active: modelData.status === "active"
                            onActivated: root.controlCenterModel.setTheme(modelData.name)
                        }
                    }
                }
            }
        }
    }
}
