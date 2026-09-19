import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property bool settingsVisible: false
    property bool backgroundMonitor: false
    property bool progressPending: false
    property string progressError: ""
    property bool systemBusy: false
    property bool confirming: false
    property bool dispatching: false
    property bool commandPending: false
    property bool initialCheckQueued: false
    readonly property bool initialLoading: commandPending || command.running || terminating || initialCheckQueued
    property bool terminating: false
    property string confirmedRevision: ""
    property string commandError: ""
    property double statusCheckedAt: 0
    property bool discoverAfterStatus: false
    signal authorizationRequested()
    property var status: ({ schema: 1, state: "unknown", detail: "Check for desktop updates",
        canUpdate: false, installed: "unknown", available: "unknown", checkedAt: 0,
        percent: -1, packages: [], log: "", backup: "", restart: "none" })
    readonly property bool active: ["starting", "downloading", "dependencies", "building", "backing-up",
        "installing", "verifying", "activating", "recovering"].indexOf(status.state) >= 0
    readonly property string authorization: active && typeof status.authorization === "string" ? status.authorization : ""
    readonly property bool busy: commandPending || command.running || terminating || dispatching || active || status.state === "checking"
    readonly property bool updateOwned: active || confirming || dispatching || status.state === "interrupted"
    readonly property bool canUpdate: status.canUpdate && !busy && !systemBusy
    readonly property string statusPath: (Quickshell.env("XDG_STATE_HOME")
        || Quickshell.env("HOME") + "/.local/state") + "/dwm-titus/desktop-update/status.json"

    // Validate installation ownership before executing any updater command.
    readonly property string updaterBootstrap: [
        "import json, os, stat, sys",
        "from pathlib import Path",
        "def trusted(path, directory=False):",
        "    if not path.is_absolute() or path.resolve() != path:",
        "        raise ValueError(\"Unsafe updater path\")",
        "    for entry in (path, *path.parents):",
        "        info = entry.lstat()",
        "        if info.st_uid != 0 or info.st_mode & 0o022:",
        "            raise ValueError(\"Untrusted updater installation\")",
        "        if entry == path and not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):",
        "            raise ValueError(\"Invalid updater file\")",
        "        if entry != path and not stat.S_ISDIR(info.st_mode):",
        "            raise ValueError(\"Invalid updater directory\")",
        "paths = os.environ.get(\"PATH\", \"\").split(\":\") + [\"/usr/local/bin\", \"/usr/bin\"]",
        "for directory in dict.fromkeys(paths):",
        "    worker = Path(directory) / \"dwm-desktop-update\"",
        "    try:",
        "        trusted(worker)",
        "        if not worker.stat().st_mode & 0o111:",
        "            continue",
        "        prefix = worker.parent.parent",
        "        manifest = prefix / \"share/dwm-titus/desktop-install.json\"",
        "        trusted(manifest)",
        "        trusted(prefix / \"libexec/dwm-titus/dwm-desktop-update-root\")",
        "        if json.loads(manifest.read_text())[\"layout\"][\"prefix\"] != str(prefix):",
        "            continue",
        "    except (OSError, ValueError, KeyError, TypeError):",
        "        continue",
        "    search = []",
        "    for command_dir in dict.fromkeys((worker.parent, Path(\"/usr/bin\"), Path(\"/usr/local/bin\"))):",
        "        try:",
        "            trusted(command_dir, directory=True)",
        "            search.append(str(command_dir))",
        "        except (OSError, ValueError):",
        "            continue",
        "    os.environ[\"PATH\"] = \":\".join(search)",
        "    os.execv(\"/usr/bin/python3\", [\"/usr/bin/python3\", \"-I\", str(worker), *sys.argv[1:]])",
        "sys.exit(\"Trusted desktop updater unavailable. Run the source installer once to enable it.\")",
    ].join("\n")
    readonly property var updaterCommand: ["/usr/bin/python3", "-I", "-c", updaterBootstrap]

    function accept(text) {
        try {
            const value = JSON.parse(text);
            if (value.schema !== 1 || typeof value.state !== "string" || typeof value.detail !== "string"
                || typeof value.canUpdate !== "boolean" || typeof value.installed !== "string"
                || typeof value.available !== "string" || typeof value.checkedAt !== "number"
                || typeof value.percent !== "number" || value.percent < -1 || value.percent > 100
                || !Array.isArray(value.packages) || typeof value.log !== "string"
                || typeof value.backup !== "string") throw new Error("Malformed desktop update status");
            const previousAuthorization = root.authorization;
            root.status = value;
            if (root.authorization.length > 0 && root.authorization !== previousAuthorization)
                root.authorizationRequested();
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
        command.command = root.updaterCommand.concat(["check"], force ? ["--force"] : []);
        command.running = true;
    }

    function refreshStatus(discover) {
        // Opening Settings during the background startup read must still discover
        // updates when that same read completes.
        if (discover === true && root.commandPending
            && command.command[root.updaterCommand.length] === "status") root.discoverAfterStatus = true;
        if (command.running || root.commandPending || root.terminating || root.dispatching || root.confirming) return;
        root.commandError = "";
        root.discoverAfterStatus = discover === true;
        root.commandPending = true;
        command.command = root.updaterCommand.concat(["status"]);
        command.running = true;
    }

    function expireCommand() {
        root.terminating = true;
        root.dispatching = false;
        root.commandPending = false;
        root.commandError = "Desktop update command timed out. Reopen System to recover the saved operation.";
        command.running = false;
        stateFile.reload();
    }

    function prepare() {
        if (!root.canUpdate) return;
        root.confirmedRevision = root.status.available;
        root.confirming = true;
    }

    function showProgress() {
        if (progressCommand.running || root.progressPending) return;
        root.progressError = "";
        root.progressPending = true;
        progressCommand.running = true;
    }

    function confirm() {
        if (!root.confirming || !root.canUpdate || root.confirmedRevision !== root.status.available) return;
        root.confirming = false;
        root.commandError = "";
        root.dispatching = true;
        root.commandPending = true;
        command.command = root.updaterCommand.concat(["start", root.confirmedRevision]);
        command.running = true;
    }

    Component.onCompleted: { if (root.backgroundMonitor) root.refreshStatus(false); }

    onSettingsVisibleChanged: {
        if (settingsVisible) {
            stateFile.reload();
            // status reconciles a worker interrupted while the shell was closed.
            root.refreshStatus(true);
        } else root.confirming = false;
    }

    FileView {
        id: stateFile
        path: root.statusPath
        watchChanges: root.backgroundMonitor || root.settingsVisible || root.active
        printErrors: false
        onLoaded: root.accept(text())
        onFileChanged: reload()
    }

    Process {
        id: progressCommand
        command: root.updaterCommand.concat(["progress"])
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.progressError = text.trim(); } }
        onExited: (exitCode, exitStatus) => {
            root.progressPending = false;
            if ((exitCode !== 0 || exitStatus !== 0) && !root.progressError)
                root.progressError = "Progress window unavailable. Follow the update here.";
        }
    }

    Timer {
        interval: 10000
        running: root.progressPending
        onTriggered: {
            progressCommand.running = false;
            root.progressPending = false;
            root.progressError = "Progress window did not open. Follow the update here.";
        }
    }

    Timer {
        // A one-shot command deadline, not a discovery or progress poll.
        interval: 75000
        running: root.commandPending
        onTriggered: root.expireCommand()
    }

    Process {
        id: command
        property string output: ""
        property string errors: ""
        onStarted: { output = ""; errors = ""; }
        stdout: StdioCollector { onStreamFinished: command.output = text }
        stderr: StdioCollector { onStreamFinished: command.errors = text }
        onExited: (exitCode, exitStatus) => {
            if (root.terminating) {
                root.terminating = false;
                stateFile.reload();
                return;
            }
            if (exitCode !== 0 || exitStatus !== 0)
                root.commandError = command.errors.trim() || "Desktop updater unavailable. Run the source installer once to enable it.";
            else {
                root.commandError = "";
                root.accept(command.output);
                if (command.command[root.updaterCommand.length] === "status") root.statusCheckedAt = Date.now();
            }
            if (root.dispatching && exitCode === 0 && exitStatus === 0) root.showProgress();
            root.dispatching = false;
            root.initialCheckQueued = command.command[root.updaterCommand.length] === "status" && root.discoverAfterStatus
                && exitCode === 0 && root.settingsVisible
                && !root.active && root.status.state !== "interrupted";
            root.commandPending = false;
            stateFile.reload();
            if (root.initialCheckQueued) Qt.callLater(() => {
                root.check(false);
                root.initialCheckQueued = false;
            });
        }
    }
}
