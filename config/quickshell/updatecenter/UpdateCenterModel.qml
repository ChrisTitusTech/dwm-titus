import QtQuick
import Quickshell
import Quickshell.Io
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
    property bool online: true
    property string message: ""
    property string settingsError: ""
    property int savedRefreshSeconds: 3600
    property bool savedAlwaysShow: true
    property string settingsBaseline: "absent"
    property bool initialCacheLoaded: false
    property bool initialLiveScanComplete: false
    readonly property bool busy: root.activeOperation !== null

    function hasExceptionalState() {
        return root.providers.some(provider => provider.freshness === "stale" || provider.freshness === "error"
            || provider.errorCode.length > 0 || ["partial", "restricted"].indexOf(provider.status) >= 0);
    }

    function shouldShow() {
        return root.busy || root.hasExceptionalState() || root.totalUpdates > 0 || root.savedAlwaysShow;
    }

    function open() { root.visible = true; }
    function close() { root.visible = false; root.settingsMode = false; root.discardSettings(); }
    function toggle() { if (root.visible) root.close(); else root.open(); }

    function refresh(force) {
        if (scanProcess.running) return false;
        scanProcess.command = Commands.updateCenterCommand("snapshot", force ? ["--force"] : []);
        scanProcess.liveRequest = force;
        scanProcess.running = true;
        return true;
    }

    function scheduledRefresh() {
        if (!root.online || scanProcess.running) return false;
        return root.refresh(true);
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

    function reconcileOperation(text) {
        const parsed = Protocol.parseAction(text);
        if (parsed === null) {
            root.message = "Update operation state is unavailable";
            return false;
        }
        const previouslyActive = root.activeOperation !== null;
        root.activeOperation = parsed.operationId.length > 0 ? parsed : null;
        operationTimer.running = root.activeOperation !== null;
        if (previouslyActive && root.activeOperation === null) root.refresh(true);
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
        operationProcess.running = true;
        root.visible = false;
        return true;
    }

    function refreshOperation() {
        if (operationProcess.running) return false;
        operationProcess.command = Commands.updateCenterCommand("active", []);
        operationProcess.running = true;
        return true;
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
        if (online) {
            root.scheduledRefresh();
            if (!startupTimer.running) refreshTimer.start();
        }
        else refreshTimer.stop();
    }

    Component.onCompleted: {
        settingsStatusProcess.running = true;
        root.refreshOperation();
        root.refresh(false);
        startupTimer.start();
    }

    Timer {
        id: startupTimer
        interval: 30000
        repeat: false
        onTriggered: {
            root.scheduledRefresh();
            refreshTimer.start();
        }
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

    Process {
        id: scanProcess
        command: Commands.updateCenterCommand("snapshot", [])
        running: false
        property bool liveRequest: false
        stdout: StdioCollector { onStreamFinished: root.acceptSnapshot(this.text) }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim().length > 0) root.message = this.text.trim() }
    }

    Process {
        id: operationProcess
        command: Commands.updateCenterCommand("active", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.reconcileOperation(this.text) }
        stderr: StdioCollector { onStreamFinished: if (this.text.trim().length > 0) root.message = this.text.trim() }
    }

    Process {
        id: settingsStatusProcess
        command: Commands.updateCenterSettingsCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.loadSettings(this.text) }
    }

    Process {
        id: settingsActionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stderr: StdioCollector { id: settingsActionError }
        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            if (exitStatus === 0 && exitCode === 0) {
                if (!settingsStatusProcess.running) settingsStatusProcess.running = true;
            } else {
                const detail = settingsActionError.text.trim();
                root.settingsError = detail.length > 0 ? detail : "Update preferences changed; refresh and try again";
            }
        }
    }
}
