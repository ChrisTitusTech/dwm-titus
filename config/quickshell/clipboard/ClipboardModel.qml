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
    property bool saveFailed: false
    property bool savePending: false
    property bool wipePending: false
    property bool settingsSaveFailed: false
    property var pendingCaptures: []

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (root.homeDir + "/.config")) + "/dwm-titus"
    readonly property string settingsPath: root.configDir + "/clipboard-settings.json"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (root.homeDir + "/.cache")) + "/dwm-titus"
    readonly property string historyPath: root.cacheDir + "/clipboard-history.json"
    readonly property string status: {
        if (root.saveFailed) {
            return "History write failed - entries are only in memory";
        }
        if (root.settingsSaveFailed) {
            return "Settings write failed - persistence state unchanged on disk";
        }

        const count = root.entries.length === 0 ? "No entries yet"
            : root.entries.length === 1 ? "1 entry" : root.entries.length + " entries";

        return root.persistenceEnabled ? count : count + " - not saved";
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", root.configDir]);
        Quickshell.execDetached(["sh", "-c",
            "mkdir -p \"$1\" && chmod 700 \"$1\"", "sh", root.cacheDir]);
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
        const stored = root.toArray(historyFile.entries);
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
        root.flushPendingCaptures();

        if (root.savePending) {
            root.savePending = false;
            root.saveHistory();
        }
    }

    function applyLoadedSettings() {
        root.persistenceEnabled = settingsFile.persistenceEnabled === true;

        // Captures flushed between the history and settings loads could only
        // be held in memory; persist them now that the stored choice is known.
        if (root.persistenceEnabled) {
            root.saveHistory();
        }
    }

    function setPersistence(enabled) {
        if (root.persistenceEnabled === enabled) {
            return;
        }

        root.persistenceEnabled = enabled;
        settingsFile.persistenceEnabled = enabled;
        settingsFile.writeAdapter();

        if (enabled) {
            root.saveHistory();
        } else {
            // The wipe is destructive, so only run it once the settings file
            // has actually recorded the disabled state; a failed write must
            // not leave the stored setting enabled with the history deleted.
            root.wipePending = true;
        }
    }

    function finishSettingsWrite() {
        root.settingsSaveFailed = false;

        if (root.wipePending && !root.persistenceEnabled) {
            root.wipePending = false;

            // Completing the deletion contract: disabling persistence wipes
            // the stored copy instead of leaving a stale one behind.
            if (root.historyReady) {
                historyFile.entries = [];
                historyFile.writeAdapter();
            }
        }
    }

    function settingsWriteFailed() {
        // The stored preference is still whatever was on disk, so undo the UI
        // change instead of letting the switch silently diverge from the file.
        root.wipePending = false;
        root.settingsSaveFailed = true;
        settingsFile.reload();
    }

    function saveHistory() {
        if (!root.historyReady) {
            // An early write would replace stored history with the not-yet-
            // loaded list; defer until the initial load has completed.
            root.savePending = true;
            return;
        }

        if (!root.persistenceEnabled) {
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

        path: root.historyPath
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.restrictHistoryFileMode();
            root.loadHistory();
        }
        onSaved: {
            root.saveFailed = false;
            root.restrictHistoryFileMode();
        }
        onSaveFailed: root.saveFailed = true
        onLoadFailed: error => {
            root.historyReady = true;

            if (error === 2) {
                root.saveHistory();
            }

            root.flushPendingCaptures();
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

        path: root.settingsPath
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyLoadedSettings()
        onSaved: root.finishSettingsWrite()
        onSaveFailed: root.settingsWriteFailed()
        onLoadFailed: error => {
            if (error === 2) {
                root.applyLoadedSettings();
                settingsFile.writeAdapter();
            }
        }

        // qmllint disable unresolved-type
        adapter: JsonAdapter {
            id: clipboardSettings

            property bool persistenceEnabled: false
        }
    }
}
