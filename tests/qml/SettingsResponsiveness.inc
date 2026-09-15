    // Runs inside an isolated copy of the production ShellRoot.
    property int responseStage: -4
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
                        "text-size": {state: "available", value: scale.toString(), option: scale.toString()}
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
                appearanceModel.personalizationSelections["text-size"].value = "1.0";
                appearanceModel.applySharedTypography();
                settingsModel.openWindow();
                root.responseStarted = Date.now();
                root.responseStage = 1;
            } else if (root.responseStage === 1) {
                const panes = root.responsePaneItems();
                if (!panes.some(item => String(item).startsWith("DisplaySettingsPane"))) return;
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
                settingsModel.selectSection(section.id);
                const expected = ["Display", "Input", "Network", "Bluetooth", "Audio", "Power", "Defaults", "Appearance", "System"][index];
                const pane = root.responsePaneItems().find(item => String(item).startsWith(expected + "SettingsPane"));
                if (!pane || !pane.visible || pane.width <= 0 || pane.height <= 0) return;
                root.responseCheck(pane.width > 0 && pane.height > 0, "Loaded pane has layout geometry: " + section.id);
                if (section.id === "input") {
                    const reads = settingsModel.testInputReads;
                    settingsModel.refresh();
                    root.responseCheck(settingsModel.testInputReads === reads + 1, "Explicit Refresh reloads input state");
                }
                root.responsePanes.push(pane);
                root.responseStage++;
            } else if (root.responseStage === 11) {
                settingsModel.close();
                root.responseCheck(root.responsePaneItems().length === 9, "Closing retains visited panes");
                settingsModel.openWindow();
                root.responseStage++;
            } else if (root.responseStage === 12) {
                root.responseCheck(root.responsePaneItems().length === 9, "Reopening does not duplicate panes");
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
                    const launcher = Qt.createComponent("launcher/LauncherResultDelegate.qml");
                    const wifi = Qt.createComponent("network/NetworkWifiRow.qml");
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
                console.info("Settings responsiveness: PASS");
                Qt.quit();
            }
        }
    }
