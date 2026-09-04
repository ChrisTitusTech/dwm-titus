//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import qs.accessibility
import qs.appearance
import qs.controlcenter
import qs.controls
import qs.defaults
import qs.health
import qs.launcher
import qs.network
import qs.notifications
import qs.panel
import qs.power
import qs.settings
import qs.state
import qs.systemmanagement

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
        if (popupId !== "power") powerMenuModel.close("panel");
        root.selectedPanelWindow = panel;
    }

    function openCommandMenu(screen) {
        networkModel.close();
        bluetoothModel.close();
        controlCenterModel.close();
        controlsModel.close();
        powerMenuModel.close("panel");
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
        powerModel: powerModel
    }

    PowerModel {
        id: powerModel
    }

    DefaultAppsModel {
        id: defaultsModel
    }

    AutostartModel {
        id: autostartModel
    }

    AppearanceModel {
        id: appearanceModel
    }

    AccessibilityModel {
        id: accessibilityModel
    }

    PanelSettingsModel {
        id: panelSettingsModel
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
        powerModel: powerModel
        panelSettingsModel: panelSettingsModel
    }

    SystemHealthModel {
        id: systemHealthModel
    }

    SystemManagementModel {
        id: systemManagementModel
    }

    SettingsModel {
        id: settingsModel
        networkModel: networkModel
        bluetoothModel: bluetoothModel
        controlsModel: controlsModel
        powerModel: powerModel
        powerMenuModel: powerMenuModel
        defaultsModel: defaultsModel
        autostartModel: autostartModel
        appearanceModel: appearanceModel
        accessibilityModel: accessibilityModel
        panelSettingsModel: panelSettingsModel
        systemManagementModel: systemManagementModel
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
            powerMenuModel.close("panel");
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

        function doNotDisturb(): bool {
            return notificationModel.doNotDisturb;
        }

        function popupTimeout(): int {
            return notificationModel.popupTimeoutMs;
        }

        function policyState(): string {
            return notificationModel.policyState;
        }

        function policyStatus(): string {
            return notificationModel.policyStatus();
        }

        function resetPolicy(): void {
            notificationModel.resetPolicy();
        }

        function setDoNotDisturb(enabled: bool): void {
            notificationModel.setDoNotDisturb(enabled);
        }

        function setPopupTimeout(timeoutMs: int): void {
            notificationModel.setPopupTimeout(timeoutMs);
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

        function systemManagementProviderStatus(): string {
            return systemManagementModel.providerState;
        }

        function systemManagementUpdateCount(): int {
            return systemManagementModel.updates.length;
        }

        function systemManagementSnapshotState(): string {
            return systemManagementModel.snapshotState;
        }

        function inputAccessibilityValue(settingId: string): string {
            const setting = settingsModel.inputSettings.find(function(item) {
                return item.device === "accessx" && item.id === settingId;
            });
            return setting ? setting.value : "";
        }

        function inputAccessibilityPreview(settingId: string, enabled: bool): void {
            settingsModel.previewInput("accessx", settingId, enabled ? "1" : "0");
        }

        function inputPreviewState(): string {
            return settingsModel.previewKind;
        }

        function inputPreviewAction(action: string): void {
            if (settingsModel.previewKind !== "input") return;
            if (action === "keep") settingsModel.keepPreview();
            else if (action === "revert") settingsModel.revertPreview();
        }

        function inputAccessibilityReset(settingId: string): void {
            if (settingsModel.previewOperationLocked) return;
            settingsModel.resetInput("accessx", settingId);
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

        function powerProviderStatus(): string {
            return powerModel.providerState;
        }

        function powerBatteryAvailable(): bool {
            return powerModel.batteryAvailable;
        }

        function powerBatteryPercent(): int {
            return powerModel.batteryPercent;
        }

        function powerActiveProfile(): string {
            return powerModel.activeProfile;
        }

        function powerDpmsStatus(): string {
            return powerModel.dpmsState;
        }

        function powerDpmsEnabled(): bool {
            return powerModel.dpmsEnabled;
        }

        function powerDpmsTimeout(): int {
            return powerModel.dpmsTimeout;
        }

        function powerLockStatus(): string {
            return powerModel.lockState;
        }

        function powerLockEnabled(): bool {
            return powerModel.lockEnabled;
        }

        function powerLockTimeout(): int {
            return powerModel.lockTimeout;
        }

        function powerBusy(): bool {
            return powerModel.busy;
        }

        function powerMessage(): string {
            return powerModel.messageFor("settings");
        }

        function powerSetDpms(enabled: bool): void {
            powerModel.setDpms(enabled, "settings");
        }

        function defaultsProviderStatus(): string {
            return defaultsModel.providerState;
        }

        function defaultsRoleCount(): int {
            return defaultsModel.roles.length;
        }

        function defaultsMessage(): string {
            return defaultsModel.messageFor("settings");
        }

        function defaultsBusy(): bool {
            return defaultsModel.busy;
        }

        function defaultsRoleDesktopId(role: string): string {
            const match = defaultsModel.roles.find(function(item) { return item.id === role; });
            return match ? match.desktopId : "";
        }

        function defaultsSetRole(role: string, desktopId: string): void {
            defaultsModel.setRole(role, desktopId, "settings");
        }

        function defaultsResetRole(role: string): void {
            defaultsModel.resetRole(role, "settings");
        }

        function autostartProviderStatus(): string {
            return autostartModel.providerState;
        }

        function autostartEntryCount(): int {
            return autostartModel.entries.length;
        }

        function autostartMessage(): string {
            return autostartModel.messageFor("settings");
        }

        function autostartBusy(): bool {
            return autostartModel.busy;
        }

        function autostartEntryState(desktopId: string): string {
            const entry = autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.state : "";
        }

        function autostartEntryName(desktopId: string): string {
            const entry = autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.name : "";
        }

        function autostartEntryOrigin(desktopId: string): string {
            const entry = autostartModel.entries.find(function(item) { return item.id === desktopId; });
            return entry ? entry.origin : "";
        }

        function appearanceProviderStatus(): string {
            return appearanceModel.providerState;
        }

        function appearanceProviderDetail(): string {
            return appearanceModel.providerDetail;
        }

        function appearanceApplicationState(): string {
            return appearanceModel.applicationState;
        }

        function appearanceInventoryState(capability: string): string {
            return appearanceModel.inventorySelection(capability).state;
        }

        function appearanceInventoryProviderState(): string {
            return appearanceModel.inventoryProviderState;
        }

        function appearanceInventoryWatchState(): string {
            return appearanceModel.inventoryWatchState;
        }

        function appearanceInventoryCandidateState(capability: string, token: string): string {
            const match = appearanceModel.inventoryCandidates.find(function(item) {
                return item.id === capability && item.token === token;
            });
            return match ? match.state : "";
        }

        function appearanceIntegrationState(integrationId: string): string {
            const match = appearanceModel.integrations.find(function(item) { return item.id === integrationId; });
            return match ? match.state : "";
        }

        function appearanceIntegrationDetail(integrationId: string): string {
            const match = appearanceModel.integrations.find(function(item) { return item.id === integrationId; });
            return match ? match.detail : "";
        }

        function appearanceErrorCode(scope: string): string {
            const match = appearanceModel.errors.find(function(item) { return item.scope === scope; });
            return match ? match.code : "";
        }

        function appearanceActiveTheme(): string {
            return appearanceModel.activeTheme;
        }

        function appearanceThemeCount(): int {
            return appearanceModel.themes.length;
        }

        function appearanceMutationReady(): bool {
            return appearanceModel.mutationReady;
        }

        function appearancePreviewState(): string {
            return appearanceModel.previewState;
        }

        function appearancePreviewRemaining(): int {
            return appearanceModel.previewRemaining;
        }

        function appearanceWallpaperState(): string {
            return appearanceModel.wallpaperState;
        }

        function appearanceWallpaperProviderState(): string {
            return appearanceModel.wallpaperProviderState;
        }

        function appearanceWallpaperProviderDetail(): string {
            return appearanceModel.wallpaperProviderDetail;
        }

        function appearanceWallpaperDetail(): string {
            return appearanceModel.wallpaperDetail;
        }

        function appearanceWallpaperPath(): string {
            return appearanceModel.wallpaperPath;
        }

        function appearanceWallpaperFit(): string {
            return appearanceModel.wallpaperFit;
        }

        function appearanceWallpaperMutationDetail(): string {
            return appearanceModel.wallpaperMutationDetail;
        }

        function appearanceWallpaperMutationState(): string {
            return appearanceModel.wallpaperMutationState;
        }

        function appearanceWallpaperResetReady(): bool {
            return appearanceModel.wallpaperResetReady;
        }

        function appearanceWallpaperResetState(): string {
            return appearanceModel.wallpaperResetState;
        }

        function appearanceWallpaperResetDetail(): string {
            return appearanceModel.wallpaperResetDetail;
        }

        function appearanceWallpaperPreviewState(): string {
            return appearanceModel.wallpaperPreviewState;
        }

        function appearanceWallpaperPreviewRemaining(): int {
            return appearanceModel.wallpaperPreviewRemaining;
        }

        function appearanceWallpaperStatusBusy(): bool {
            return appearanceModel.wallpaperStatusBusy;
        }

        function appearanceWallpaperReconcile(): void {
            appearanceModel.reconcileWallpaperPreview();
        }

        function appearanceFontState(): string {
            return appearanceModel.fontState;
        }

        function appearanceFontFamily(): string {
            return appearanceModel.fontFamily;
        }

        function appearanceFontScale(): string {
            return appearanceModel.fontScale.toFixed(2);
        }

        function appearanceFontMutationReady(): bool {
            return appearanceModel.fontMutationReady;
        }

        function appearanceFontPreviewState(): string {
            return appearanceModel.fontPreviewState;
        }

        function appearanceFontPreviewRemaining(): int {
            return appearanceModel.fontPreviewRemaining;
        }

        function appearancePersonalizationStatus(): string {
            return appearanceModel.personalizationProviderState;
        }

        function appearancePersonalizationStatusBusy(): bool {
            return appearanceModel.personalizationStatusBusy;
        }

        function appearanceRefresh(): void {
            appearanceModel.refreshAll(true);
        }

        function capabilityStatus(capabilityId: string): string {
            return settingsModel.capabilityById(capabilityId).status;
        }

        function accessibilityState(): string {
            return accessibilityModel.providerState;
        }

        function accessibilityMutationReady(): bool {
            return accessibilityModel.mutationReady;
        }

        function accessibilityBusy(): bool {
            return accessibilityModel.busy;
        }

        function accessibilityHighContrast(): bool {
            return accessibilityModel.highContrast;
        }

        function accessibilityReducedMotion(): bool {
            return accessibilityModel.reducedMotion;
        }

        function accessibilitySetContrast(enabled: bool): void {
            accessibilityModel.setSetting("contrast", enabled ? "high" : "standard");
        }

        function accessibilitySetReducedMotion(enabled: bool): void {
            accessibilityModel.setSetting("motion", enabled ? "reduced" : "full");
        }

        function accessibilityReset(): void {
            accessibilityModel.reset();
        }

        function appearancePersonalizationMutationState(): string {
            return appearanceModel.personalizationMutationState;
        }

        function appearancePersonalizationValue(capability: string): string {
            return appearanceModel.personalizationSelection(capability).value;
        }

        function appearancePersonalizationOption(capability: string): string {
            return appearanceModel.personalizationSelection(capability).option;
        }

        function appearancePersonalizationEffectiveState(capability: string): string {
            return appearanceModel.personalizationEffectiveState(capability);
        }

        function appearancePersonalizationApplyState(capability: string): string {
            return appearanceModel.personalizationReadiness(capability).apply;
        }

        function appearancePersonalizationResetState(capability: string): string {
            return appearanceModel.personalizationReadiness(capability).reset;
        }

        function appearancePersonalizationDelegateState(capability: string): string {
            const match = appearanceModel.personalizationDelegates[capability];
            return match ? match.state : "";
        }

        function appearanceMessage(): string {
            return appearanceModel.message;
        }

        function appearanceRecoveryState(): string {
            return appearanceModel.recoveryState;
        }

        function panelSettingsState(): string {
            return panelSettingsModel.providerState;
        }

        function panelWidgetEnabled(widget: string): bool {
            return panelSettingsModel.widgetEnabled(widget);
        }

        function panelWidgetSet(widget: string, enabled: bool): void {
            panelSettingsModel.setWidget(widget, enabled);
        }

        function panelWidgetsReset(): void {
            panelSettingsModel.reset();
        }

        function autostartConfirming(): bool {
            return autostartModel.confirming;
        }

        function autostartConfirm(): void {
            autostartModel.confirmAction("settings");
        }

        function autostartCancel(): void {
            autostartModel.cancelConfirmation("settings");
        }

        function autostartSetSearch(query: string): void {
            autostartModel.setSearch(query);
        }

        function autostartFilteredCount(): int {
            return autostartModel.filteredEntries.length;
        }

        function autostartSet(desktopId: string, enabled: bool): void {
            const entry = autostartModel.entries.find(function(item) { return item.id === desktopId; });
            if (entry) autostartModel.requestSet(entry, enabled ? "enabled" : "disabled", "settings");
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
            panelSettingsModel: panelSettingsModel
            powerModel: powerModel
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
        powerModel: powerModel
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
        powerModel: powerModel
        powerMenuModel: powerMenuModel
        defaultsModel: defaultsModel
        autostartModel: autostartModel
        appearanceModel: appearanceModel
        accessibilityModel: accessibilityModel
        notificationModel: notificationModel
        panelSettingsModel: panelSettingsModel
    }
}
