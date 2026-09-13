import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

pragma ComponentBehavior: Bound

Scope {
    id: root
    property bool active: false
    property bool pending: false
    property bool busy: false
    property string message: ""
    property string statusFailure: ""
    property string watchFailure: ""
    property string actionFailure: ""
    readonly property string failure: actionFailure || statusFailure || watchFailure
    property var snapshot: ({ protocol: 1, editable: false, installed: false,
        active: 100, inactive: 100, policy: "auto", effective: "", override: "",
        revision: "", path: "", detail: "Loading Picom configuration", copyable: false })
    property var actionArguments: []
    property string action: "status"
    readonly property bool editable: root.snapshot.editable && !root.busy

    function accept(text) {
        const value = JSON.parse(text);
        if (value.protocol !== 1 || typeof value.editable !== "boolean"
                || typeof value.revision !== "string" || typeof value.detail !== "string"
                || typeof value.path !== "string" || typeof value.override !== "string"
                || !Number.isFinite(value.active) || !Number.isFinite(value.inactive)
                || value.active < 0 || value.active > 100 || value.inactive < 0 || value.inactive > 100
                || ["auto", "xrender", "glx", "egl"].indexOf(value.policy) < 0)
            throw new Error("Invalid Picom settings response");
        root.snapshot = value;
    }

    function refresh() {
        if (!root.active) return;
        if (root.busy || statusProcess.running) {
            root.pending = true;
            return;
        }
        root.pending = false;
        statusProcess.running = true;
    }

    function mutate(action, args) {
        if (!root.editable && action !== "copy-config") return;
        if (root.busy) return;
        root.action = action;
        root.actionArguments = args.concat([root.snapshot.revision]);
        root.busy = true;
        root.message = "";
        root.actionFailure = "";
        actionProcess.running = true;
    }

    function setOpacity(active, inactive) {
        root.mutate("set-opacity", [String(active), String(inactive)]);
    }

    onActiveChanged: {
        if (active) root.refresh();
        else {
            statusProcess.running = false;
            root.pending = false;
            settle.stop();
        }
    }

    Process {
        id: statusProcess
        command: Commands.helperCommand("dwm-settings-picom", "status", [], true)
        stdout: StdioCollector { id: statusOutput }
        stderr: StdioCollector { id: statusError }
        onExited: (exitCode, exitStatus) => {
            if (!root.active) return;
            if (!root.busy) {
                try {
                    if (exitCode !== 0 || exitStatus !== 0) throw new Error(statusError.text || "Picom status failed");
                    root.accept(statusOutput.text);
                    root.statusFailure = "";
                } catch (error) { root.statusFailure = String(error); }
            } else root.pending = true;
            if (root.pending && !root.busy) settle.restart();
        }
    }

    Process {
        id: actionProcess
        command: Commands.helperCommand("dwm-settings-picom", root.action, root.actionArguments, true)
        stdout: StdioCollector { id: actionOutput }
        stderr: StdioCollector { id: actionError }
        onExited: (exitCode, exitStatus) => {
            try {
                if (exitCode !== 0 || exitStatus !== 0) throw new Error(actionError.text || "Picom change failed");
                root.accept(actionOutput.text);
                root.message = root.snapshot.message || "Picom configuration saved";
            } catch (error) { root.actionFailure = String(error); }
            root.busy = false;
            root.refresh();
        }
    }

    Process {
        id: watcher
        command: Commands.helperCommand("dwm-settings-picom", "watch", [], true)
        running: root.active
        stdout: SplitParser {
            onRead: data => {
                if (data === "ready") root.watchFailure = "";
                if (data === "changed" || data === "ready") settle.restart();
            }
        }
        stderr: StdioCollector { id: watchError }
        onExited: (exitCode, exitStatus) => {
            if (root.active && (exitCode !== 0 || exitStatus !== 0))
                root.watchFailure = watchError.text || "Live Picom updates unavailable; use Refresh";
        }
    }

    Timer {
        id: settle
        interval: 150
        onTriggered: root.refresh()
    }
}
