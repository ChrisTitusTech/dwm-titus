import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var controlCenterModel
    required property var healthModel
    required property var launcherModel
    required property var panelWindow
    required property var powerMenuModel
    required property var settingsModel

    readonly property int cardWidth: Theme.controlCenterWidth
    readonly property int maximumHeight: Math.max(240, panelWindow.screen.height - Theme.panelHeight - Theme.popupMargin)
    readonly property var powerPresets: [
        { "label": "5m", "seconds": 300 },
        { "label": "10m", "seconds": 600 },
        { "label": "15m", "seconds": 900 },
        { "label": "30m", "seconds": 1800 },
        { "label": "1h", "seconds": 3600 }
    ]

    function pageTitle() {
        if (controlCenterModel.page === "widgets") return "Bar Widgets";
        if (controlCenterModel.page === "actions") return "Quick Actions";
        if (controlCenterModel.page === "appearance") return "Appearance";
        if (controlCenterModel.page === "power") return "Power Settings";
        return "Control Center";
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

    function openApplications() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.launcherModel.open();
        });
    }

    function openSessionPower() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.powerMenuModel.open("controlcenter");
        });
    }

    function openSystemHealth() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.healthModel.openOnScreen(root.panelWindow.screen);
        });
    }

    function openSettings() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.settingsModel.open();
        });
    }

    function openKeybinds() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.controlCenterModel.openKeybinds();
        });
    }

    function openSystemInfo() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.controlCenterModel.openInfo();
        });
    }

    visible: controlCenterModel.visible
    targetWindow: panelWindow
    popupX: Theme.controlCenterX
    popupY: Theme.panelHeight
    popupWidth: cardWidth
    popupHeight: Math.min(controlCard.implicitHeight, maximumHeight)
    onDismissed: controlCenterModel.close()

    onVisibleChanged: {
        if (visible) {
            root.powerMenuModel.close();
            Qt.callLater(function() {
                controlCard.forceActiveFocus();
            });
        } else {
            root.controlCenterModel.close();
        }
    }

    Connections {
        target: root.controlCenterModel

        function onPageChanged() {
            menuFlick.contentY = 0;
            Qt.callLater(function() {
                controlCard.forceActiveFocus();
            });
        }
    }

    component PresetButton: Rectangle {
        id: presetButton

        property string label: ""
        property bool active: false
        signal activated()

        implicitHeight: 28
        radius: Theme.smallRadius
        color: active ? Theme.surfaceActive : presetMouse.containsMouse ? Theme.surfaceHover : Theme.surface
        border.color: active ? Theme.accentSecondary : presetMouse.containsMouse ? Theme.borderStrong : Theme.border
        border.width: Theme.pillBorderWidth

        UiText {
            anchors.centerIn: parent
            text: presetButton.label
            color: presetButton.active ? Theme.accentSecondary : Theme.text
        }

        MouseArea {
            id: presetMouse

            anchors.fill: parent
            enabled: presetButton.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: presetButton.activated()
        }
    }

    ShellSurface {
        id: controlCard

        anchors.fill: parent
        implicitHeight: menuColumn.implicitHeight + margin * 2
        margin: 10
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.controlCenterModel.close();
                event.accepted = true;
            }
        }

        Flickable {
            id: menuFlick

            anchors.fill: parent
            contentWidth: width
            contentHeight: menuColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            ColumnLayout {
                id: menuColumn

                width: menuFlick.width
                spacing: 4

                MenuHeader {
                    Layout.fillWidth: true
                    title: root.pageTitle()
                    showBack: root.controlCenterModel.page !== "overview"
                    titleLetterSpacing: root.controlCenterModel.page === "overview" ? 2 : 1
                    onBackRequested: root.controlCenterModel.openOverview()
                    onCloseRequested: root.controlCenterModel.close()
                }

                UiText {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.message.length > 0
                    text: root.controlCenterModel.message
                    color: Theme.textMuted
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Theme.border
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.page === "overview"
                    spacing: 2

                    SectionLabel { label: "Launch" }

                    MenuRow {
                        Layout.fillWidth: true
                        label: "Applications"
                        onActivated: root.openApplications()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Power"
                        navigates: true
                        onActivated: root.openSessionPower()
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        color: Theme.border
                    }

                    SectionLabel { label: "Desktop" }

                    MenuRow {
                        Layout.fillWidth: true
                        label: "Bar Widgets"
                        navigates: true
                        onActivated: root.controlCenterModel.openWidgets()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Quick Actions"
                        navigates: true
                        onActivated: root.controlCenterModel.openActions()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Appearance"
                        navigates: true
                        onActivated: root.controlCenterModel.openAppearance()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Power Settings"
                        navigates: true
                        onActivated: root.controlCenterModel.openPower()
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        color: Theme.border
                    }

                    SectionLabel { label: "Utilities" }

                    MenuRow {
                        Layout.fillWidth: true
                        label: "Settings"
                        onActivated: root.openSettings()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "System Health"
                        onActivated: root.openSystemHealth()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Keybinds"
                        onActivated: root.openKeybinds()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "System Info"
                        onActivated: root.openSystemInfo()
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.page === "widgets"
                    spacing: 2

                    Repeater {
                        model: ["Volume", "Bluetooth", "Network", "Power", "Workspaces"]

                        delegate: MenuRow {
                            required property string modelData

                            Layout.fillWidth: true
                            label: modelData
                            detail: root.controlCenterModel.widgetEnabled(modelData) ? "On" : "Off"
                            active: root.controlCenterModel.widgetEnabled(modelData)
                            onActivated: root.controlCenterModel.toggleWidget(modelData)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.page === "actions"
                    spacing: 2

                    Repeater {
                        model: root.controlCenterModel.actions

                        delegate: MenuRow {
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
                    visible: root.controlCenterModel.page === "appearance"
                    spacing: 2

                    Repeater {
                        model: root.controlCenterModel.themeRows

                        delegate: MenuRow {
                            required property var modelData

                            Layout.fillWidth: true
                            label: modelData.name
                            detail: modelData.status === "active" ? "Active" : ""
                            active: modelData.status === "active"
                            enabled: !root.controlCenterModel.busy
                            onActivated: root.controlCenterModel.setTheme(modelData.name)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.page === "power"
                    spacing: 6

                    UiText {
                        Layout.fillWidth: true
                        text: root.controlCenterModel.powerDpmsEnabled
                            ? "Screen off after " + root.formatDuration(root.controlCenterModel.powerDpmsTimeout)
                            : "Screen timeout disabled"
                        color: Theme.textMuted
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Screen Timeout"
                        detail: root.controlCenterModel.powerDpmsEnabled ? "On" : "Off"
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

                            delegate: PresetButton {
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

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.topMargin: 3
                        Layout.bottomMargin: 3
                        color: Theme.border
                    }

                    UiText {
                        Layout.fillWidth: true
                        text: root.controlCenterModel.powerLockEnabled
                            ? "Lock after " + root.formatDuration(root.controlCenterModel.powerLockTimeout)
                            : "Auto lock disabled"
                        color: Theme.textMuted
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        label: "Auto Lock"
                        detail: root.controlCenterModel.powerLockEnabled ? "On" : "Off"
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

                            delegate: PresetButton {
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
