import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property int maxEntries: 50
    readonly property int maxEntryLength: 100000
    readonly property int maxPendingCaptures: 8
    property bool visible: false
    property string query: ""
    property int selectedIndex: 0
    property var targetScreen: null
    property var entries: []
    property var filteredEntries: []
    property int timeTick: 0
    // Clipboard history is opt-in: captures always stay in memory for the
    // session, but nothing is written to disk until persistence is enabled.
    property bool persistenceEnabled: false
    property bool historyReady: false
    property bool historyLoaded: false
    property bool historyLoadFailed: false
    property bool clearPending: false
    property bool settingsReady: false
    property bool settingsWriting: false
    property bool requestedPersistence: false
    property bool historyWiping: false
    property bool confirmedPersistence: false
    property bool storageReady: false
    property bool saveFailed: false
    property bool savePending: false
    property bool wipePending: false
    property bool settingsSaveFailed: false
    property bool settingsLoadFailed: false
    property var pendingCaptures: []

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (root.homeDir + "/.config")) + "/dwm-titus"
    readonly property string settingsPath: root.configDir + "/clipboard-settings.json"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (root.homeDir + "/.cache")) + "/dwm-titus"
    readonly property string historyPath: root.cacheDir + "/clipboard-history.json"
    readonly property string status: {
        if (root.historyLoadFailed) return "History unreadable - session only; retry to reload";
        if (root.saveFailed) {
            return root.wipePending ? "Stored history could not be cleared - retry save"
                : "History write failed - entries are only in memory";
        }
        if (root.settingsLoadFailed) return "Settings unreadable - session only; retry to reload";
        if (root.settingsSaveFailed) {
            return "Settings write failed - persistence state unchanged on disk";
        }

        const count = root.entries.length === 0 ? "No entries yet"
            : root.entries.length === 1 ? "1 entry" : root.entries.length + " entries";

        return root.persistenceEnabled ? count : count + " - not saved";
    }

    // Establish private storage before FileView can read or write history.
    Process {
        id: prepareStorage
        command: ["sh", "-c", "umask 077; test ! -L \"$1\" && mkdir -p -- \"$1\" \"$2\" && chmod 700 -- \"$1\"",
            "sh", root.cacheDir, root.configDir]
        running: true
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            root.storageReady = exitCode === 0 && exitStatus === 0;
            if (!root.storageReady) {
                root.settingsSaveFailed = true;
                root.historyReady = true;
                root.flushPendingCaptures();
            }
        }
    }

    onEntriesChanged: root.refreshFilteredEntries()
    onQueryChanged: root.refreshFilteredEntries()

    Connections {
        target: Quickshell

        function onClipboardTextChanged() {
            root.capture(Quickshell.clipboardText);
        }
    }

    function capture(text) {
        // FileView loads asynchronously; a capture that saved before the
        // initial load finished could replace the stored history with a
        // single-entry list, so early captures are queued instead.
        if (!root.historyReady) {
            root.queueCapture(text);
            return;
        }

        root.recordEntry(text);
        root.saveHistory();
    }

    function queueCapture(text) {
        if (typeof text !== "string") {
            return;
        }

        const value = text.length > root.maxEntryLength ? text.slice(0, root.maxEntryLength) : text;

        if (value.trim().length === 0 || root.pendingCaptures.indexOf(value) >= 0) {
            return;
        }

        root.pendingCaptures = root.pendingCaptures.concat([value]).slice(-root.maxPendingCaptures);
    }

    function flushPendingCaptures() {
        const pending = root.pendingCaptures;

        root.pendingCaptures = [];

        let changed = false;

        for (const value of pending) {
            changed = root.recordEntry(value) || changed;
        }

        if (changed) {
            root.saveHistory();
        }
    }

    function recordEntry(text) {
        if (typeof text !== "string") {
            return false;
        }

        const value = text.length > root.maxEntryLength ? text.slice(0, root.maxEntryLength) : text;

        if (value.trim().length === 0) {
            return false;
        }

        // Recopying the newest entry refreshes its timestamp so the displayed
        // age reflects the latest copy. This branch also ignores the copy-back
        // performed by select(), so writing an entry to the clipboard can
        // never re-record it.
        if (root.entries.length > 0 && root.entries[0].text === value) {
            root.entries = [{ "text": value, "timestamp": Date.now() }].concat(root.entries.slice(1));
            return true;
        }

        const remaining = [];

        for (const entry of root.entries) {
            if (entry.text !== value) {
                remaining.push(entry);
            }
        }

        root.entries = [{ "text": value, "timestamp": Date.now() }].concat(remaining).slice(0, root.maxEntries);
        return true;
    }

    // JsonAdapter hands back a QVariantList, which is array-like but not a
    // real JS Array (Array.isArray is false), so copy it by index.
    function toArray(value) {
        const rows = [];

        if (!value) {
            return rows;
        }

        for (let index = 0; index < value.length; index++) {
            rows.push(value[index]);
        }

        return rows;
    }

    function loadHistory() {
        root.historyLoaded = true;
        if (!root.settingsReady || root.settingsLoadFailed || root.historyLoadFailed || root.historyReady) return;
        const savedEntries = root.toArray(historyFile.entries);
        if (!root.confirmedPersistence && savedEntries.length > 0) root.wipePending = true;
        const stored = root.confirmedPersistence && !root.clearPending ? savedEntries : [];
        const entries = [];

        for (const item of stored) {
            if (!item || typeof item.text !== "string" || item.text.trim().length === 0) {
                continue;
            }

            const text = item.text.length > root.maxEntryLength ? item.text.slice(0, root.maxEntryLength) : item.text;
            const timestamp = typeof item.timestamp === "number" && item.timestamp > 0
                ? item.timestamp : Date.now();

            entries.push({ "text": text, "timestamp": timestamp });
        }

        root.entries = entries.slice(0, root.maxEntries);
        root.historyReady = true;
        // Finish FileView load notification before starting its atomic write.
        Qt.callLater(root.flushPendingWipe);
        root.flushPendingCaptures();
        if (root.clearPending) Qt.callLater(root.saveHistory);

        if (root.savePending) {
            root.savePending = false;
            root.saveHistory();
        }
    }

    function applyLoadedSettings() {
        if (root.settingsLoadFailed) {
            root.pendingCaptures = root.entries.map(entry => entry.text).reverse().concat(root.pendingCaptures);
            root.historyReady = false;
            root.settingsLoadFailed = false;
            root.settingsSaveFailed = false;
        }
        root.confirmedPersistence = settingsFile.persistenceEnabled === true;
        root.persistenceEnabled = root.confirmedPersistence;
        root.settingsReady = true;
        if (root.historyLoadFailed) Qt.callLater(historyFile.reload);
        else if (root.historyLoaded) root.loadHistory();
        if (root.persistenceEnabled) root.saveHistory();
    }

    function setPersistence(enabled) {
        if (!root.storageReady || !root.settingsReady || root.settingsWriting
                || root.settingsLoadFailed || root.historyWiping || root.persistenceEnabled === enabled) return;
        root.requestedPersistence = enabled;
        root.persistenceEnabled = enabled;
        settingsFile.persistenceEnabled = enabled;
        root.settingsWriting = true;
        root.wipePending = !enabled;
        settingsFile.setText(JSON.stringify({ "persistenceEnabled": enabled }) + "\n");
    }

    function flushPendingWipe() {
        if (root.wipePending && !root.settingsWriting && !root.settingsLoadFailed
                && !root.historyLoadFailed && !root.confirmedPersistence && root.historyReady) {
            root.historyWiping = true;
            historyFile.entries = [];
            historyFile.writeAdapter();
        }
    }

    function finishSettingsWrite() {
        root.confirmedPersistence = root.persistenceEnabled;
        root.settingsWriting = false;
        root.settingsSaveFailed = false;
        root.flushPendingWipe();
        if (root.confirmedPersistence) root.saveHistory();
    }

    function settingsWriteFailed() {
        root.wipePending = false;
        root.settingsWriting = false;
        root.settingsSaveFailed = true;
        root.persistenceEnabled = root.confirmedPersistence;
        settingsFile.persistenceEnabled = root.confirmedPersistence;
        // Reset FileView's failed-write cache once. Missing-file loads do not
        // write defaults, so this cannot become a reload/write retry loop.
        root.settingsReady = false;
        Qt.callLater(settingsFile.reload);
    }

    function retrySave() {
        if (root.settingsLoadFailed) settingsFile.reload();
        else if (root.historyLoadFailed) historyFile.reload();
        else if (root.settingsSaveFailed) root.setPersistence(root.requestedPersistence);
        else if (root.wipePending) root.flushPendingWipe();
        else root.saveHistory();
    }

    function saveHistory() {
        if (!root.historyReady) {
            // An early write would replace stored history with the not-yet-
            // loaded list; defer until the initial load has completed.
            root.savePending = true;
            return;
        }

        if (root.historyLoadFailed || !root.storageReady || !root.persistenceEnabled || !root.confirmedPersistence) {
            return;
        }

        historyFile.entries = root.entries;
        historyFile.writeAdapter();
    }

    function restrictHistoryFileMode() {
        // Atomic writes recreate the file with default permissions on every
        // save, so re-assert the private mode after each write. Clipboard
        // history can hold secrets and must stay readable by its owner only.
        Quickshell.execDetached(["chmod", "600", root.historyPath]);
    }

    function refreshFilteredEntries() {
        const needle = root.query.trim().toLowerCase();
        const rows = [];

        for (const entry of root.entries) {
            if (needle.length === 0 || entry.text.toLowerCase().indexOf(needle) >= 0) {
                rows.push(entry);
            }
        }

        if (root.selectedIndex >= rows.length) {
            root.selectedIndex = rows.length > 0 ? rows.length - 1 : 0;
        }

        root.filteredEntries = rows;
    }

    function openWindow() {
        root.visible = true;
        root.query = "";
        root.selectedIndex = 0;
        root.refreshFilteredEntries();
    }

    function open() {
        root.targetScreen = null;
        root.openWindow();
    }

    function openOnScreen(screen) {
        root.targetScreen = screen;
        root.openWindow();
    }

    function close() {
        root.visible = false;
        root.query = "";
        root.selectedIndex = 0;
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function setQuery(value) {
        root.query = value;
        root.selectedIndex = 0;
    }

    function selectRelative(delta) {
        const rows = root.filteredEntries;

        if (rows.length === 0) {
            root.selectedIndex = 0;
            return;
        }

        root.selectedIndex = ((root.selectedIndex + delta) % rows.length + rows.length) % rows.length;
    }

    function selectAbsolute(index) {
        const rows = root.filteredEntries;

        if (rows.length === 0) {
            root.selectedIndex = 0;
            return;
        }

        root.selectedIndex = Math.max(0, Math.min(index, rows.length - 1));
    }

    function select(index) {
        const rows = root.filteredEntries;

        if (index < 0 || index >= rows.length) {
            return;
        }

        const entry = rows[index];

        root.entries = [{ "text": entry.text, "timestamp": Date.now() }].concat(
            root.entries.filter(function(item) {
                return item.text !== entry.text;
            }));
        root.saveHistory();
        Quickshell.clipboardText = entry.text;
        root.close();
    }

    function copySelected() {
        if (root.filteredEntries.length > 0) {
            root.select(root.selectedIndex);
        }
    }

    function deleteAt(index) {
        const rows = root.filteredEntries;

        if (index < 0 || index >= rows.length) {
            return;
        }

        const text = rows[index].text;

        root.entries = root.entries.filter(function(item) {
            return item.text !== text;
        });
        root.saveHistory();
    }

    function clearAll() {
        root.clearPending = true;
        root.pendingCaptures = [];
        root.entries = [];
        root.saveHistory();
    }

    function relativeTime(timestamp) {
        const ageSeconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));

        if (ageSeconds < 60) {
            return "now";
        }
        if (ageSeconds < 3600) {
            return Math.floor(ageSeconds / 60) + "m";
        }
        if (ageSeconds < 86400) {
            return Math.floor(ageSeconds / 3600) + "h";
        }
        return Math.floor(ageSeconds / 86400) + "d";
    }

    FileView {
        id: historyFile

        property alias entries: clipboardAdapter.entries

        path: root.storageReady ? root.historyPath : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            if (root.historyLoadFailed) {
                root.pendingCaptures = root.entries.map(entry => entry.text).reverse().concat(root.pendingCaptures);
                root.historyReady = false;
                root.historyLoadFailed = false;
                root.saveFailed = false;
            }
            root.restrictHistoryFileMode();
            root.loadHistory();
        }
        onSaved: {
            root.clearPending = false;
            root.saveFailed = false;
            if (root.historyWiping) root.wipePending = false;
            root.historyWiping = false;
            root.restrictHistoryFileMode();
        }
        onSaveFailed: {
            root.saveFailed = true;
            root.historyWiping = false;
            Qt.callLater(historyFile.reload);
        }
        onLoadFailed: error => {
            root.historyLoaded = true;
            if (error !== 2) {
                root.historyLoadFailed = true;
                root.saveFailed = true;
                root.historyReady = true;
                root.flushPendingCaptures();
            } else {
                if (root.historyLoadFailed) {
                    root.pendingCaptures = root.entries.map(entry => entry.text).reverse().concat(root.pendingCaptures);
                    root.historyReady = false;
                    root.saveFailed = false;
                }
                root.historyLoadFailed = false;
                root.loadHistory();
            }
        }

        // qmllint disable unresolved-type
        adapter: JsonAdapter {
            id: clipboardAdapter

            property var entries: []
        }
    }

    FileView {
        id: settingsFile

        property alias persistenceEnabled: clipboardSettings.persistenceEnabled

        path: root.storageReady ? root.settingsPath : ""
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyLoadedSettings()
        onSaved: root.finishSettingsWrite()
        onSaveFailed: root.settingsWriteFailed()
        onLoadFailed: error => {
            if (error === 2) {
                settingsFile.persistenceEnabled = false;
                root.applyLoadedSettings();
                return;
            }
            root.settingsReady = true;
            root.settingsSaveFailed = true;
            root.settingsLoadFailed = true;
            root.historyReady = true;
            root.confirmedPersistence = false;
            root.persistenceEnabled = false;
            root.flushPendingCaptures();
        }

        // qmllint disable unresolved-type
        adapter: JsonAdapter {
            id: clipboardSettings

            property bool persistenceEnabled: false
        }
    }
}
