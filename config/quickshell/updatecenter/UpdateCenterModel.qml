import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.core
import "UpdateCenterProtocol.js" as Protocol

Scope {
    id: root

    property var providers: []
    property int totalUpdates: 0
    property bool visible: false
    property bool settingsMode: false
    property int draftRefreshSeconds: 3600
    property bool draftAlwaysShow: true
    property var activeOperation: null
    property var connectivitySource: Networking
    property string message: ""
    property string settingsError: ""
    property int savedRefreshSeconds: 3600
    property bool savedAlwaysShow: true
    property string settingsBaseline: "absent"
    property bool initialCacheLoaded: false
    property bool initialLiveScanComplete: false
    property bool connectivityReady: false
    property bool startupDelayElapsed: false
    property bool pendingForceRefresh: false
    property bool pendingSettingsReload: false
    property string pendingTerminalClose: ""
    readonly property bool online: root.connectivitySource.devices.values.some(
        device => device.connected)
    readonly property bool busy: root.activeOperation !== null
    readonly property bool scanning: scanProcess.running
    readonly property bool settingsLoading: settingsStatusProcess.running
    readonly property bool periodicRefreshRunning: refreshTimer.running
    readonly property int refreshIntervalMilliseconds: root.savedRefreshSeconds * 1000

    function hasExceptionalState() {
        return root.providers.some(provider => provider.freshness === "stale" || provider.freshness === "error"
            || provider.errorCode.length > 0 || ["partial", "restricted"].indexOf(provider.status) >= 0);
    }

    function hasRestartGuidance() {
        return root.providers.some(provider => provider.restart === "session" || provider.restart === "system");
    }

    function shouldShow() {
        return root.busy || root.hasExceptionalState() || root.hasRestartGuidance()
            || root.totalUpdates > 0 || root.savedAlwaysShow;
    }

    function open() { root.visible = true; }
    function close() { root.visible = false; root.settingsMode = false; root.discardSettings(); }
    function toggle() { if (root.visible) root.close(); else root.open(); }

    function refresh(force) {
        if (scanProcess.running) {
            if (force) root.pendingForceRefresh = true;
            return false;
        }
        if (force) root.pendingForceRefresh = false;
        scanProcess.command = Commands.updateCenterCommand("snapshot", force ? ["--force"] : []);
        scanProcess.liveRequest = force;
        scanProcess.running = true;
        return true;
    }

    function scheduledRefresh() {
        if (!root.online) return false;
        return root.refresh(true);
    }

    function drainScanQueue() {
        if (!root.pendingForceRefresh || scanProcess.running || !root.online) return false;
        root.pendingForceRefresh = false;
        return root.refresh(true);
    }

    function startupElapsed() {
        startupTimer.stop();
        root.startupDelayElapsed = true;
        const started = root.scheduledRefresh();
        if (root.online) refreshTimer.start();
        else refreshTimer.stop();
        return started;
    }

    function acceptSnapshot(text) {
        const parsed = Protocol.parseSnapshot(text);
        if (parsed === null) {
            root.message = "Update provider returned an invalid snapshot";
            return false;
        }
        root.providers = parsed.providers;
        root.totalUpdates = parsed.totalUpdates;
        if (scanProcess.liveRequest) root.initialLiveScanComplete = true;
        else root.initialCacheLoaded = true;
        root.message = "";
        return true;
    }

    function reconcileOperation(text, source) {
        const parsed = Protocol.parseAction(text);
        if (parsed === null) {
            root.message = "Update operation state is unavailable";
            return false;
        }
        const previouslyActive = root.activeOperation !== null;
        root.activeOperation = parsed.operationId.length > 0 && parsed.phase !== "closed" ? parsed : null;
        operationTimer.running = root.activeOperation !== null;
        if (root.activeOperation !== null && source !== "terminal-closed")
            root.pendingTerminalClose = root.activeOperation.operationId;
        if (previouslyActive && root.activeOperation === null) {
            root.pendingTerminalClose = "";
            root.refresh(true);
        }
        return true;
    }

    function launch(providerId) { return root.dispatchOperation("launch", providerId); }
    function recover(providerId) { return root.dispatchOperation("recover", providerId); }
    function dispatchOperation(action, providerId) {
        const recoverable = root.activeOperation !== null && root.activeOperation.providerId === providerId
            && ["interrupted", "system-failed", "system-complete/user-failed"].indexOf(root.activeOperation.phase) >= 0;
        if ((root.busy && (action !== "recover" || !recoverable)) || operationProcess.running
                || ["fedora", "dwm-titus", "flatpak", "mise"].indexOf(providerId) < 0)
            return false;
        operationProcess.command = Commands.updateCenterCommand(action, [providerId]);
        operationProcess.requestKind = action;
        operationProcess.responseAccepted = false;
        operationProcess.running = true;
        root.visible = false;
        return true;
    }

    function refreshOperation() {
        if (operationProcess.running) return false;
        operationProcess.command = Commands.updateCenterCommand("active", []);
        operationProcess.requestKind = "active";
        operationProcess.responseAccepted = false;
        operationProcess.running = true;
        return true;
    }

    function reconcileTerminalClose(operationId) {
        if (operationProcess.running || !/^op-[0-9a-f]{32}$/.test(operationId)) return false;
        operationProcess.command = Commands.updateCenterCommand("terminal-closed", [operationId]);
        operationProcess.requestKind = "terminal-closed";
        operationProcess.responseAccepted = false;
        operationProcess.running = true;
        return true;
    }

    function drainOperationQueue() {
        if (operationProcess.running) return;
        if (root.pendingTerminalClose.length > 0) {
            const operationId = root.pendingTerminalClose;
            root.pendingTerminalClose = "";
            root.reconcileTerminalClose(operationId);
        } else if (operationProcess.needsAuthoritativeRefresh) {
            operationProcess.needsAuthoritativeRefresh = false;
            root.refreshOperation();
        }
    }

    function loadSettings(text) {
        const parsed = Protocol.parseSettings(text);
        if (parsed === null) {
            root.settingsError = "Update preferences are unavailable";
            return false;
        }
        root.savedRefreshSeconds = parsed.refreshSeconds;
        root.savedAlwaysShow = parsed.alwaysShow;
        root.settingsBaseline = parsed.baseline;
        root.draftRefreshSeconds = parsed.refreshSeconds;
        root.draftAlwaysShow = parsed.alwaysShow;
        refreshTimer.interval = parsed.refreshSeconds * 1000;
        root.settingsError = parsed.state === "partial" || parsed.state === "unavailable" ? parsed.detail : "";
        return true;
    }

    function refreshSettings() {
        if (settingsStatusProcess.running) {
            root.pendingSettingsReload = true;
            return false;
        }
        root.pendingSettingsReload = false;
        settingsStatusProcess.running = true;
        return true;
    }

    function drainSettingsQueue() {
        if (!root.pendingSettingsReload || settingsStatusProcess.running) return false;
        root.pendingSettingsReload = false;
        settingsStatusProcess.running = true;
        return true;
    }

    function showSettings() {
        root.settingsMode = true;
        root.discardSettings();
    }

    function discardSettings() {
        root.draftRefreshSeconds = root.savedRefreshSeconds;
        root.draftAlwaysShow = root.savedAlwaysShow;
        root.settingsError = "";
    }

    function saveSettings() {
        if (settingsActionProcess.running || !Number.isInteger(root.draftRefreshSeconds)
                || root.draftRefreshSeconds < 300 || draftRefreshSeconds > 21600) {
            root.settingsError = "Refresh interval must be an integer from 300 to 21600 seconds";
            return false;
        }
        settingsActionProcess.command = Commands.updateCenterSettingsCommand("set",
            [String(root.draftRefreshSeconds), root.draftAlwaysShow ? "enabled" : "disabled", root.settingsBaseline]);
        settingsActionProcess.running = true;
        return true;
    }

    onOnlineChanged: {
        if (!root.connectivityReady) return;
        if (online) {
            if (!root.startupDelayElapsed) return;
            root.scheduledRefresh();
            if (!startupTimer.running) refreshTimer.start();
        }
        else refreshTimer.stop();
    }

    Component.onCompleted: {
        root.refreshSettings();
        root.refreshOperation();
        root.refresh(false);
        startupTimer.start();
        root.connectivityReady = true;
    }

    Timer {
        id: startupTimer
        interval: 30000
        repeat: false
        onTriggered: root.startupElapsed()
    }

    Timer {
        id: refreshTimer
        interval: 3600000
        repeat: true
        running: false
        onTriggered: root.scheduledRefresh()
    }

    Timer {
        id: operationTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: root.refreshOperation()
    }

    Timer {
        id: scanDrainTimer
        interval: 0
        repeat: false
        onTriggered: root.drainScanQueue()
    }

    Timer {
        id: operationDrainTimer
        interval: 0
        repeat: false
        onTriggered: root.drainOperationQueue()
    }

    Timer {
        id: settingsDrainTimer
        interval: 0
        repeat: false
        onTriggered: root.drainSettingsQueue()
    }

    Process {
        id: scanProcess
        command: Commands.updateCenterCommand("snapshot", [])
        running: false
        property bool liveRequest: false
        stdout: StdioCollector { id: scanOutput }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim().length > 0) root.message = this.text.trim() }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (exitStatus === 0 && exitCode === 0) root.acceptSnapshot(scanOutput.text);
            scanDrainTimer.start();
        }
    }

    Process {
        id: operationProcess
        command: Commands.updateCenterCommand("active", [])
        running: false
        property string requestKind: "active"
        property bool responseAccepted: false
        property bool needsAuthoritativeRefresh: false
        stdout: StdioCollector { id: operationOutput }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim().length > 0) root.message = this.text.trim() }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (exitStatus === 0 && exitCode === 0)
                operationProcess.responseAccepted = root.reconcileOperation(operationOutput.text, operationProcess.requestKind);
            if ((operationProcess.requestKind === "launch" || operationProcess.requestKind === "recover")
                    && (!operationProcess.responseAccepted || exitStatus !== 0 || exitCode !== 0))
                operationProcess.needsAuthoritativeRefresh = true;
            operationDrainTimer.start();
        }
    }

    Process {
        id: settingsStatusProcess
        command: Commands.updateCenterSettingsCommand("status", [])
        running: false
        stdout: StdioCollector { id: settingsStatusOutput }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (exitStatus === 0 && exitCode === 0) root.loadSettings(settingsStatusOutput.text);
            settingsDrainTimer.start();
        }
    }

    Process {
        id: settingsActionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stderr: StdioCollector { id: settingsActionError }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (exitStatus === 0 && exitCode === 0) {
                root.refreshSettings();
            } else {
                const detail = settingsActionError.text.trim();
                root.settingsError = detail.length > 0 ? detail : "Update preferences changed; refresh and try again";
            }
        }
    }
}
