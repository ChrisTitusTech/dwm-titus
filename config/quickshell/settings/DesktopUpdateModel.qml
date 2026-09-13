import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool settingsVisible: false
    property bool systemBusy: false
    property bool confirming: false
    property bool dispatching: false
    property bool commandPending: false
    property string confirmedRevision: ""
    property string commandError: ""
    property var status: ({ schema: 1, state: "unknown", detail: "Check for desktop updates",
        canUpdate: false, installed: "unknown", available: "unknown", checkedAt: 0,
        percent: -1, packages: [], log: "", backup: "", restart: "none" })
    readonly property bool active: ["starting", "downloading", "dependencies", "building", "backing-up",
        "installing", "verifying", "activating"].indexOf(status.state) >= 0
    readonly property bool busy: commandPending || command.running || dispatching || active || status.state === "checking"
    readonly property bool updateOwned: active || confirming || dispatching || status.state === "interrupted"
    readonly property bool canUpdate: status.canUpdate && !busy && !systemBusy
    readonly property string statusPath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/dwm-titus/desktop-update/status.json"

    function accept(text) {
        try {
            const value = JSON.parse(text);
            if (value.schema !== 1 || typeof value.state !== "string" || typeof value.detail !== "string"
                || typeof value.canUpdate !== "boolean" || typeof value.installed !== "string"
                || typeof value.available !== "string" || typeof value.checkedAt !== "number"
                || typeof value.percent !== "number" || value.percent < -1 || value.percent > 100
                || !Array.isArray(value.packages) || typeof value.log !== "string"
                || typeof value.backup !== "string") throw new Error("Malformed desktop update status");
            root.status = value;
            if (root.confirming && (!value.canUpdate || value.available !== root.confirmedRevision))
                root.confirming = false;
        } catch (error) {
            root.confirming = false;
            root.status = Object.assign({}, root.status, { state: "failed", canUpdate: false });
            root.commandError = "Desktop update status could not be read. Check again to recover.";
        }
    }

    function check(force) {
        if (root.busy || root.confirming) return;
        root.commandError = "";
        root.commandPending = true;
        command.command = ["dwm-desktop-update", "check"].concat(force ? ["--force"] : []);
        command.running = true;
    }

    function prepare() {
        if (!root.canUpdate) return;
        root.confirmedRevision = root.status.available;
        root.confirming = true;
    }

    function confirm() {
        if (!root.confirming || !root.canUpdate || root.confirmedRevision !== root.status.available) return;
        root.confirming = false;
        root.commandError = "";
        root.dispatching = true;
        root.commandPending = true;
        command.command = ["dwm-desktop-update", "start", root.confirmedRevision];
        command.running = true;
    }

    onSettingsVisibleChanged: {
        if (settingsVisible) {
            stateFile.reload();
            // status reconciles a worker interrupted while the shell was closed.
            if (!command.running && !root.commandPending) {
                root.commandPending = true;
                command.command = ["dwm-desktop-update", "status"];
                command.running = true;
            }
        } else root.confirming = false;
    }

    FileView {
        id: stateFile
        path: root.statusPath
        watchChanges: root.settingsVisible || root.active
        printErrors: false
        onLoaded: root.accept(text())
        onFileChanged: reload()
    }

    Timer {
        // A one-shot command deadline, not a discovery or progress poll.
        interval: 75000
        running: root.commandPending
        onTriggered: {
            command.running = false;
            root.dispatching = false;
            root.commandPending = false;
            root.commandError = "Desktop update command timed out. Reopen System to recover the saved operation.";
            stateFile.reload();
        }
    }

    Process {
        id: command
        property string output: ""
        property string errors: ""
        onStarted: { output = ""; errors = ""; }
        stdout: StdioCollector { onStreamFinished: command.output = text }
        stderr: StdioCollector { onStreamFinished: command.errors = text }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 || exitStatus !== 0)
                root.commandError = command.errors.trim() || "Desktop updater unavailable. Run the source installer once to enable it.";
            else {
                root.commandError = "";
                root.accept(command.output);
            }
            root.dispatching = false;
            root.commandPending = false;
            stateFile.reload();
            if (command.command[1] === "status" && exitCode === 0 && root.settingsVisible
                && !root.active && root.status.state !== "interrupted") Qt.callLater(() => root.check(false));
        }
    }
}
