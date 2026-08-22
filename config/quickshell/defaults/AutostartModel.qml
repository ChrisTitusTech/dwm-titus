import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool settingsVisible: false
    property bool busy: false
    property string providerState: "idle"
    property string providerDetail: "Autostart entries have not been loaded"
    property var entries: []
    property string searchQuery: ""
    property bool confirming: false
    property var pendingEntry: null
    property string pendingAction: ""
    property string pendingState: ""
    property string pendingOrigin: ""
    property string mutationOrigin: ""
    property string message: ""
    property string rejectionOrigin: ""
    property string rejectionMessage: ""
    property string actionError: ""
    property bool actionSucceeded: false
    property int mutationGeneration: 0
    property int actionGeneration: 0
    property int snapshotGeneration: 0
    property bool snapshotPending: false

    readonly property var filteredEntries: {
        const query = root.searchQuery.trim().toLowerCase();
        if (query.length === 0) return root.entries;
        return root.entries.filter(function(entry) {
            return entry.id.toLowerCase().indexOf(query) >= 0
                || entry.name.toLowerCase().indexOf(query) >= 0
                || entry.origin.toLowerCase().indexOf(query) >= 0;
        });
    }

    function validDesktopId(value) {
        return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._-]*\.desktop$/.test(value)
            && value.indexOf("..") < 0;
    }

    function validRevision(value) {
        return typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
    }

    function validEffectiveState(value) {
        return value === "enabled" || value === "disabled" || value === "non-applicable"
            || value === "conditional" || value === "unsupported" || value === "malformed";
    }

    function resultStateMatches(requested, effective) {
        if (requested === "enabled")
            return effective === "enabled" || effective === "conditional";
        if (requested === "disabled")
            return effective === "disabled" || effective === "non-applicable";
        return requested.length === 0;
    }

    function clearState(detail) {
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.entries = [];
    }

    function parseSnapshot(text) {
        if (root.snapshotGeneration !== root.mutationGeneration) return;
        let protocolValid = false;
        let provider = null;
        const entries = [];
        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "autostart-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 3
                    && (fields[1] === "ready" || fields[1] === "degraded"
                        || fields[1] === "unavailable")) {
                provider = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "entry" && fields.length === 14
                    && root.validDesktopId(fields[1])
                    && (fields[3] === "vendor" || fields[3] === "user-override"
                        || fields[3] === "user-only")
                    && root.validEffectiveState(fields[4])
                    && (fields[5] === "visible" || fields[5] === "hidden"
                        || fields[5] === "not-shown" || fields[5] === "conditional"
                        || fields[5] === "unknown")
                    && (fields[6] === "0" || fields[6] === "1")
                    && (fields[7] === "0" || fields[7] === "1")
                    && (fields[8] === "0" || fields[8] === "1")
                    && (fields[9] === "normal" || fields[9] === "session-critical")
                    && root.validRevision(fields[10])
                    && (fields[11] === "0" || fields[11] === "1")
                    && (fields[12] === "0" || fields[12] === "1")) {
                entries.push({ "id": fields[1], "name": fields[2], "origin": fields[3],
                    "state": fields[4], "visibility": fields[5], "userPresent": fields[6] === "1",
                    "vendorPresent": fields[7] === "1", "canReset": fields[8] === "1",
                    "risk": fields[9], "revision": fields[10],
                    "canEnable": fields[11] === "1", "canDisable": fields[12] === "1",
                    "detail": fields[13] });
            }
        }
        if (!protocolValid || provider === null) {
            root.clearState("Autostart provider returned an unsupported response");
            return;
        }
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.entries = entries;
    }

    function messageFor(origin) {
        if (root.rejectionOrigin === origin && root.rejectionMessage.length > 0)
            return root.rejectionMessage;
        return root.mutationOrigin.length === 0 || root.mutationOrigin === origin ? root.message : "";
    }

    function setSearch(value) { root.searchQuery = value; }

    function openSettings() {
        root.settingsVisible = true;
        if (!watchProcess.running) watchProcess.running = true;
        root.refresh();
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.cancelConfirmation("settings");
        watchSettleTimer.stop();
        watchRestartTimer.stop();
        watchProcess.running = false;
        snapshotProcess.running = false;
        root.snapshotPending = false;
        root.searchQuery = "";
    }

    function refresh() {
        if (!root.settingsVisible) return;
        if (snapshotProcess.running) {
            root.snapshotPending = true;
            return;
        }
        root.snapshotPending = false;
        root.snapshotGeneration = root.mutationGeneration;
        snapshotProcess.running = true;
    }

    function requestSet(entry, state, origin) {
        if (!entry || (state !== "enabled" && state !== "disabled")) return;
        root.requestAction("set", entry, state, origin);
    }

    function requestReset(entry, origin) {
        if (!entry || !entry.canReset) return;
        root.requestAction("reset", entry, "", origin);
    }

    function requestAction(action, entry, state, origin) {
        const source = origin || "settings";
        if (!entry || !root.validDesktopId(entry.id) || !root.validRevision(entry.revision)
                || (action !== "set" && action !== "reset")
                || (action === "set" && state !== "enabled" && state !== "disabled")
                || (action === "reset" && !entry.canReset)) {
            root.rejectionOrigin = source;
            root.rejectionMessage = "The requested autostart change is no longer available";
            return;
        }
        if (root.confirming) {
            root.rejectionOrigin = source;
            root.rejectionMessage = "Finish or cancel the pending autostart confirmation first";
            return;
        }
        if (root.busy || actionProcess.running) {
            root.rejectionOrigin = source;
            root.rejectionMessage = "Another autostart change is already in progress";
            return;
        }
        if (entry.risk === "session-critical") {
            root.confirming = true;
            root.pendingAction = action;
            root.pendingEntry = entry;
            root.pendingState = state;
            root.pendingOrigin = source;
            return;
        }
        root.runAction(action, entry, state, source, false);
    }

    function cancelConfirmation(origin) {
        if (!root.confirming || (origin && root.pendingOrigin !== origin)) return;
        root.confirming = false;
        root.pendingAction = "";
        root.pendingEntry = null;
        root.pendingState = "";
        root.pendingOrigin = "";
    }

    function confirmAction(origin) {
        if (!root.confirming || root.pendingEntry === null || root.pendingOrigin !== origin) return;
        const action = root.pendingAction;
        const entry = root.pendingEntry;
        const state = root.pendingState;
        const owner = root.pendingOrigin;
        root.cancelConfirmation(owner);
        root.runAction(action, entry, state, owner, true);
    }

    function runAction(action, entry, state, origin, confirmed) {
        const args = action === "set" ? [entry.id, state, entry.revision] : [entry.id, entry.revision];
        if (confirmed) args.push("confirm-session-critical");
        root.mutationGeneration++;
        root.actionGeneration = root.mutationGeneration;
        root.mutationOrigin = origin;
        if (root.rejectionOrigin === root.mutationOrigin) {
            root.rejectionOrigin = "";
            root.rejectionMessage = "";
        }
        root.message = "Applying autostart change for next login...";
        root.actionError = "";
        root.actionSucceeded = false;
        actionProcess.expectedAction = action;
        actionProcess.expectedDesktopId = entry.id;
        actionProcess.expectedState = action === "set" ? state : "";
        actionProcess.command = Commands.checkedCommand(Commands.autostartHelperCommand(action, args));
        root.busy = true;
        actionProcess.running = true;
    }

    function parseActionResult(text) {
        if (root.actionGeneration !== root.mutationGeneration) return;
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "autostart-protocol\t1\t0") {
            root.actionSucceeded = false;
            return;
        }
        const fields = lines[1].split("\t");
        root.actionSucceeded = fields.length === 8 && fields[0] === "action"
            && fields[1] === "success" && fields[2] === actionProcess.expectedAction
            && fields[3] === actionProcess.expectedDesktopId
            && root.validEffectiveState(fields[4]) && root.validRevision(fields[5])
            && root.resultStateMatches(actionProcess.expectedState, fields[4]);
    }

    Process {
        id: snapshotProcess
        command: Commands.autostartHelperCommand("snapshot", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSnapshot(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0 && root.snapshotGeneration === root.mutationGeneration)
                    root.clearState(error);
            }
        }
        onRunningChanged: {
            if (!running && root.snapshotPending && root.settingsVisible) {
                root.snapshotPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: watchProcess
        command: Commands.autostartHelperCommand("watch", [])
        running: false
        stdout: SplitParser { onRead: watchSettleTimer.restart() }
        onRunningChanged: {
            if (!running && root.settingsVisible) watchRestartTimer.restart();
        }
    }

    Timer {
        id: watchSettleTimer
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: watchRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.settingsVisible && !watchProcess.running) watchProcess.running = true;
        }
    }

    Process {
        id: actionProcess
        property string expectedAction: ""
        property string expectedDesktopId: ""
        property string expectedState: ""
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseActionResult(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                if (root.actionGeneration === root.mutationGeneration) root.actionError = this.text.trim();
            }
        }
        onRunningChanged: {
            if (running || root.actionGeneration !== root.mutationGeneration) return;
            root.busy = false;
            root.message = root.actionSucceeded ? "Autostart change saved for next login"
                : (root.actionError.length > 0 ? root.actionError
                    : "Autostart helper did not confirm the requested change");
            if (root.settingsVisible) root.refresh();
        }
    }
}
