import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var controlCenterModel
    required property var healthModel
    required property var panelWindow
    required property var powerMenuModel
    required property var settingsModel

    readonly property int cardWidth: Theme.controlCenterWidth
    readonly property int gap: Theme.controlCenterGap
    readonly property var powerPresets: [
        { "label": "5m", "seconds": 300 },
        { "label": "10m", "seconds": 600 },
        { "label": "15m", "seconds": 900 },
        { "label": "30m", "seconds": 1800 },
        { "label": "1h", "seconds": 3600 }
    ]
    property string sidePanel: "none"

    function sideTitle() {
        if (sidePanel === "utilities") return "Utilities";
        if (sidePanel === "actions") return "Quick Actions";
        if (sidePanel === "appearance") return "Appearance";
        if (sidePanel === "power") return "Power Settings";
        return "Widgets";
    }

    function formatDuration(seconds) {
        if (seconds >= 3600 && seconds % 3600 === 0) {
            return (seconds / 3600) + "h";
        }
        if (seconds >= 60 && seconds % 60 === 0) {
            return (seconds / 60) + "m";
        }
        return seconds + "s";
    }

    function openSystemHealth() {
        root.controlCenterModel.close();
        root.healthModel.openOnScreen(root.panelWindow.screen);
    }

    function openSettings() {
        root.controlCenterModel.close();
        root.settingsModel.open();
    }

    function openPowerSettings() {
        root.controlCenterModel.openPower();
        root.sidePanel = "power";
    }

    visible: controlCenterModel.visible
    targetWindow: panelWindow
    popupX: Theme.controlCenterX
    popupY: Theme.panelHeight
    popupWidth: cardWidth + (sidePanel === "none" ? 0 : cardWidth + gap)
    popupHeight: sidePanel === "none" ? controlCard.implicitHeight : Math.max(controlCard.implicitHeight, sideCard.implicitHeight)
    onDismissed: controlCenterModel.close()

    onVisibleChanged: {
        if (visible) {
            sidePanel = "none";
            Qt.callLater(function() {
                controlCard.forceActiveFocus();
            });
        } else {
            root.controlCenterModel.close();
        }
    }

    component Tile: Rectangle {
        id: tile

        property string label: ""
        property bool active: false
        signal activated()

        implicitHeight: 26
        radius: Theme.smallRadius
        color: active ? Theme.surfaceActive : tileMouse.containsMouse ? Theme.surfaceHover : Theme.surface
        border.color: active ? Theme.accentSecondary : tileMouse.containsMouse ? Theme.borderStrong : Theme.border
        border.width: Theme.pillBorderWidth

        UiText {
            anchors.centerIn: parent
            text: tile.label
            color: tile.active ? Theme.accentSecondary : tileMouse.containsMouse ? Theme.textStrong : Theme.text
        }

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            enabled: tile.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: tile.activated()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.gap

        ShellSurface {
            id: controlCard

            Layout.preferredWidth: root.cardWidth
            Layout.maximumHeight: implicitHeight
            Layout.alignment: Qt.AlignTop
            margin: 12
            implicitHeight: controlColumn.implicitHeight + margin * 2
            focus: true

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                    root.controlCenterModel.close();
                    event.accepted = true;
                }
            }

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
                        text: "x"
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

                UiText {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.message.length > 0
                    text: root.controlCenterModel.message
                    color: Theme.textMuted
                    elide: Text.ElideRight
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                UiText { text: "Actions"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: "Reload QS-Config"
                    enabled: !root.controlCenterModel.busy
                    onActivated: root.controlCenterModel.runAction("restart-quickshell")
                }
                Tile {
                    Layout.fillWidth: true
                    label: "Power  >"
                    onActivated: {
                        root.powerMenuModel.open("controlcenter");
                    }
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Bar Functions"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: root.sidePanel === "widgets" ? "Bar Functions  <" : "Bar Functions  >"
                    active: root.sidePanel === "widgets"
                    onActivated: root.sidePanel = root.sidePanel === "widgets" ? "none" : "widgets"
                }

                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }
                UiText { text: "Utilities"; color: Theme.textMuted; font.letterSpacing: 1 }
                Tile {
                    Layout.fillWidth: true
                    label: root.sidePanel === "utilities" ? "Utilities  <" : "Utilities  >"
                    active: root.sidePanel === "utilities"
                    onActivated: root.sidePanel = root.sidePanel === "utilities" ? "none" : "utilities"
                }
            }
        }

        ShellSurface {
            id: sideCard

            Layout.preferredWidth: root.cardWidth
            Layout.maximumHeight: implicitHeight
            Layout.alignment: Qt.AlignTop
            margin: 12
            implicitHeight: sideColumn.implicitHeight + margin * 2
            visible: root.sidePanel !== "none"

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
                            active: root.controlCenterModel.widgetEnabled(modelData)
                            onActivated: root.controlCenterModel.toggleWidget(modelData)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "utilities"
                    spacing: 8

                    Tile {
                        Layout.fillWidth: true
                        label: "Settings  >"
                        onActivated: root.openSettings()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "System Health  >"
                        onActivated: root.openSystemHealth()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Quick Actions  >"
                        onActivated: {
                            root.controlCenterModel.openActions();
                            root.sidePanel = "actions";
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Appearance  >"
                        onActivated: {
                            root.controlCenterModel.openAppearance();
                            root.sidePanel = "appearance";
                        }
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Keybinds  >"
                        onActivated: root.controlCenterModel.openKeybinds()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "Power Settings  >"
                        onActivated: root.openPowerSettings()
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: "System Info  >"
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
                            enabled: !root.controlCenterModel.busy
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
                            enabled: !root.controlCenterModel.busy
                            onActivated: root.controlCenterModel.setTheme(modelData.name)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.sidePanel === "power"
                    spacing: 8

                    UiText {
                        Layout.fillWidth: true
                        text: root.controlCenterModel.powerDpmsEnabled
                            ? "Screen off after " + root.formatDuration(root.controlCenterModel.powerDpmsTimeout)
                            : "Screen DPMS disabled"
                        color: Theme.textMuted
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: root.controlCenterModel.powerDpmsEnabled ? "Disable Screen DPMS" : "Enable Screen DPMS"
                        active: root.controlCenterModel.powerDpmsEnabled
                        enabled: root.controlCenterModel.powerDpmsAvailable && !root.controlCenterModel.busy
                        onActivated: root.controlCenterModel.setPowerDpms(!root.controlCenterModel.powerDpmsEnabled)
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 6
                        rowSpacing: 6

                        Repeater {
                            model: root.powerPresets
                            delegate: Tile {
                                required property var modelData
                                Layout.fillWidth: true
                                label: modelData.label
                                active: root.controlCenterModel.powerDpmsEnabled
                                    && root.controlCenterModel.powerDpmsTimeout === modelData.seconds
                                enabled: root.controlCenterModel.powerDpmsAvailable && !root.controlCenterModel.busy
                                onActivated: root.controlCenterModel.setPowerDpmsTimeout(modelData.seconds)
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                    UiText {
                        Layout.fillWidth: true
                        text: root.controlCenterModel.powerLockEnabled
                            ? "Lock after " + root.formatDuration(root.controlCenterModel.powerLockTimeout)
                            : "Auto Lock disabled"
                        color: Theme.textMuted
                    }
                    Tile {
                        Layout.fillWidth: true
                        label: root.controlCenterModel.powerLockEnabled ? "Disable Auto Lock" : "Enable Auto Lock"
                        active: root.controlCenterModel.powerLockEnabled
                        enabled: root.controlCenterModel.powerLockAvailable && !root.controlCenterModel.busy
                        onActivated: root.controlCenterModel.setPowerLock(!root.controlCenterModel.powerLockEnabled)
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 6
                        rowSpacing: 6

                        Repeater {
                            model: root.powerPresets
                            delegate: Tile {
                                required property var modelData
                                Layout.fillWidth: true
                                label: modelData.label
                                active: root.controlCenterModel.powerLockEnabled
                                    && root.controlCenterModel.powerLockTimeout === modelData.seconds
                                enabled: root.controlCenterModel.powerLockAvailable && !root.controlCenterModel.busy
                                onActivated: root.controlCenterModel.setPowerLockTimeout(modelData.seconds)
                            }
                        }
                    }
                }
            }
        }
    }
}
