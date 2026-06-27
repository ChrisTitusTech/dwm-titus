import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

FloatingWindow {
    id: root

    required property var controlCenterModel

    readonly property var overviewPages: [
        { "id": "health", "label": "System Health", "detail": "Check required commands, config paths, and desktop tools" },
        { "id": "actions", "label": "Quick Actions", "detail": "Restart desktop services and open common tools" },
        { "id": "appearance", "label": "Appearance", "detail": "Switch active dwm-titus themes" },
        { "id": "keybinds", "label": "Keybinds", "detail": "Browse live hotkeys from hotkeys.toml" },
        { "id": "info", "label": "System Info", "detail": "View session and host details" }
    ]
    readonly property var actions: [
        { "id": "restart-picom", "label": "Restart Picom", "detail": "Restart the compositor" },
        { "id": "reload-wallpaper", "label": "Reload Wallpaper", "detail": "Randomize the wallpaper folder" },
        { "id": "toggle-compositor", "label": "Toggle Compositor", "detail": "Start or stop picom" },
        { "id": "restart-networkmanager", "label": "Restart NetworkManager", "detail": "Open a terminal for the privileged restart" },
        { "id": "dependency-check", "label": "Dependency Check", "detail": "Run check-deps.sh in a terminal" },
        { "id": "install-missing-deps", "label": "Install Missing Deps", "detail": "Run the installer in a terminal" },
        { "id": "open-wallpapers", "label": "Wallpaper Folder", "detail": "Open the wallpaper directory" },
        { "id": "gtk-settings", "label": "GTK Settings", "detail": "Open nwg-look when installed" }
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
        } else if (page === "info") {
            controlCenterModel.openInfo();
        }
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
                    required property var modelData

                    width: ListView.view.width
                    title: modelData.name
                    detail: modelData.status === "active" ? "Active theme" : "Click to apply"
                    status: modelData.status === "active" ? "ok" : ""

                    MouseArea {
                        anchors.fill: parent
                        enabled: modelData.status !== "active" && !root.controlCenterModel.busy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controlCenterModel.setTheme(modelData.name)
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
