import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var controlCenterModel

    readonly property var overviewPages: [
        { "id": "health", "label": "System Health", "detail": "Check required commands, config paths, and desktop tools" },
        { "id": "actions", "label": "Quick Actions", "detail": "Restart desktop services and open common tools" },
        { "id": "appearance", "label": "Appearance", "detail": "Switch active dwm-titus themes" },
        { "id": "keybinds", "label": "Keybinds", "detail": "Browse live hotkeys from hotkeys.toml" },
        { "id": "power", "label": "Power", "detail": "Screen DPMS and auto-lock timing" },
        { "id": "info", "label": "System Info", "detail": "View session and host details" }
    ]
    readonly property var actions: [
        { "id": "restart-picom", "label": "Restart Picom", "detail": "Restart the compositor" },
        { "id": "restart-quickshell", "label": "Restart Quickshell", "detail": "Restart the desktop shell" },
        { "id": "reload-wallpaper", "label": "Reload Wallpaper", "detail": "Randomize the wallpaper folder" },
        { "id": "restart-networkmanager", "label": "Restart NetworkManager", "detail": "Open a terminal for the privileged restart" },
        { "id": "dependency-check", "label": "Dependency Check", "detail": "Run check-deps.sh in a terminal" },
        { "id": "install-missing-deps", "label": "Install Missing Deps", "detail": "Run the installer in a terminal" },
        { "id": "open-wallpapers", "label": "Wallpaper Folder", "detail": "Open the wallpaper directory" },
        { "id": "gtk-settings", "label": "GTK Settings", "detail": "Open nwg-look when installed" }
    ]
    readonly property var powerPresets: [
        { "label": "5m", "seconds": 300 },
        { "label": "10m", "seconds": 600 },
        { "label": "15m", "seconds": 900 },
        { "label": "30m", "seconds": 1800 },
        { "label": "1h", "seconds": 3600 }
    ]

    title: "dwm control center"
    visible: controlCenterModel.visible
    implicitWidth: 760
    implicitHeight: 620
    color: Theme.transparent

    function pageTitle() {
        if (controlCenterModel.page === "overview") {
            return "Control Center";
        }

        return controlCenterModel.page.charAt(0).toUpperCase() + controlCenterModel.page.slice(1);
    }

    function openPage(page) {
        if (page === "health") {
            controlCenterModel.openHealth();
        } else if (page === "actions") {
            controlCenterModel.openActions();
        } else if (page === "appearance") {
            controlCenterModel.openAppearance();
        } else if (page === "keybinds") {
            controlCenterModel.openKeybinds();
        } else if (page === "power") {
            controlCenterModel.openPower();
        } else if (page === "info") {
            controlCenterModel.openInfo();
        }
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

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                if (root.controlCenterModel.page === "overview") {
                    root.controlCenterModel.close();
                } else {
                    root.controlCenterModel.openOverview();
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.rowSpacing

                Text {
                    Layout.fillWidth: true
                    text: root.pageTitle()
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                ShellButton {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: Theme.buttonHeight
                    visible: root.controlCenterModel.page !== "overview"
                    label: "Back"
                    onActivated: root.controlCenterModel.openOverview()
                }

                ShellButton {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: Theme.buttonHeight
                    visible: root.controlCenterModel.page !== "overview"
                    label: "Refresh"
                    onActivated: root.controlCenterModel.refresh()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.controlCenterModel.message.length > 0
                text: root.controlCenterModel.message
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "overview"
                clip: true
                cellWidth: Math.max(220, width / 2)
                cellHeight: 74
                model: root.overviewPages

                delegate: ControlCenterActionButton {
                    required property var modelData

                    width: GridView.view.cellWidth - Theme.listSpacing
                    label: modelData.label
                    detail: modelData.detail
                    onActivated: root.openPage(modelData.id)
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "health"
                clip: true
                spacing: Theme.listSpacing
                model: root.controlCenterModel.healthRows

                delegate: ControlCenterRow {
                    required property var modelData

                    width: ListView.view.width
                    title: modelData.label
                    detail: modelData.detail
                    status: modelData.status
                }
            }

            GridView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "actions"
                clip: true
                cellWidth: Math.max(230, width / 2)
                cellHeight: 70
                model: root.actions

                delegate: ControlCenterActionButton {
                    required property var modelData

                    width: GridView.view.cellWidth - Theme.listSpacing
                    enabled: !root.controlCenterModel.busy
                    label: modelData.label
                    detail: modelData.detail
                    onActivated: root.controlCenterModel.runAction(modelData.id)
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "appearance"
                clip: true
                spacing: Theme.listSpacing
                model: root.controlCenterModel.themeRows

                delegate: ControlCenterRow {
                    id: appearanceThemeRow

                    required property var modelData

                    width: ListView.view.width
                    title: appearanceThemeRow.modelData.name
                    detail: appearanceThemeRow.modelData.status === "active" ? "Active theme" : "Click to apply"
                    status: appearanceThemeRow.modelData.status === "active" ? "ok" : ""

                    MouseArea {
                        anchors.fill: parent
                        enabled: appearanceThemeRow.modelData.status !== "active" && !root.controlCenterModel.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controlCenterModel.setTheme(appearanceThemeRow.modelData.name)
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "keybinds"
                clip: true
                spacing: Theme.listSpacing
                model: root.controlCenterModel.keybindRows

                delegate: ControlCenterRow {
                    required property var modelData

                    width: ListView.view.width
                    title: modelData.keys
                    detail: modelData.description
                    status: ""
                }
            }

            Flickable {
                id: powerFlick

                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "power"
                clip: true
                contentWidth: width
                contentHeight: powerColumn.implicitHeight

                ColumnLayout {
                    id: powerColumn

                    width: powerFlick.width
                    spacing: Theme.sectionSpacing

                    SectionLabel {
                        label: "Display"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        color: Theme.surface
                        border.color: root.controlCenterModel.powerDpmsEnabled ? Theme.accent : Theme.border
                        border.width: 1
                        radius: Theme.radius

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: Theme.rowSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.rowSpacing

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.tightSpacing

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Screen DPMS"
                                        color: Theme.textStrong
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.panelFontSize
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.controlCenterModel.powerDpmsEnabled ? "Display off after " + root.formatDuration(root.controlCenterModel.powerDpmsTimeout) : "Disabled"
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                        elide: Text.ElideRight
                                    }
                                }

                                ControlCenterOptionButton {
                                    Layout.preferredWidth: 96
                                    Layout.preferredHeight: 44
                                    label: root.controlCenterModel.powerDpmsEnabled ? "Disable" : "Enable"
                                    active: root.controlCenterModel.powerDpmsEnabled
                                    enabled: root.controlCenterModel.powerDpmsAvailable && !root.controlCenterModel.busy
                                    onActivated: root.controlCenterModel.setPowerDpms(!root.controlCenterModel.powerDpmsEnabled)
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.buttonHeight
                                spacing: Theme.listSpacing * 2

                                Repeater {
                                    model: root.powerPresets

                                    ControlCenterOptionButton {
                                        required property var modelData

                                        width: 74
                                        height: Theme.buttonHeight
                                        label: modelData.label
                                        active: root.controlCenterModel.powerDpmsEnabled && root.controlCenterModel.powerDpmsTimeout === modelData.seconds
                                        enabled: root.controlCenterModel.powerDpmsAvailable && !root.controlCenterModel.busy
                                        onActivated: root.controlCenterModel.setPowerDpmsTimeout(modelData.seconds)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !root.controlCenterModel.powerDpmsAvailable
                                text: "xset unavailable"
                                color: Theme.danger
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.smallFontSize
                                elide: Text.ElideRight
                            }
                        }
                    }

                    SectionLabel {
                        label: "Locking"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 150
                        color: Theme.surface
                        border.color: root.controlCenterModel.powerLockEnabled ? Theme.accent : Theme.border
                        border.width: 1
                        radius: Theme.radius

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: Theme.rowSpacing

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.rowSpacing

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.tightSpacing

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Auto Lock"
                                        color: Theme.textStrong
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.panelFontSize
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.controlCenterModel.powerLockEnabled ? "Lock after " + root.formatDuration(root.controlCenterModel.powerLockTimeout) : "Disabled"
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                        elide: Text.ElideRight
                                    }
                                }

                                ControlCenterOptionButton {
                                    Layout.preferredWidth: 96
                                    Layout.preferredHeight: 44
                                    label: root.controlCenterModel.powerLockEnabled ? "Disable" : "Enable"
                                    active: root.controlCenterModel.powerLockEnabled
                                    enabled: root.controlCenterModel.powerLockAvailable && !root.controlCenterModel.busy
                                    onActivated: root.controlCenterModel.setPowerLock(!root.controlCenterModel.powerLockEnabled)
                                }
                            }

                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.buttonHeight
                                spacing: Theme.listSpacing * 2

                                Repeater {
                                    model: root.powerPresets

                                    ControlCenterOptionButton {
                                        required property var modelData

                                        width: 74
                                        height: Theme.buttonHeight
                                        label: modelData.label
                                        active: root.controlCenterModel.powerLockEnabled && root.controlCenterModel.powerLockTimeout === modelData.seconds
                                        enabled: root.controlCenterModel.powerLockAvailable && !root.controlCenterModel.busy
                                        onActivated: root.controlCenterModel.setPowerLockTimeout(modelData.seconds)
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: !root.controlCenterModel.powerLockAvailable
                                text: "light-locker unavailable"
                                color: Theme.danger
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.smallFontSize
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.controlCenterModel.page === "info"
                clip: true
                spacing: Theme.listSpacing
                model: root.controlCenterModel.infoRows

                delegate: ControlCenterRow {
                    required property var modelData

                    width: ListView.view.width
                    title: modelData.label
                    detail: modelData.value
                    status: ""
                }
            }
        }
    }
}
