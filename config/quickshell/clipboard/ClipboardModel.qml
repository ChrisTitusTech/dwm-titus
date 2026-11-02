import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    readonly property int maxEntries: 50
    readonly property int maxEntryLength: 65536
    readonly property int maxPendingCaptures: 8
    property bool visible: false
    property string query: ""
    property int selectedIndex: 0
    property var targetScreen: null
    property var entries: []
    property var filteredEntries: []
    property int timeTick: 0
    // Capture and disk persistence require separate explicit opt-ins.
    property bool captureEnabled: false
    property bool confirmedCapture: false
    property bool requestedCapture: false
    property bool privacyReady: false
    property bool captureSuppressed: false
    property bool backendReady: false
    property bool backendFailed: false
    property bool observerStopping: false
    property string observerBuffer: ""
    property bool consentEnable: false
    property bool consentRunning: false
    property bool consentFailed: false
    property bool persistenceEnabled: false
    property bool historyReady: false
    property bool historyLoaded: false
    property bool historyLoadFailed: false
    property bool clearPending: false
    property bool settingsReady: false
    property bool settingsWriting: false
    property bool requestedPersistence: false
    property bool historyWiping: false
    property bool historyWriting: false
    property bool discardPending: false
    property bool confirmedPersistence: false
    property bool storageReady: false
    readonly property bool storagePreparing: prepareStorage.running
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
    readonly property string historyPath: root.cacheDir + "/clipboard-history-v2.json"
    readonly property string status: {
        if (root.backendFailed) return "Capture stopped: privacy backend unavailable; enable to retry";
        if (root.historyLoadFailed) return "History unreadable - retry to reload";
        if (root.saveFailed) {
            return root.wipePending ? "Stored history could not be cleared - retry save"
                : "History write failed - entries are only in memory";
        }
        if (root.settingsLoadFailed) return "Settings unreadable - capture stopped; retry to reload";
        if (root.settingsSaveFailed) {
            if (!root.storageReady) return "Storage unavailable - repair permissions and retry";
            return "Settings write failed - persistence state unchanged on disk";
        }

        if (!root.captureEnabled) return "Capture off - older history is never imported";

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
            if (root.storageReady) {
                root.settingsSaveFailed = false;
                root.historyReady = false;
                root.historyLoaded = false;
                Qt.callLater(root.startDiscard);
            }
            if (!root.storageReady) {
                root.settingsSaveFailed = true;
                root.historyReady = true;
                root.flushPendingCaptures();
            }
        }
    }

    onEntriesChanged: root.refreshFilteredEntries()
    onQueryChanged: root.refreshFilteredEntries()

    function failBackend() {
        if (observer.running) root.observerStopping = true;
        root.backendFailed = true;
        root.backendReady = false;
        root.captureEnabled = false;
        root.observerBuffer = "";
        root.pendingCaptures = [];
    }

    function observerChunk(chunk) {
        if (!root.captureEnabled || root.backendFailed) return;
        // Empty-marker SplitParser streams chunks without accumulating a frame.
        // The backend emits ASCII JSON, so chunk boundaries cannot split UTF-8.
        for (let offset = 0; offset < chunk.length;) {
            const newline = chunk.indexOf("\n", offset);
            const end = newline < 0 ? chunk.length : newline;
            if (root.observerBuffer.length + end - offset > 393300) {
                root.failBackend(); return;
            }
            root.observerBuffer += chunk.slice(offset, end);
            if (newline < 0) return;
            const frame = root.observerBuffer;
            root.observerBuffer = "";
            let value;
            try { value = JSON.parse(frame); } catch (error) { root.failBackend(); return; }
            if (!value || typeof value !== "object" || Array.isArray(value)) { root.failBackend(); return; }
            const keys = Object.keys(value).sort().join(",");
            if (!root.backendReady && keys === "event,protocol" && value.event === "ready" && value.protocol === 1) {
                root.backendReady = true;
            } else if (root.backendReady && keys === "event,text" && value.event === "text"
                    && typeof value.text === "string" && value.text.length <= root.maxEntryLength) {
                root.capture(value.text);
            } else { root.failBackend(); return; }
            offset = newline + 1;
        }
    }

    Process {
        id: observer
        command: Commands.helperCommand("dwm-clipboard-observer", null, [])
        running: root.captureEnabled && root.settingsReady && !root.settingsLoadFailed
            && !root.clearPending && !root.backendFailed && !root.observerStopping
        onRunningChanged: if (running) { root.backendReady = false; root.observerBuffer = ""; }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (root.observerStopping) root.observerStopping = false;
            else if (root.captureEnabled) root.failBackend();
        }
        stdout: SplitParser { splitMarker: ""; onRead: data => root.observerChunk(data) }
    }

    Timer {
        interval: 3000
        running: observer.running && !root.backendReady
        onTriggered: root.failBackend()
    }

    // Explicit consent discards legacy plaintext without ever reading it.
    Process {
        id: consent
        command: ["python3", "-c",
            "import os,sys,json,tempfile; os.umask(0o077); p=sys.argv[1]; old=sys.argv[2]; fd,t=tempfile.mkstemp(dir=os.path.dirname(p)); f=os.fdopen(fd,'w'); json.dump({'privacyVersion':2,'entries':[]},f); f.close(); os.replace(t,p); os.unlink(old) if os.path.lexists(old) else None",
            root.historyPath, root.cacheDir + "/clipboard-history.json"]
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            root.consentRunning = false;
            if (exitCode !== 0 || exitStatus !== 0) { root.consentFailed = true; root.saveFailed = true; return; }
            root.consentFailed = false;
            root.discardPending = false;
            root.saveFailed = false;
            root.clearPending = false;
            root.wipePending = false;
            root.privacyReady = true;
            root.historyReady = false;
            root.historyLoaded = false;
            if (!root.consentEnable && root.settingsReady && !root.settingsLoadFailed) root.captureEnabled = root.confirmedCapture && !root.captureSuppressed;
            historyFile.reload();
            if (root.consentEnable) root.writeSettings(true, false);
        }
    }

    function startDiscard() {
        if (!root.discardPending || root.historyWriting || root.consentRunning || !root.storageReady) return;
        root.discardPending = false;
        root.consentRunning = true;
        consent.running = true;
    }

    function writeEntries(entries) {
        // FileView suppresses identical writes without a completion signal.
        // A serial guarantees every scheduled write has a matching callback.
        historyFile.privacyVersion = 2;
        historyFile.entries = entries;
        historyFile.writeSerial += 1;
        root.historyWriting = true;
        historyFile.writeAdapter();
    }

    function finishHistoryWrite(success) {
        root.historyWriting = false;
        root.saveFailed = !success;
        if (success && root.historyWiping) root.wipePending = false;
        root.historyWiping = false;
        if (root.discardPending) { Qt.callLater(root.startDiscard); return; }
        if (!success) { Qt.callLater(historyFile.reload); return; }
        root.restrictHistoryFileMode();
        if (root.wipePending) Qt.callLater(root.flushPendingWipe);
        else if (root.savePending) {
            root.savePending = false;
            Qt.callLater(root.saveHistory);
        }
    }

    function setCapture(enabled) {
        if (root.settingsWriting || root.consentRunning) return;
        root.requestedCapture = enabled;
        root.backendFailed = false;
        root.backendReady = false;
        if (!enabled) {
            if (observer.running) root.observerStopping = true;
            root.captureSuppressed = true;
            root.captureEnabled = false;
            root.entries = [];
            root.pendingCaptures = [];
            root.wipePending = true;
            root.persistenceEnabled = false;
            root.confirmedPersistence = false;
            root.confirmedCapture = false;
            root.clearAll();
            if (!root.settingsLoadFailed) root.writeSettings(false, false);
            return;
        }
        if (!root.storageReady || !root.settingsReady || root.settingsLoadFailed) return;
        if (!root.privacyReady) {
            root.consentEnable = true;
            root.consentRunning = true;
            consent.running = true;
        } else if (root.confirmedCapture && !root.settingsSaveFailed) {
            root.captureSuppressed = false;
            root.captureEnabled = true;
        } else root.writeSettings(true, root.confirmedPersistence);
    }

    function writeSettings(capture, persistence) {
        root.requestedCapture = capture;
        root.requestedPersistence = persistence;
        root.persistenceEnabled = persistence;
        settingsFile.captureEnabled = capture;
        settingsFile.persistenceEnabled = persistence;
        settingsFile.privacyVersion = 2;
        root.settingsWriting = true;
        settingsFile.setText(JSON.stringify({privacyVersion:2, captureEnabled:capture, persistenceEnabled:persistence}) + "\n");
    }

    function capture(text) {
        if (!root.captureEnabled || !root.backendReady || root.settingsLoadFailed) return;
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
        const savedEntries = historyFile.privacyVersion === 2 ? root.toArray(historyFile.entries) : [];
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
        root.privacyReady = settingsFile.privacyVersion === 2;
        root.confirmedCapture = root.privacyReady && settingsFile.captureEnabled === true;
        root.captureEnabled = root.confirmedCapture && !root.captureSuppressed && !root.backendFailed;
        root.confirmedPersistence = root.privacyReady && root.confirmedCapture && settingsFile.persistenceEnabled === true;
        root.persistenceEnabled = root.confirmedPersistence;
        root.settingsReady = true;
        if (!root.privacyReady) { root.historyReady = true; return; }
        if (root.historyLoadFailed) Qt.callLater(historyFile.reload);
        else if (root.historyLoaded) root.loadHistory();
        if (root.persistenceEnabled) root.saveHistory();
    }

    function setPersistence(enabled) {
        if (!root.storageReady || !root.settingsReady || root.settingsWriting
                || root.settingsLoadFailed || root.historyWiping || root.persistenceEnabled === enabled) return;
        if (!root.captureEnabled) return;
        root.wipePending = !enabled;
        root.writeSettings(root.confirmedCapture, enabled);
    }

    function flushPendingWipe() {
        if (root.privacyReady && root.wipePending && !root.settingsWriting && !root.settingsLoadFailed
                && !root.historyLoadFailed && !root.confirmedPersistence && root.historyReady
                && !root.historyWriting && !root.clearPending && !root.consentRunning) {
            root.historyWiping = true;
            root.writeEntries([]);
        }
    }

    function finishSettingsWrite() {
        root.confirmedCapture = root.requestedCapture;
        root.captureSuppressed = !root.requestedCapture;
        root.captureEnabled = root.requestedCapture;
        root.confirmedPersistence = root.requestedPersistence;
        root.settingsWriting = false;
        root.settingsSaveFailed = false;
        root.flushPendingWipe();
        if (root.confirmedPersistence) root.saveHistory();
    }

    function settingsWriteFailed() {
        root.captureEnabled = false;
        root.captureSuppressed = true;
        root.settingsWriting = false;
        root.settingsSaveFailed = true;
        root.persistenceEnabled = root.confirmedPersistence;
        settingsFile.privacyVersion = 0;
        settingsFile.captureEnabled = false;
        settingsFile.persistenceEnabled = false;
        // Reset FileView's failed-write cache once. Missing-file loads do not
        // write defaults, so this cannot become a reload/write retry loop.
        root.settingsReady = false;
        Qt.callLater(settingsFile.reload);
    }

    function retrySave() {
        if (!root.storageReady) {
            if (!prepareStorage.running) prepareStorage.running = true;
            return;
        }
        if (root.consentFailed) { root.consentRunning = true; consent.running = true; }
        else if (root.settingsLoadFailed) settingsFile.reload();
        else if (root.historyLoadFailed) historyFile.reload();
        else if (root.settingsSaveFailed) root.writeSettings(root.requestedCapture, root.requestedPersistence);
        else if (root.wipePending) root.flushPendingWipe();
        else root.saveHistory();
    }

    function saveHistory() {
        if (root.clearPending || root.discardPending || root.consentRunning) return;
        if (root.historyWriting) { root.savePending = true; return; }
        if (!root.historyReady) {
            // An early write would replace stored history with the not-yet-
            // loaded list; defer until the initial load has completed.
            root.savePending = true;
            return;
        }

        if (root.historyLoadFailed || !root.storageReady || !root.persistenceEnabled || !root.confirmedPersistence) {
            return;
        }

        root.writeEntries(root.entries);
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
        if (observer.running) root.observerStopping = true;
        root.captureEnabled = false;
        root.backendReady = false;
        root.clearPending = true;
        root.pendingCaptures = [];
        root.entries = [];
        root.consentEnable = false;
        root.savePending = false;
        root.discardPending = true;
        root.startDiscard();
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

        property alias privacyVersion: clipboardAdapter.privacyVersion
        property alias writeSerial: clipboardAdapter.writeSerial
        property alias entries: clipboardAdapter.entries

        path: root.storageReady && root.privacyReady ? root.historyPath : ""
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
        onSaved: root.finishHistoryWrite(true)
        onSaveFailed: root.finishHistoryWrite(false)
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

            property int privacyVersion: 0
            property int writeSerial: 0
            property var entries: []
        }
    }

    FileView {
        id: settingsFile

        property alias privacyVersion: clipboardSettings.privacyVersion
        property alias captureEnabled: clipboardSettings.captureEnabled
        property alias persistenceEnabled: clipboardSettings.persistenceEnabled

        path: root.storageReady ? root.settingsPath : ""
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyLoadedSettings()
        onSaved: root.finishSettingsWrite()
        onSaveFailed: root.settingsWriteFailed()
        onLoadFailed: error => {
            if (error === 2) {
                settingsFile.privacyVersion = 0;
                settingsFile.captureEnabled = false;
                settingsFile.persistenceEnabled = false;
                root.applyLoadedSettings();
                return;
            }
            root.captureEnabled = false;
            root.captureSuppressed = true;
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

            property int privacyVersion: 0
            property bool captureEnabled: false
            property bool persistenceEnabled: false
        }
    }
}
