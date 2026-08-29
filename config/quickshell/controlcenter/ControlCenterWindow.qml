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
    required property var powerModel
    required property var settingsModel

    readonly property int cardWidth: Theme.controlCenterWidth
    readonly property int compactRowHeight: Math.max(28, Theme.fontBodySize + 12)
    readonly property int maximumHeight: panelWindow && panelWindow.screen
        ? Math.max(240, panelWindow.screen.height - Theme.panelHeight - Theme.popupMargin)
        : 240
    readonly property var powerPresets: root.powerModel.timeoutPresets

    function pageTitle() {
        if (controlCenterModel.page === "widgets") return "Bar Widgets";
        if (controlCenterModel.page === "actions") return "Quick Actions";
        if (controlCenterModel.page === "appearance") return "Appearance";
        if (controlCenterModel.page === "power") return "Power Settings";
        return "Control Center";
    }

    function pageMessage() {
        if (root.controlCenterModel.page === "power")
            return root.powerModel.messageFor("controlcenter");
        if (root.controlCenterModel.page === "widgets"
                && root.controlCenterModel.panelSettingsModel) {
            const panelModel = root.controlCenterModel.panelSettingsModel;
            if (panelModel.message.length > 0 && !panelModel.actionSucceeded)
                return panelModel.message;
            if (panelModel.providerState !== "available" && panelModel.providerState !== "defaults")
                return panelModel.providerDetail;
            if (panelModel.message.length > 0) return panelModel.message;
        }
        return root.controlCenterModel.message;
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
        const targetScreen = root.panelWindow ? root.panelWindow.screen : null;
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.launcherModel.openOnScreen(targetScreen);
        });
    }

    function openSessionPower() {
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.powerMenuModel.open("controlcenter");
        });
    }

    function openSystemHealth() {
        const targetScreen = root.panelWindow ? root.panelWindow.screen : null;
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.healthModel.openOnScreen(targetScreen);
        });
    }

    function openSettings() {
        const targetScreen = root.panelWindow ? root.panelWindow.screen : null;
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.settingsModel.openOnScreen(targetScreen);
        });
    }

    function openKeybinds() {
        const targetScreen = root.panelWindow ? root.panelWindow.screen : null;
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.controlCenterModel.openKeybindsOnScreen(targetScreen);
        });
    }

    function openSystemInfo() {
        const targetScreen = root.panelWindow ? root.panelWindow.screen : null;
        root.controlCenterModel.close();
        Qt.callLater(function() {
            root.controlCenterModel.openInfoOnScreen(targetScreen);
        });
    }

    visible: panelWindow !== null && panelWindow.screen !== null && controlCenterModel.visible
    targetWindow: panelWindow
    popupX: Theme.controlCenterX
    popupY: Theme.panelHeight
    popupWidth: cardWidth
    popupHeight: Math.min(controlCard.implicitHeight, maximumHeight)
    onDismissed: controlCenterModel.close()

    onVisibleChanged: {
        if (visible) {
            root.powerMenuModel.close("controlcenter");
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

        implicitHeight: Math.max(26, Theme.fontBodySize + 10)
        radius: Theme.smallRadius
        activeFocusOnTab: presetButton.enabled
        color: !presetButton.enabled ? Theme.controlDisabledFill
            : presetButton.activeFocus ? Theme.controlFocusFill
            : presetButton.active ? Theme.controlSelectedFill
            : presetMouse.containsMouse ? Theme.controlHoverFill : Theme.controlNormalFill
        border.color: !presetButton.enabled ? Theme.controlDisabledBorder
            : presetButton.activeFocus ? Theme.controlFocusBorder
            : presetButton.active ? Theme.controlSelectedBorder
            : presetMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
        border.width: presetButton.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth

        Keys.onPressed: function(event) {
            if (!presetButton.enabled || event.isAutoRepeat) return;
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                presetButton.activated();
                event.accepted = true;
            }
        }

        UiText {
            anchors.centerIn: parent
            text: presetButton.label
            color: !presetButton.enabled ? Theme.controlDisabledText
                : presetButton.activeFocus ? Theme.controlFocusText
                : presetButton.active ? Theme.controlSelectedText : Theme.controlNormalText
        }

        MouseArea {
            id: presetMouse

            anchors.fill: parent
            enabled: presetButton.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                presetButton.forceActiveFocus();
                presetButton.activated();
            }
        }
    }

    ShellSurface {
        id: controlCard

        anchors.fill: parent
        implicitHeight: menuColumn.implicitHeight + margin * 2
        margin: Theme.spacingLg
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
                spacing: Theme.compactSpacing

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
                    visible: root.pageMessage().length > 0
                    text: root.pageMessage()
                    color: Theme.textMuted
                    elide: Text.ElideRight
                }

                PanelSeparator {}

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.controlCenterModel.page === "overview"
                    spacing: Theme.compactSpacing

                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Applications"
                        onActivated: root.openApplications()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Power"
                        navigates: true
                        onActivated: root.openSessionPower()
                    }

                    PanelSeparator {
                        Layout.topMargin: Theme.compactSpacing
                        Layout.bottomMargin: Theme.compactSpacing
                    }

                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Bar Widgets"
                        navigates: true
                        onActivated: root.controlCenterModel.openWidgets()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Quick Actions"
                        navigates: true
                        onActivated: root.controlCenterModel.openActions()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Appearance"
                        navigates: true
                        onActivated: root.controlCenterModel.openAppearance()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Power Settings"
                        navigates: true
                        onActivated: root.controlCenterModel.openPower()
                    }

                    PanelSeparator {
                        Layout.topMargin: Theme.compactSpacing
                        Layout.bottomMargin: Theme.compactSpacing
                    }

                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Settings"
                        onActivated: root.openSettings()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "System Health"
                        onActivated: root.openSystemHealth()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Keybinds"
                        onActivated: root.openKeybinds()
                    }
                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
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
                            implicitHeight: root.compactRowHeight
                            label: modelData
                            detail: root.controlCenterModel.widgetEnabled(modelData) ? "On" : "Off"
                            active: root.controlCenterModel.widgetEnabled(modelData)
                            enabled: !root.controlCenterModel.panelSettingsModel
                                || (root.controlCenterModel.panelSettingsModel.mutationReady
                                    && !root.controlCenterModel.panelSettingsModel.busy)
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
                            implicitHeight: root.compactRowHeight
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
                            implicitHeight: root.compactRowHeight
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
                    spacing: Theme.spacingSm

                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Screen Timeout"
                        detail: root.powerModel.dpmsEnabled
                            ? root.formatDuration(root.powerModel.dpmsTimeout) : "Off"
                        active: root.powerModel.dpmsEnabled
                        enabled: root.powerModel.dpmsAvailable && !root.powerModel.busy
                        onActivated: root.powerModel.setDpms(!root.powerModel.dpmsEnabled, "controlcenter")
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: Theme.spacingSm
                        rowSpacing: Theme.spacingSm

                        Repeater {
                            model: root.powerPresets

                            delegate: PresetButton {
                                required property var modelData

                                Layout.fillWidth: true
                                label: modelData.label
                                active: root.powerModel.dpmsEnabled
                                    && root.powerModel.dpmsTimeout === modelData.seconds
                                enabled: root.powerModel.dpmsAvailable && !root.powerModel.busy
                                onActivated: root.powerModel.setDpmsTimeout(modelData.seconds, "controlcenter")
                            }
                        }
                    }

                    PanelSeparator {
                        Layout.topMargin: Theme.compactSpacing
                        Layout.bottomMargin: Theme.compactSpacing
                    }

                    MenuRow {
                        Layout.fillWidth: true
                        implicitHeight: root.compactRowHeight
                        label: "Auto Lock"
                        detail: root.powerModel.lockEnabled
                            ? root.formatDuration(root.powerModel.lockTimeout) : "Off"
                        active: root.powerModel.lockEnabled
                        enabled: root.powerModel.lockAvailable && !root.powerModel.busy
                        onActivated: root.powerModel.setLock(!root.powerModel.lockEnabled, "controlcenter")
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: Theme.spacingSm
                        rowSpacing: Theme.spacingSm

                        Repeater {
                            model: root.powerPresets

                            delegate: PresetButton {
                                required property var modelData

                                Layout.fillWidth: true
                                label: modelData.label
                                active: root.powerModel.lockEnabled
                                    && root.powerModel.lockTimeout === modelData.seconds
                                enabled: root.powerModel.lockAvailable && !root.powerModel.busy
                                onActivated: root.powerModel.setLockTimeout(modelData.seconds, "controlcenter")
                            }
                        }
                    }
                }
            }
        }
    }
}
