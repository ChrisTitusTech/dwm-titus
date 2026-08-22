import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool settingsVisible: false
    property bool busy: false
    property string providerState: "idle"
    property string providerDetail: "Default applications have not been loaded"
    property string watchState: "idle"
    property string watchDetail: "Live updates have not been checked"
    property var roles: []
    property var mimes: []
    property var candidates: []
    property var mimeCandidates: []
    property var recoveries: []
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

    function validState(value) {
        return value === "available" || value === "partial" || value === "restricted"
            || value === "unavailable";
    }

    function validDesktopId(value) {
        return typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9._+-]*\.desktop$/.test(value)
            && value.indexOf("..") < 0;
    }

    function validRole(value) {
        return value === "browser" || value === "terminal" || value === "file-manager";
    }

    function validMime(value) {
        return typeof value === "string" && /^[A-Za-z0-9.+-]+\/[A-Za-z0-9.+-]+$/.test(value);
    }

    function clearState(detail) {
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.watchState = "unavailable";
        root.watchDetail = detail;
        root.roles = [];
        root.mimes = [];
        root.candidates = [];
        root.mimeCandidates = [];
        root.recoveries = [];
    }

    function parseSnapshot(text) {
        if (root.snapshotGeneration !== root.mutationGeneration) return;
        let protocolValid = false;
        let provider = null;
        let watch = null;
        const roles = [];
        const mimes = [];
        const candidates = [];
        const mimeCandidates = [];
        const recoveries = [];

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "defaults-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "defaults" && root.validState(fields[2])
                    && fields[3] === "user-session") {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "watch" && fields.length === 4
                    && (fields[1] === "available" || fields[1] === "unavailable")
                    && fields[2] === "inotifywait") {
                watch = { "state": fields[1], "detail": fields[3] };
            } else if (fields[0] === "role" && fields.length === 7 && root.validRole(fields[1])
                    && root.validState(fields[2]) && (fields[3].length === 0 || root.validDesktopId(fields[3]))
                    && (fields[5] === "xdg-settings" || fields[5] === "xdg-mime"
                        || fields[5] === "hotkeys.toml")) {
                roles.push({ "id": fields[1], "state": fields[2], "desktopId": fields[3],
                    "label": fields[4], "provider": fields[5], "detail": fields[6] });
            } else if (fields[0] === "mime" && fields.length === 6 && root.validMime(fields[1])
                    && (fields[2] === "available" || fields[2] === "unavailable")
                    && (fields[3].length === 0 || root.validDesktopId(fields[3]))) {
                mimes.push({ "mime": fields[1], "state": fields[2], "desktopId": fields[3],
                    "label": fields[4], "detail": fields[5] });
            } else if (fields[0] === "candidate" && fields.length === 7 && root.validRole(fields[1])
                    && root.validDesktopId(fields[2])
                    && (fields[4] === "available" || fields[4] === "restricted")) {
                candidates.push({ "role": fields[1], "desktopId": fields[2], "label": fields[3],
                    "state": fields[4], "launchToken": fields[5], "detail": fields[6] });
            } else if (fields[0] === "mime-candidate" && fields.length === 6
                    && root.validMime(fields[1]) && root.validDesktopId(fields[2])
                    && (fields[4] === "available" || fields[4] === "restricted")) {
                mimeCandidates.push({ "mime": fields[1], "desktopId": fields[2], "label": fields[3],
                    "state": fields[4], "detail": fields[5] });
            } else if (fields[0] === "recovery" && fields.length === 4
                    && (root.validRole(fields[1]) || root.validMime(fields[1]))
                    && (fields[2] === "available" || fields[2] === "unavailable")) {
                recoveries.push({ "scope": fields[1], "state": fields[2], "detail": fields[3] });
            }
        }

        if (!protocolValid || provider === null) {
            root.clearState("Defaults provider returned an unsupported response");
            return;
        }
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.watchState = watch === null ? "unavailable" : watch.state;
        root.watchDetail = watch === null ? "Defaults provider returned no watch state" : watch.detail;
        root.roles = roles;
        root.mimes = mimes;
        root.candidates = candidates;
        root.mimeCandidates = mimeCandidates;
        root.recoveries = recoveries;
    }

    function messageFor(origin) {
        if (root.rejectionOrigin === origin && root.rejectionMessage.length > 0)
            return root.rejectionMessage;
        return root.mutationOrigin.length === 0 || root.mutationOrigin === origin ? root.message : "";
    }

    function openSettings() {
        root.settingsVisible = true;
        if (!watchProcess.running) watchProcess.running = true;
        root.refresh();
    }

    function closeSettings() {
        root.settingsVisible = false;
        watchSettleTimer.stop();
        watchRestartTimer.stop();
        watchProcess.running = false;
        snapshotProcess.running = false;
        root.snapshotPending = false;
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

    function runAction(action, scope, desktopId, origin) {
        if (root.busy || actionProcess.running) {
            root.rejectionOrigin = origin || "settings";
            root.rejectionMessage = "Another Defaults change is already in progress";
            return;
        }
        if ((action === "set-role" && (!root.validRole(scope) || !root.validDesktopId(desktopId)))
                || (action === "set-mime" && (!root.validMime(scope) || !root.validDesktopId(desktopId)))
                || (action === "reset-role" && !root.validRole(scope))
                || (action === "reset-mime" && !root.validMime(scope))) return;
        const args = action.indexOf("set-") === 0 ? [scope, desktopId] : [scope];
        root.mutationGeneration++;
        root.actionGeneration = root.mutationGeneration;
        root.mutationOrigin = origin || "settings";
        if (root.rejectionOrigin === root.mutationOrigin) {
            root.rejectionOrigin = "";
            root.rejectionMessage = "";
        }
        root.message = "Applying Defaults change...";
        root.actionError = "";
        root.actionSucceeded = false;
        actionProcess.expectedResult = ["defaults-result", "1", "0", action, scope,
            desktopId || "", "ok"].join("\t");
        actionProcess.command = Commands.checkedCommand(Commands.defaultsHelperCommand(action, args));
        root.busy = true;
        actionProcess.running = true;
    }

    function setRole(role, desktopId, origin) { root.runAction("set-role", role, desktopId, origin); }
    function setMime(mime, desktopId, origin) { root.runAction("set-mime", mime, desktopId, origin); }
    function resetRole(role, origin) { root.runAction("reset-role", role, "", origin); }
    function resetMime(mime, origin) { root.runAction("reset-mime", mime, "", origin); }

    Process {
        id: snapshotProcess
        command: Commands.defaultsHelperCommand("snapshot", [])
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
        command: Commands.defaultsHelperCommand("watch", [])
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
        property string expectedResult: ""
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.actionGeneration !== root.mutationGeneration) return;
                root.actionSucceeded = this.text.trim() === actionProcess.expectedResult;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (root.actionGeneration === root.mutationGeneration) root.actionError = this.text.trim();
            }
        }
        onRunningChanged: {
            if (running || root.actionGeneration !== root.mutationGeneration) return;
            root.busy = false;
            root.message = root.actionSucceeded ? "Defaults updated"
                : (root.actionError.length > 0 ? root.actionError
                    : "Defaults helper did not confirm the requested change");
            if (root.settingsVisible) root.refresh();
        }
    }
}
