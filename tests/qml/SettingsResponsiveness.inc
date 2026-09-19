    // Runs inside an isolated copy of the production ShellRoot.
    property bool checkedAppearanceStatusDelay: false
    property bool checkedDisplayRecovery: false
    property bool checkedInputRecovery: false
    property string delayedSection: ""
    property int delayedFrames: 0
    property bool checkedPolicyRead: false
    property bool checkedUpdaterRead: false
    property int loadingFrames: 0
    property var loadingBounds: []
    property int responseStage: -4
    property var scaleHealthWindow: null
    property var scaleNotificationPopup: null
    property int scaleNotificationDismissed: -1
    property var scaleNetworkPopup: null
    property var scaleAudioPopup: null
    property var scaleRows: []
    property var scaleBluetoothPane: null
    property int scrollFrames: 0
    property real scrollStartY: 0
    property var scrollPane: null
    property var responsePanes: []
    property double responseStarted: Date.now()
    property var responseFirstPane: null
    function responseCheck(ok, detail) {
        if (!ok) {
            console.error("Responsiveness FAILED: " + detail);
            Qt.quit();
            throw new Error(detail);
        }
    }
    function responseItems(item, predicate) {
        let result = predicate(item) ? [item] : [];
        for (const child of item.children || [])
            result = result.concat(responseItems(child, predicate));
        return result;
    }
    function responsePaneItems() {
        return responseItems(settingsWindow.contentItem, item => /^(Display|Input|Network|Bluetooth|Audio|Power|Defaults|Appearance|System)SettingsPane_QML/.test(String(item)));
    }
    function setTypographyScale(scale) {
        const token = scale === 1 ? "1.0" : scale.toString();
        appearanceModel.personalizationSelections = {
            "font": {state: "available", value: "Noto Sans 11", option: "Noto Sans"},
            "text-size": {state: "available", value: token, option: token}
        };
        appearanceModel.applySharedTypography();
    }
    function checkPanelTypography() {
        const panel = root.defaultPanelWindow;
        if (!panel || Math.abs(panel.height - Theme.panelHeight) > 1) return false;
        const contents = root.responseItems(panel.contentItem, item => item.visible
            && (item.text !== undefined || /Image/.test(String(item))));
        root.responseCheck(contents.length > 0, "Panel typography check has visible content");
        for (const item of contents) {
            const position = item.mapToItem(panel.contentItem, 0, 0);
            root.responseCheck(position.y >= -1 && position.y + item.height <= panel.height + 1,
                "Panel content fits at scale " + Theme.requestedFontScale + ": " + item);
        }
        return true;
    }
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.responseStage === -4) {
                root.setTypographyScale(0.75);
                root.responseStage++;
            } else if (root.responseStage === -3) {
                if (root.checkPanelTypography()) root.responseStage++;
            } else if (root.responseStage === -2) {
                root.setTypographyScale(1.0);
                root.responseStage++;
            } else if (root.responseStage === -1) {
                if (root.checkPanelTypography()) root.responseStage++;
            } else if (root.responseStage === 0) {
                console.info("Settings measurement: closed panes=" + root.responsePaneItems().length
                    + " items=" + root.responseItems(settingsWindow.contentItem, () => true).length
                    + " startup_ms=" + (Date.now() - root.responseStarted));
                root.responseCheck(root.responsePaneItems().length === 0, "Closed startup creates no panes");
                appearanceModel.personalizationSelections = {
                    "font": {state: "available", value: "Noto Sans,  11", option: "Noto Sans"},
                    "text-size": {state: "available", value: "2.0", option: "2.0"}
                };
                appearanceModel.applySharedTypography();
                root.responseCheck(Theme.fontFamily === "Noto Sans" && Math.abs(Theme.fontScale * Theme.nativeScale - 2) < 0.01,
                    "Shared desktop typography reaches the shell at 200 percent");
                root.responseCheck(Theme.controlHeight >= Theme.inputFontSize,
                    "Controls accommodate the shared text size");
                appearanceModel.personalizationSelections = {};
                appearanceModel.applySharedTypography();
                root.responseCheck(Math.abs(Theme.fontScale * Theme.nativeScale - 2) < 0.01,
                    "A transient provider failure preserves the last valid desktop scale");
                for (const scale of [0.75, 1.0]) {
                    appearanceModel.personalizationSelections = {
                        "font": {state: "available", value: "Noto Sans 11", option: "Noto Sans"},
                        "text-size": {state: "available", value: scale.toString(), option: scale === 1 ? "1.0" : scale.toString()}
                    };
                    appearanceModel.applySharedTypography();
                    const expectedPixels = Math.max(10, Math.round(13 * scale));
                    root.responseCheck(Math.abs(Theme.fontBodySize * Theme.nativeScale - expectedPixels)
                            <= Theme.nativeScale / 2 + 0.01,
                        "Font minimums are compensated at " + scale);
                    root.responseCheck(Theme.pillHeight <= Theme.panelHeight
                            && Theme.trayItemSize <= Theme.panelHeight
                            && Theme.scaledSize(25.2) <= Theme.panelHeight
                            && Theme.scaledFontSize(14 * 1.5, 8) <= Theme.panelHeight,
                        "Panel contents fit at " + scale);
                }
                appearanceModel.personalizationSelections = {
                    "font": {state: "available", value: "Sans 10", option: "follow-system"},
                    "text-size": {state: "available", value: "1.0", option: "follow-system"}
                };
                appearanceModel.applySharedTypography();
                root.responseCheck(Theme.fontFamily === "Sans" && Theme.fontScale === 1
                    && !Theme.desktopTypography,
                    "Reset follows the same system typography in the shell");
                appearanceModel.personalizationSelections = {
                    "font": {state: "available", value: "Sans 10", option: "follow-system"},
                    "text-size": {state: "available", value: "1.5", option: "follow-system"}
                };
                appearanceModel.applySharedTypography();
                root.responseCheck(Theme.fontScale === 1.5 && !Theme.desktopTypography,
                    "System-follow honors non-default text size while preserving native DPI");
                for (const value of [0.5, 3.0]) {
                    root.setTypographyScale(1.0);
                    appearanceModel.personalizationSelections["text-size"] = {
                        state: "available", value: value.toString(), option: "follow-system"};
                    appearanceModel.applySharedTypography();
                    root.responseCheck(Theme.fontScale === Math.max(0.75, Math.min(2.0, value))
                        && !Theme.desktopTypography,
                        "External system scale clamps deterministically and clears explicit ownership");
                }
                appearanceModel.personalizationSelections["text-size"] = {
                    state: "available", value: "1.5", option: "follow-system"};
                appearanceModel.applySharedTypography();
                appearanceModel.personalizationSelections["text-size"] = {
                    state: "partial", value: "1.0", option: "unknown"};
                appearanceModel.applySharedTypography();
                root.responseCheck(Theme.fontScale === 1.5 && !Theme.desktopTypography,
                    "Unknown scale ownership preserves the last valid system DPI mode");
                appearanceModel.personalizationSelections["text-size"] = {
                    state: "available", value: "1.0", option: "follow-system"};
                appearanceModel.applySharedTypography();
                settingsModel.testInitialLoading = true;
                settingsModel.openWindow();
                settingsModel.refreshDisplays();
                settingsModel.refreshCapabilities();
                root.responseStarted = Date.now();
                root.responseStage = 1;
            } else if (root.responseStage === 1) {
                const panes = root.responsePaneItems();
                if (!panes.some(item => String(item).startsWith("DisplaySettingsPane"))) return;
                const initialPane = panes.find(item => String(item).startsWith("DisplaySettingsPane"));
                const viewport = initialPane.parent;
                if (settingsModel.testInitialLoading) {
                    root.responseCheck(initialPane.opacity === 0 && !initialPane.enabled,
                        "Initial controls stay hidden and disabled while data is delayed");
                    const bounds = [viewport.x, viewport.y, viewport.width, viewport.height];
                    if (root.loadingFrames === 0) root.loadingBounds = bounds;
                    else root.responseCheck(JSON.stringify(bounds) === JSON.stringify(root.loadingBounds),
                        "Loading viewport stays fixed while initial data is delayed");
                    root.loadingFrames++;
                    if (root.loadingFrames >= 6) settingsModel.testInitialLoading = false;
                    return;
                }
                if (settingsModel.displayActionBusy) {
                    root.responseCheck(initialPane.opacity === 0 && !initialPane.enabled,
                        "Display preview recovery keeps initial controls hidden");
                    root.checkedDisplayRecovery = true;
                    return;
                }
                if (initialPane.opacity !== 1) return;
                root.responseCheck(initialPane.enabled, "Settled controls become usable");
                root.responseCheck(JSON.stringify([viewport.x, viewport.y, viewport.width, viewport.height])
                    === JSON.stringify(root.loadingBounds), "Loaded viewport matches loading viewport");
                settingsModel.testInitialLoading = true;
                root.responseCheck(initialPane.opacity === 1 && initialPane.enabled,
                    "Later refresh does not hide existing controls");
                settingsModel.testInitialLoading = false;
                console.info("Settings measurement: first pane ready_ms=" + (Date.now() - root.responseStarted));
                const before = settingsModel.testActivations;
                settingsModel.setSearch("dis");
                settingsModel.setSearch("disp");
                settingsModel.selectSection("displays");
                settingsModel.selectRelative(1); // One matching section.
                console.info("Settings measurement: redundant activations=" + (settingsModel.testActivations - before));
                root.responseCheck(settingsModel.testActivations === before, "Same-section search/navigation does not rediscover");
                settingsModel.setSearch("audio");
                root.responseCheck(settingsModel.testActivations === before + 1 && settingsModel.selectedSectionId === "audio", "A changed search activates its section exactly once");
                settingsModel.selectSection("displays");
                root.responseCheck(settingsModel.testActivations === before + 2 && settingsModel.searchQuery === "", "Selecting outside the filter clears it without intermediate activation");
                const reads = settingsModel.testDisplayReads;
                settingsModel.refresh();
                root.responseCheck(settingsModel.testDisplayReads === reads + 1, "Explicit Refresh reloads display state");
                root.responseFirstPane = panes.find(item => String(item).startsWith("DisplaySettingsPane"));
                root.responseFirstPane.profileName = "Unsaved display profile";
                root.responseStage = 2;
                settingsModel.setSearch("");
            } else if (root.responseStage >= 2 && root.responseStage <= 10) {
                const index = root.responseStage - 2;
                const section = settingsModel.sections[index];
                if (root.delayedSection !== section.id) {
                    root.delayedSection = section.id;
                    root.delayedFrames = 0;
                    if (section.id === "input") settingsModel.recoverInputPreview();
                    if (section.id === "appearance") notificationModel.policyState = "loading";
                    if (section.id === "system") desktopUpdateModel.commandPending = true;
                    settingsModel.selectSection(section.id);
                    if (section.id === "defaults") {
                        defaultsModel.refresh();
                        autostartModel.refresh();
                    }
                    if (section.id === "power") powerModel.refresh();
                }
                const expected = ["Display", "Input", "Network", "Bluetooth", "Audio", "Power", "Defaults", "Appearance", "System"][index];
                const pane = root.responsePaneItems().find(item => String(item).startsWith(expected + "SettingsPane"));
                if (pane && !pane.parent.presented && section.id === "input" && settingsModel.inputActionBusy) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Input preview recovery keeps initial controls hidden");
                    root.checkedInputRecovery = true;
                }
                if (pane && section.id === "appearance" && root.delayedFrames < 6) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Notification policy read and first save keep Appearance hidden");
                    root.checkedPolicyRead = true;
                    if (++root.delayedFrames === 3) notificationModel.policyState = "defaults";
                    if (root.delayedFrames === 6) {
                        notificationModel.popupTimeoutMs = notificationModel.popupTimeoutMs === 4000 ? 10000 : 4000;
                        notificationModel.savePolicy();
                    }
                }
                if (pane && section.id === "system" && root.delayedFrames < 6) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Updater status and queued discovery keep System hidden");
                    root.checkedUpdaterRead = true;
                    if (++root.delayedFrames === 3) {
                        desktopUpdateModel.initialCheckQueued = true;
                        desktopUpdateModel.commandPending = false;
                    }
                    if (root.delayedFrames === 6) desktopUpdateModel.initialCheckQueued = false;
                }
                if (section.id === "appearance" && pane && !pane.parent.presented
                        && !appearanceModel.initialLoading && !settingsModel.busy
                        && !settingsModel.capabilityRefreshPending
                        && (accessibilityModel.initialLoading || panelSettingsModel.initialLoading)) {
                    root.responseCheck(pane.opacity === 0 && !pane.enabled,
                        "Late accessibility/panel status cannot reveal default controls");
                    root.checkedAppearanceStatusDelay = true;
                }
                if (!pane || !pane.visible || pane.opacity !== 1 || pane.width <= 0 || pane.height <= 0) return;
                root.responseCheck(pane.width > 0 && pane.height > 0, "Loaded pane has layout geometry: " + section.id);
                if (section.id === "appearance") root.responseCheck(notificationModel.policyState === "available",
                    "The delayed first policy save produces a valid available policy");
                if (section.id === "input") {
                    const reads = settingsModel.testInputReads;
                    settingsModel.refresh();
                    root.responseCheck(settingsModel.testInputReads === reads + 1, "Explicit Refresh reloads input state");
                }
                root.responsePanes.push(pane);
                root.responseStage++;
            } else if (root.responseStage === 11) {
                root.responseCheck(!settingsWindow.testEarlyPresentation, "First presentation waits for every pending provider");
                root.responseCheck(root.checkedDisplayRecovery && root.checkedInputRecovery,
                    "Exercised both delayed preview-recovery reads");
                root.responseCheck(root.checkedPolicyRead && root.checkedUpdaterRead,
                    "Exercised notification policy and desktop updater initial reads");
                root.responseCheck(!autostartModel.testQueuedGap && !defaultsModel.testQueuedGap
                        && !powerModel.testQueuedGap && !settingsModel.testQueuedGap,
                    "Queued refresh flags remain set until the next process starts");
                root.responseCheck(root.checkedAppearanceStatusDelay,
                    "Exercised panel/accessibility reads finishing after other Appearance data");
                settingsModel.testInitialLoading = true;
                settingsModel.close();
                root.responseCheck(root.responsePaneItems().length === 9, "Closing retains visited panes");
                settingsModel.openWindow();
                root.responseStage++;
            } else if (root.responseStage === 12) {
                root.responseCheck(root.responsePaneItems().length === 9, "Reopening does not duplicate panes");
                root.responseCheck(root.responseFirstPane.opacity === 1 && root.responseFirstPane.enabled,
                    "Previously loaded controls stay usable when reopening during a refresh");
                settingsModel.testInitialLoading = false;
                root.responseCheck(root.responsePaneItems().indexOf(root.responseFirstPane) >= 0, "First pane identity survives navigation and close");
                root.responseCheck(root.responseFirstPane.profileName === "Unsaved display profile", "Unsaved profile name survives navigation and close");
                root.responseCheck(root.responsePanes.every(item => root.responsePaneItems().indexOf(item) >= 0), "Every visited pane survives");
                root.responseCheck(settingsWindow.fullscreen, "Settings requests fullscreen like System Health");
                settingsModel.selectSection("appearance");
                root.scrollPane = root.responsePaneItems().find(item => item.objectName === "appearanceSettingsPane");
                root.responseCheck(root.scrollPane !== undefined, "Appearance scroll surface is available");
                root.responseStage = 13;
            } else if (root.responseStage === 13) {
                const choices = root.responseItems(root.scrollPane,
                    item => item.capability !== undefined);
                root.responseCheck(choices.filter(item => item.capability === "font").length === 1
                    && choices.filter(item => item.capability === "text-size").length === 1,
                    "Appearance offers exactly one font and one text-size control");
                const fontChoice = choices.find(item => item.capability === "font");
                const fontInput = root.responseItems(fontChoice,
                    item => item.selectByMouse !== undefined)[0];
                fontInput.text = "Noto ";
                fontInput.textEdited();
                root.responseCheck(fontChoice.selectedValue === "Noto "
                    && fontInput.text === "Noto " && fontChoice.submissionValue === "Noto",
                    "Font editing preserves spaces and trims only the submitted value");
                const installedFamily = Qt.fontFamilies().find(family => family === "Noto Sans")
                    || Qt.fontFamilies()[0];
                root.responseCheck(appearanceModel.fontDescriptionFamily(installedFamily + " Bold Italic 11") === installedFamily
                    && appearanceModel.fontDescriptionFamily(installedFamily) === installedFamily,
                    "Styled desktop descriptions resolve to an installed family");
                root.responseCheck(fontChoice.candidateAvailable("An installed family outside the suggestions")
                    && appearanceModel.personalizationCandidateAvailable("font", "An installed family outside the suggestions")
                    && !fontChoice.candidateAvailable("Invalid\nfont"),
                    "Manual font entry is preserved without accepting malformed fields");
                root.responseCheck(!choices.some(item => item.capability === "gtk" || item.capability === "qt"),
                    "Toolkit overrides are absent from Appearance");
                root.responseCheck(root.responseItems(root.scrollPane,
                    item => item.text === "Application status" || item.text === "Keyboard and pointer access").length === 0,
                    "Diagnostic status summaries are absent from Appearance");
                root.responseCheck(root.scrollPane.contentHeight > root.scrollPane.height, "Appearance has scrollable content");
                root.scrollPane.contentY = 0;
                root.scrollPane.flick(1200, 1600);
                root.responseStage = 14;
            } else if (root.responseStage >= 14 && root.responseStage <= 17) {
                const pane = root.scrollPane;
                root.responseCheck(Math.abs(pane.contentX) < 0.1, "Diagonal input must not shift Appearance horizontally");
                root.responseCheck(pane.contentY >= -0.1 && pane.contentY <= Math.max(0, pane.contentHeight - pane.height) + 0.1,
                    "Appearance must not overscroll and bounce back");
                if (++root.scrollFrames < 20) return;
                if (root.responseStage === 14) {
                    pane.cancelFlick();
                    root.scrollStartY = pane.contentY;
                    pane.flick(-1200, -1600);
                } else if (root.responseStage === 15) {
                    root.responseCheck(pane.contentY > root.scrollStartY + 1, "An inward flick from the top must scroll down");
                    pane.cancelFlick();
                    pane.contentY = Math.max(0, pane.contentHeight - pane.height);
                    pane.flick(-1200, -1600);
                } else if (root.responseStage === 16) {
                    pane.cancelFlick();
                    root.scrollStartY = pane.contentY;
                    pane.flick(1200, 1600);
                } else {
                    root.responseCheck(pane.contentY < root.scrollStartY - 1, "An inward flick from the bottom must scroll up");
                    Theme.desktopTypography = false;
                    Theme.applyFontPreferences("Noto Sans", 2);
                    const health = Qt.createComponent("health/SystemHealthWindow.qml");
                    root.scaleHealthWindow = health.createObject(root, {healthModel: systemHealthModel});
                    root.scaleHealthWindow.visible = true;
                    const launcher = Qt.createComponent("launcher/LauncherResultDelegate.qml");
                    const wifi = Qt.createComponent("network/NetworkWifiRow.qml");
                    const notifications = Qt.createComponent("notifications/NotificationPopupWindow.qml");
                    root.scaleNotificationPopup = notifications.createObject(root,
                        {panelWindow: root.defaultPanelWindow, notificationModel: {
                            notifications: [0, 1, 2, 3].map(key => ({key: key, appName: "Test application",
                                summary: "Notification " + key, body: "A long notification body that wraps across several lines so the complete stack needs scrolling at large text sizes.",
                                urgency: 1, urgencyName: "Normal", timeoutMs: 100000})),
                            dismiss: key => { root.scaleNotificationDismissed = key; }, expire: () => {}}});
                    const network = Qt.createComponent("network/NetworkWindow.qml");
                    root.scaleNetworkPopup = network.createObject(root, {panelWindow: root.defaultPanelWindow,
                        networkModel: {visible: true, busy: false, actionsAvailable: true, editorAvailable: false,
                            wifiPasswordPromptVisible: true, wifiPasswordPromptOrigin: "panel", wifiPassword: "",
                            statusText: "Online", message: "", activeConnections: [], savedProfiles: [], wifiNetworks: [],
                            selectedWifiIndex: -1, selectedWifiNetwork: () => ({ssid: "Test network"}),
                            cancelWifiPasswordPrompt: () => {}, close: () => {}}});
                    const audio = Qt.createComponent("controls/ControlsWindow.qml");
                    root.scaleAudioPopup = audio.createObject(root, {panelWindow: root.defaultPanelWindow,
                        controlsModel: {visible: true, busy: false, volumeMuted: false, volumeDisplayText: "50%",
                            message: "", volumePercent: 50, micText: "MIC on", mediaText: "Track",
                            mediaPlayer: "Player", outputDevices: [{name: "output", description: "Speakers", isDefault: true}],
                            close: () => {}}});
                    const bluetooth = Qt.createComponent("settings/BluetoothSettingsPane.qml");
                    root.scaleBluetoothPane = bluetooth.createObject(settingsWindow.contentItem,
                        {width: 1000, height: 900, bluetoothModel: {
                            providerState: "available", statusText: "Bluetooth", powered: true,
                            available: true, actionsAvailable: true, busy: false, message: "",
                            actionAddress: "", devices: [{name: "Headphones", address: "00:11:22:33:44:55",
                                connected: false, paired: false, trusted: false}]}});
                    root.scaleRows = [
                        launcher.createObject(settingsWindow.contentItem, {width: 700, index: 0,
                            selected: false, modelData: {name: "Application", generic: "Description", comment: "", primaryCategory: "Utility", icon: ""},
                            launcherModel: {categoryLabel: () => "Utility"}}),
                        wifi.createObject(settingsWindow.contentItem, {width: 700,
                            network: {ssid: "Network", security: "WPA2", signal: 80, device: "wlan0", active: false}})
                    ];
                }
                root.scrollFrames = 0;
                root.responseStage++;
            } else if (root.responseStage === 18) {
                const tiles = root.responseItems(root.scaleHealthWindow.contentItem,
                    item => item.objectName === "healthSummaryTile");
                root.responseCheck(tiles.length === 4, "Health summary renders four tiles");
                for (const tile of tiles) {
                    root.responseCheck(tile.x >= 0 && tile.x + tile.width <= tile.parent.width + 1,
                        "Health tiles wrap within the available width");
                    const labels = root.responseItems(tile, item => item.text !== undefined);
                    for (const label of labels) {
                        const point = label.mapToItem(tile, 0, 0);
                        root.responseCheck(point.x >= 0 && point.x + label.width <= tile.width
                            && label.contentWidth <= label.width + 1,
                            "Health summary label fits at 200 percent: " + label.text);
                    }
                    const caption = labels[0].mapToItem(tile, 0, 0);
                    const count = labels[1].mapToItem(tile, 0, 0);
                    root.responseCheck(caption.x + labels[0].width <= count.x,
                        "Health caption and count do not overlap");
                }
                root.scaleHealthWindow.destroy();
                const sections = root.responseItems(settingsWindow.contentItem,
                    item => item.selected !== undefined && item.modelData !== undefined
                        && item.modelData.id !== undefined);
                const bluetoothRows = root.responseItems(root.scaleBluetoothPane,
                    item => item.modelData !== undefined && item.modelData.address !== undefined);
                root.responseCheck(bluetoothRows.length > 0, "200 percent Bluetooth rows are rendered");
                const rows = root.scaleRows.concat(sections, bluetoothRows);
                root.responseCheck(root.scaleRows.every(item => item !== null) && sections.length > 0,
                    "200 percent row checks have rendered delegates");
                for (const row of rows) {
                    for (const text of root.responseItems(row, item => item.visible && item.text !== undefined)) {
                        const point = text.mapToItem(row, 0, 0);
                        root.responseCheck(point.y >= -1 && point.y + text.height <= row.height + 1,
                            "200 percent text fits its row: " + text.text);
                    }
                }
                const viewport = root.responseItems(root.scaleAudioPopup.contentItem,
                    item => item.objectName === "popupViewport")[0];
                root.responseCheck(viewport && viewport.contentHeight > viewport.height
                    && viewport.height <= root.defaultPanelWindow.screen.height,
                    "Oversized audio popup stays on screen and scrolls");
                const card = root.responseItems(root.scaleAudioPopup.contentItem,
                    item => String(item).startsWith("ShellSurface"))[0];
                root.responseCheck(card !== undefined, "Audio popup card is rendered");
                for (const text of root.responseItems(card, item => item.visible && item.text !== undefined)) {
                    const point = text.mapToItem(card, 0, 0);
                    root.responseCheck(point.y >= -1 && point.y + text.height <= card.height + 1,
                        "200 percent audio controls fit inside the scrollable card: " + text.text);
                }
                viewport.contentY = viewport.contentHeight - viewport.height;
                root.responseCheck(viewport.contentY > 0, "Audio popup can scroll to its bottom controls");
                const networkSurface = root.scaleNetworkPopup.popupContent.find(item => item.content !== undefined);
                const prompt = networkSurface.content.find(item => item.title === "dwm network password");
                root.responseCheck(prompt && prompt.visible && prompt.height <= prompt.screen.height,
                    "200 percent Wi-Fi prompt fits the screen");
                const passwordViewport = root.responseItems(prompt.contentItem,
                    item => item.objectName === "passwordViewport")[0];
                const connect = root.responseItems(prompt.contentItem, item => item.label === "Connect")[0];
                root.responseCheck(passwordViewport && connect,
                    "Wi-Fi prompt keeps its action controls");
                passwordViewport.contentY = Math.max(0, passwordViewport.contentHeight - passwordViewport.height);
                const actionPosition = connect.mapToItem(passwordViewport, 0, 0);
                root.responseCheck(actionPosition.y >= -1
                    && actionPosition.y + connect.height <= passwordViewport.height + 1,
                    "Wi-Fi Connect action is reachable at maximum scale");
                const notificationViewport = root.responseItems(root.scaleNotificationPopup.contentItem,
                    item => item.objectName === "notificationViewport")[0];
                root.responseCheck(root.scaleNotificationPopup.height + Theme.panelHeight
                    <= root.defaultPanelWindow.screen.height && notificationViewport.contentHeight > notificationViewport.height,
                    "Four large notifications stay within the screen and scroll");
                notificationViewport.contentY = notificationViewport.contentHeight - notificationViewport.height;
                const lastCard = root.responseItems(root.scaleNotificationPopup.contentItem,
                    item => item.item !== undefined && item.item.key === 3)[0];
                const dismissText = root.responseItems(lastCard, item => item.text === "x")[0];
                const dismissPosition = dismissText.mapToItem(notificationViewport, 0, 0);
                root.responseCheck(dismissPosition.y >= -1
                    && dismissPosition.y + dismissText.height <= notificationViewport.height + 1,
                    "The final notification dismiss control is reachable");
                lastCard.dismiss();
                root.responseCheck(root.scaleNotificationDismissed === 3, "Final notification dismiss reaches its model");
                root.scaleNotificationPopup.destroy();
                root.scaleNetworkPopup.destroy();
                root.scaleAudioPopup.destroy();
                for (const row of root.scaleRows) row.destroy();
                root.scaleBluetoothPane.destroy();
                settingsModel.close();
                appearanceModel.personalizationStatusPending = true;
                appearanceModel.finishPersonalizationAction();
                root.responseStage++;
            } else if (root.responseStage === 19) {
                root.responseCheck(!appearanceModel.settingsVisible
                    && !appearanceModel.personalizationStatusPending,
                    "Action completion drains typography refreshes with Settings closed");
                root.responseCheck(appearanceModel.testTypographyMonitor.running,
                    "Typography monitor initially runs");
                appearanceModel.testTypographyMonitor.running = false;
                root.responseStarted = Date.now();
                root.responseStage++;
            } else if (root.responseStage === 20) {
                if (!appearanceModel.testTypographyMonitor.running) {
                    root.responseCheck(Date.now() - root.responseStarted < 5000,
                        "Typography monitor restarts after exit with Settings closed");
                    return;
                }
                root.responseCheck(!appearanceModel.settingsVisible,
                    "Typography monitor recovers while Settings stays closed");
                console.info("Settings responsiveness: PASS");
                Qt.quit();
            }
        }
    }
