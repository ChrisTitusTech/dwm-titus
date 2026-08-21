//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.controlcenter
import qs.controls
import qs.health
import qs.launcher
import qs.network
import qs.notifications
import qs.panel
import qs.power
import qs.settings
import qs.state

pragma ComponentBehavior: Bound

ShellRoot {
    id: root

    property var selectedPanelWindow: null
    readonly property var defaultPanelWindow: panelVariants.instances.length > 0
        ? panelVariants.instances[0] : null
    readonly property var activePanelWindow: selectedPanelWindow && selectedPanelWindow.screen
        ? selectedPanelWindow : defaultPanelWindow
    readonly property var activePanelScreen: activePanelWindow && activePanelWindow.screen
        ? activePanelWindow.screen
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)

    function selectPanelPopup(panel, popupId) {
        if (!panel || !panel.screen) {
            return;
        }

        commandMenuModel.close();
        if (popupId !== "bluetooth") bluetoothModel.close();
        if (popupId !== "controlcenter") controlCenterModel.close();
        if (popupId !== "controls") controlsModel.close();
        if (popupId !== "network") networkModel.close();
        if (popupId !== "power") powerMenuModel.close();
        root.selectedPanelWindow = panel;
    }

    function openCommandMenu(screen) {
        networkModel.close();
        bluetoothModel.close();
        controlCenterModel.close();
        controlsModel.close();
        powerMenuModel.close();
        launcherModel.close();
        if (screen) commandMenuModel.openOnScreen(screen); else commandMenuModel.open();
    }

    function toggleCommandMenu(screen) {
        if (commandMenuModel.visible) {
            commandMenuModel.close();
        } else {
            root.openCommandMenu(screen);
        }
    }

    function panelForScreen(screen) {
        if (screen) {
            for (const panel of panelVariants.instances) {
                if (panel.screen === screen || (panel.screen && panel.screen.name === screen.name)) {
                    return panel;
                }
            }
        }

        return root.activePanelWindow;
    }

    function runCommandMenuAction(target, action, argument, requestedScreen) {
        const panel = root.panelForScreen(requestedScreen);
        const screen = requestedScreen || (panel ? panel.screen : root.activePanelScreen);

        if (target === "settings" && (action === "open" || action === "select")) {
            settingsModel.openOnScreen(screen);
            if (action === "select") settingsModel.selectSection(argument);
        } else if (target === "network" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "network");
            networkModel.open();
        } else if (target === "bluetooth" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "bluetooth");
            bluetoothModel.open();
        } else if (target === "controls" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "controls");
            controlsModel.open();
        } else if (target === "systemhealth" && action === "open") {
            systemHealthModel.openOnScreen(screen);
        } else if (target === "controlcenter" && action === "keybindings") {
            controlCenterModel.openKeybindsOnScreen(screen);
        } else if (target === "power" && action === "open") {
            if (panel) root.selectPanelPopup(panel, "power");
            powerMenuModel.open("panel");
        }
    }

    DwmState {
        id: dwmState
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    LauncherModel {
        id: launcherModel

        onVisibleChanged: {
            if (visible) commandMenuModel.close();
        }
    }

    CommandMenuModel {
        id: commandMenuModel
        launcherModel: launcherModel
        currentEntryIds: {
            const ids = [];

            if (settingsModel.visible) {
                ids.push("settings");
                if (settingsModel.selectedSectionId === "displays" || settingsModel.selectedSectionId === "input") {
                    ids.push(settingsModel.selectedSectionId);
                    ids.push("display-input");
                } else if (settingsModel.selectedSectionId === "power") {
                    ids.push("system");
                    ids.push("power-settings");
                } else if (settingsModel.selectedSectionId === "system") {
                    ids.push("system");
                    ids.push("system-settings");
                }
            }
            if (networkModel.visible) ids.push("network");
            if (bluetoothModel.visible) ids.push("bluetooth");
            if (controlsModel.visible) ids.push("audio");
            if (systemHealthModel.visible) ids.push("health");
            if (controlCenterModel.utilityVisible && controlCenterModel.utilityPage === "keybinds") ids.push("keybindings");
            if (powerMenuModel.visible) {
                ids.push("system");
                ids.push("power-menu");
            }

            return ids;
        }
        onIpcActionRequested: (target, action, argument, screen) => root.runCommandMenuAction(target, action, argument, screen)
    }

    PowerMenuModel {
        id: powerMenuModel
    }

    NetworkModel {
        id: networkModel
    }

    ControlsModel {
        id: controlsModel
    }

    BluetoothModel {
        id: bluetoothModel
    }

    ControlCenterModel {
        id: controlCenterModel
    }

    SystemHealthModel {
        id: systemHealthModel
    }

    SettingsModel {
        id: settingsModel
        networkModel: networkModel
        bluetoothModel: bluetoothModel
        controlsModel: controlsModel
    }

    LazyLoader {
        active: true

        component: Item {
            Component.onCompleted: {
                networkModel.refresh();
                bluetoothModel.refresh();
                controlsModel.refresh();
            }
        }
    }

    NotificationModel {
        id: notificationModel
    }

    IpcHandler {
        target: "launcher"

        function applicationConsumers(): int {
            return launcherModel.applicationConsumers;
        }

        function close(): void {
            launcherModel.close();
        }

        function indexCount(): int {
            return launcherModel.apps.length;
        }

        function open(): void {
            launcherModel.open();
        }

        function toggle(): void {
            launcherModel.toggle();
        }
    }

    IpcHandler {
        target: "menu"

        function activeMenu(): string {
            return commandMenuModel.activeMenu;
        }

        function close(): void {
            commandMenuModel.close();
        }

        function open(): void {
            root.openCommandMenu(null);
        }

        function resultCount(): int {
            return commandMenuModel.rows.length;
        }

        function selectedLabel(): string {
            return commandMenuModel.selectedLabel;
        }

        function summon(): void {
            root.openCommandMenu(dwmState.focusedScreen());
        }

        function toggle(): void {
            root.toggleCommandMenu(null);
        }
    }

    IpcHandler {
        target: "power"

        function close(): void {
            powerMenuModel.close();
        }

        function open(): void {
            powerMenuModel.open();
        }

        function toggle(): void {
            powerMenuModel.toggle();
        }
    }

    IpcHandler {
        target: "network"

        function close(): void {
            networkModel.close();
        }

        function open(): void {
            networkModel.open();
        }

        function refresh(): void {
            networkModel.refresh();
        }

        function status(): string {
            return networkModel.statusText;
        }

        function toggle(): void {
            networkModel.toggle();
        }
    }

    IpcHandler {
        target: "controls"

        function close(): void {
            controlsModel.close();
        }

        function bluetoothStatus(): string {
            return controlsModel.bluetoothText;
        }

        function open(): void {
            controlsModel.open();
        }

        function refresh(): void {
            controlsModel.refresh();
        }

        function micStatus(): string {
            return controlsModel.micText;
        }

        function mediaStatus(): string {
            return controlsModel.mediaText;
        }

        function mediaNext(): void {
            controlsModel.mediaNext();
        }

        function mediaPlayPause(): void {
            controlsModel.mediaPlayPause();
        }

        function mediaPrevious(): void {
            controlsModel.mediaPrevious();
        }

        function toggle(): void {
            controlsModel.toggle();
        }

        function volumeDown(): void {
            controlsModel.volumeDown();
        }

        function volumeStatus(): string {
            return controlsModel.volumeDisplayText;
        }

        function volumeSet(percent: int): void {
            controlsModel.volumeSet(percent);
        }

        function volumeToggleMute(): void {
            controlsModel.volumeToggleMute();
        }

        function volumeUp(): void {
            controlsModel.volumeUp();
        }
    }

    IpcHandler {
        target: "notifications"

        function clear(): void {
            notificationModel.clear();
        }

        function count(): int {
            return notificationModel.notifications.length;
        }

        function clearHistory(): void {
            notificationModel.clearHistory();
        }

        function closeHistory(): void {
            notificationModel.closeHistory();
        }

        function historyCount(): int {
            return notificationModel.history.length;
        }

        function historyLatestSummary(): string {
            return notificationModel.historyLatestSummary();
        }

        function openHistory(): void {
            notificationModel.openHistory();
        }

        function toggleHistory(): void {
            notificationModel.toggleHistory();
        }
    }

    IpcHandler {
        target: "controlcenter"

        function close(): void {
            controlCenterModel.close();
        }

        function open(): void {
            controlCenterModel.open();
        }

        function openKeybinds(): void {
            controlCenterModel.openKeybinds();
        }

        function refresh(): void {
            controlCenterModel.refresh();
        }

        function toggle(): void {
            controlCenterModel.toggle();
        }
    }

    IpcHandler {
        target: "systemhealth"

        function close(): void {
            systemHealthModel.close();
        }

        function open(): void {
            systemHealthModel.openOnScreen(root.activePanelScreen);
        }

        function refresh(): void {
            systemHealthModel.refresh();
        }

        function toggle(): void {
            if (systemHealthModel.visible) {
                systemHealthModel.close();
            } else {
                systemHealthModel.openOnScreen(root.activePanelScreen);
            }
        }
    }

    IpcHandler {
        target: "settings"

        function close(): void {
            settingsModel.close();
        }

        function currentSection(): string {
            return settingsModel.selectedSectionId;
        }

        function displayCount(): int {
            return settingsModel.displayOutputs.length;
        }

        function displayStatus(): string {
            return settingsModel.displayState;
        }

        function inputCount(): int {
            return settingsModel.inputDevices.length;
        }

        function inputStatus(): string {
            return settingsModel.inputState;
        }

        function networkProviderStatus(): string {
            return networkModel.providerState;
        }

        function networkDeviceCount(): int {
            return networkModel.devices.length;
        }

        function bluetoothProviderStatus(): string {
            return bluetoothModel.providerState;
        }

        function bluetoothDeviceCount(): int {
            return bluetoothModel.devices.length;
        }

        function audioProviderStatus(): string {
            return controlsModel.audioProviderState;
        }

        function audioSourceKind(): string {
            return controlsModel.audioSourceKind;
        }

        function audioOutputCount(): int {
            return controlsModel.outputDevices.length;
        }

        function audioInputCount(): int {
            return controlsModel.inputDevices.length;
        }

        function audioStreamCount(): int {
            return controlsModel.audioStreams.length;
        }

        function open(): void {
            settingsModel.open();
        }

        function refresh(): void {
            settingsModel.refresh();
        }

        function select(section: string): void {
            settingsModel.selectSection(section);
        }

        function status(): string {
            return settingsModel.discoveryState;
        }

        function toggle(): void {
            settingsModel.toggle();
        }
    }

    IpcHandler {
        target: "tray"

        function count(): int {
            return SystemTray.items.values.length;
        }

        function ids(): string {
            const items = SystemTray.items.values;
            const ids = [];

            for (let i = 0; i < items.length; i++) {
                ids.push(items[i].id || items[i].title || items[i].tooltipTitle || "unknown");
            }

            return ids.join("\n");
        }

        function details(): string {
            const items = SystemTray.items.values;
            const rows = [];

            for (let i = 0; i < items.length; i++) {
                const item = items[i];
                rows.push([
                    item.id || "unknown",
                    item.title || "",
                    item.icon || "",
                    item.hasMenu ? "menu" : "no-menu",
                    item.status === undefined || item.status === null ? "" : item.status
                ].join("\t"));
            }

            return rows.join("\n");
        }
    }

    IpcHandler {
        target: "bar"

        function height(): int {
            return root.defaultPanelWindow ? root.defaultPanelWindow.implicitHeight : 0;
        }

        function layout(): string {
            return root.defaultPanelWindow ? root.defaultPanelWindow.layoutSignature() : "";
        }

        function iconSizes(): string {
            return root.defaultPanelWindow ? root.defaultPanelWindow.systemIconSizes() : "";
        }

        function workspaceCount(): int {
            if (!root.defaultPanelWindow) return 0;
            return dwmState.barWorkspaceIndexes(
                root.defaultPanelWindow.screen,
                root.defaultPanelWindow.primaryPanel).length;
        }

        function networkIconState(): string {
            return networkModel.barIconState;
        }

        function volumeIconState(): string {
            return controlsModel.volumeIconState;
        }
    }

    LauncherWindow {
        launcherModel: launcherModel
    }

    CommandMenuWindow {
        commandMenuModel: commandMenuModel
    }

    PowerMenuWindow {
        powerMenuModel: powerMenuModel
        panelWindow: root.activePanelWindow
    }

    Variants {
        id: panelVariants

        model: Quickshell.screens

        DwmPanel {
            required property var modelData

            screen: modelData
            state: dwmState
            clock: clock
            networkModel: networkModel
            controlsModel: controlsModel
            bluetoothModel: bluetoothModel
            controlCenterModel: controlCenterModel
            powerMenuModel: powerMenuModel
            primaryPanel: modelData === Quickshell.screens[0]
            onPopupRequested: (panel, popupId) => root.selectPanelPopup(panel, popupId)
        }
    }

    NetworkWindow {
        networkModel: networkModel
        panelWindow: root.activePanelWindow
    }

    NotificationPopupWindow {
        notificationModel: notificationModel
        panelWindow: root.defaultPanelWindow
    }

    NotificationHistoryWindow {
        notificationModel: notificationModel
    }

    ControlsWindow {
        controlsModel: controlsModel
        panelWindow: root.activePanelWindow
    }

    BluetoothWindow {
        bluetoothModel: bluetoothModel
        panelWindow: root.activePanelWindow
    }

    ControlCenterWindow {
        controlCenterModel: controlCenterModel
        launcherModel: launcherModel
        panelWindow: root.activePanelWindow
        powerMenuModel: powerMenuModel
        healthModel: systemHealthModel
        settingsModel: settingsModel
    }

    UtilityDetailWindow {
        controlCenterModel: controlCenterModel
    }

    SystemHealthWindow {
        healthModel: systemHealthModel
        screen: systemHealthModel.targetScreen ? systemHealthModel.targetScreen : root.activePanelScreen
    }

    SettingsWindow {
        settingsModel: settingsModel
        networkModel: networkModel
        bluetoothModel: bluetoothModel
        controlsModel: controlsModel
    }
}
