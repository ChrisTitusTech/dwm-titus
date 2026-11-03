import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// State for the "Diagnose with AI" agents. `dwm-agent list` gives one row per
// agent; `dwm-agent status` gives the alert switches and the skills link.
// Both are read on demand (section opened, Refresh, after a change), never polled.
Scope {
    id: root

    property bool settingsVisible: false

    // The Settings window stays above other windows, so a terminal opened for
    // install or sign-in (and the browser it starts) would land behind it.
    signal terminalOpened
    property bool listLoaded: false
    property bool statusLoaded: false
    property bool refreshQueued: false
    property var agents: []
    property bool crashNotifications: true
    property bool hangDetection: false
    property string skills: "missing"
    property string message: ""
    readonly property bool loaded: root.listLoaded && root.statusLoaded
    readonly property bool reading: listProcess.running || statusProcess.running
    readonly property bool initialLoading: !root.loaded && (root.reading || root.refreshQueued)
    readonly property bool busy: root.reading || actionProcess.running

    onSettingsVisibleChanged: if (settingsVisible) root.refresh()

    function parseList(text) {
        const agents = [];
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] !== "agent" || fields.length < 7) continue;
            agents.push({
                "name": fields[1],
                "label": fields[2],
                "installed": fields[3] === "yes",
                "version": fields[4] === "-" ? "" : fields[4],
                "signedIn": fields[5],
                "isDefault": fields[6] === "yes"
            });
        }
        root.agents = agents;
    }

    function parseStatus(text) {
        let crash = true;
        let hang = false;
        let skills = "missing";
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "crash-notifications" && fields.length >= 2) crash = fields[1] !== "off";
            else if (fields[0] === "hang-detection" && fields.length >= 2) hang = fields[1] === "on";
            else if (fields[0] === "skills" && fields.length >= 2) skills = fields[1];
        }
        root.crashNotifications = crash;
        root.hangDetection = hang;
        root.skills = skills;
    }

    function refresh() {
        if (root.reading) {
            root.refreshQueued = true;
            return;
        }
        root.refreshQueued = false;
        root.message = "";
        listProcess.running = true;
        statusProcess.running = true;
    }

    function runAction(action, args) {
        if (actionProcess.running) return;
        root.message = "";
        actionProcess.command = Commands.checkedCommand(Commands.agentCommand(action, args));
        actionProcess.running = true;
    }

    function setToggle(name, enabled) {
        root.runAction("set", [name, enabled ? "on" : "off"]);
    }

    function makeDefault(name) {
        root.runAction("default", [name]);
    }

    // Install and sign-in prompt for sudo or open a browser, so they run in a
    // detached terminal. Their result shows after Refresh or reopening.
    function openTerminal(action, name) {
        root.message = "";
        Quickshell.execDetached(Commands.agentTerminalCommand(action, [name]));
        root.terminalOpened();
    }

    function readFinished() {
        if (!root.reading && root.refreshQueued) {
            Qt.callLater(function() {
                if (!root.reading) root.refresh();
            });
        }
    }

    Process {
        id: listProcess

        command: Commands.checkedCommand(Commands.agentCommand("list", []))
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseList(this.text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) root.message = error;
            }
        }

        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            root.listLoaded = true;
            if (exitCode !== 0 && root.message.length === 0)
                root.message = "Could not list the AI agents";
        }

        onRunningChanged: if (!running) root.readFinished()
    }

    Process {
        id: statusProcess

        command: Commands.checkedCommand(Commands.agentCommand("status", []))
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseStatus(this.text)
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) root.message = error;
            }
        }

        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            root.statusLoaded = true;
            if (exitCode !== 0 && root.message.length === 0)
                root.message = "Could not read the AI assistant status";
        }

        onRunningChanged: if (!running) root.readFinished()
    }

    Process {
        id: actionProcess

        running: false

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) root.message = error;
            }
        }

        onExited: (exitCode, exitStatus) => { // qmllint disable signal-handler-parameters
            const failed = exitCode !== 0;
            const error = failed && root.message.length === 0 ? "Could not change the setting" : root.message;
            root.refresh();
            if (failed) root.message = error;
        }
    }
}
