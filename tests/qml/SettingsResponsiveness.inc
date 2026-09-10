    // Runs inside an isolated copy of the production ShellRoot.
    property int responseStage: 0
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
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: {
            if (root.responseStage === 0) {
                console.info("Settings measurement: closed panes=" + root.responsePaneItems().length
                    + " items=" + root.responseItems(settingsWindow.contentItem, () => true).length
                    + " startup_ms=" + (Date.now() - root.responseStarted));
                root.responseCheck(root.responsePaneItems().length === 0, "Closed startup creates no panes");
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
            } else {
                root.responseCheck(root.responsePaneItems().length === 9, "Reopening does not duplicate panes");
                root.responseCheck(root.responsePaneItems().indexOf(root.responseFirstPane) >= 0, "First pane identity survives navigation and close");
                root.responseCheck(root.responseFirstPane.profileName === "Unsaved display profile", "Unsaved profile name survives navigation and close");
                root.responseCheck(root.responsePanes.every(item => root.responsePaneItems().indexOf(item) >= 0), "Every visited pane survives");
                settingsModel.close();
                console.info("Settings responsiveness: PASS");
                Qt.quit();
            }
        }
    }
