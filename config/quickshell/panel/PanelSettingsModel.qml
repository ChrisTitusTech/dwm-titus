import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    readonly property bool initialLoading: statusProcess.running || root.refreshPending

    property string providerState: "idle"
    property string providerDetail: "Loading panel settings"
    property bool busy: false
    property string message: ""
    property string pendingWidget: ""
    property string pendingValue: ""
    property bool statusParsed: false
    property bool refreshPending: false
    property bool mutationRefreshPending: false
    property bool actionSucceeded: false
    property var values: ({
        "workspaces": true,
        "volume": true,
        "bluetooth": true,
        "network": true,
        "power": true,
        "keyboard-layout": true
    })
    property var optionValues: ({
        "clock-seconds": false
    })
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME")
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configPath: root.configHome + "/dwm-titus/panel-widgets.conf"
    readonly property bool mutationReady: root.providerState !== "unavailable"
    readonly property var widgets: [
        { "id": "workspaces", "label": "Workspaces" },
        { "id": "volume", "label": "Volume" },
        { "id": "bluetooth", "label": "Bluetooth" },
        { "id": "network", "label": "Network" },
        { "id": "power", "label": "Power" },
        { "id": "keyboard-layout", "label": "Keyboard layout" }
    ]
    readonly property var options: [
        { "id": "clock-seconds", "label": "Clock: show seconds" }
    ]

    function validWidget(id) {
        return id === "workspaces" || id === "volume" || id === "bluetooth"
            || id === "network" || id === "power" || id === "keyboard-layout";
    }

    function widgetEnabled(id) {
        return root.validWidget(id) ? root.values[id] !== false : true;
    }

    function validOption(id) {
        return id === "clock-seconds";
    }

    function optionEnabled(id) {
        return root.validOption(id) && root.optionValues[id] === true;
    }

    function useDefaults() {
        root.values = ({
            "workspaces": true,
            "volume": true,
            "bluetooth": true,
            "network": true,
            "power": true,
            "keyboard-layout": true
        });
        root.optionValues = ({
            "clock-seconds": false
        });
    }

    function refresh() {
        if (statusProcess.running) {
            root.refreshPending = true;
            return;
        }
        root.refreshPending = false;
        root.statusParsed = false;
        statusProcess.running = true;
    }

    function parseStatus(text) {
        const lines = text.trim().split("\n");
        // 1.1 adds one option line before "complete"; 1.0 has none.
        const optionCount = lines[0] === "panel-settings-protocol\t1\t1" ? root.options.length
            : lines[0] === "panel-settings-protocol\t1\t0" ? 0 : -1;
        if (optionCount < 0 || lines.length < 8 + optionCount
                || lines[lines.length - 1] !== "complete\tstatus") return;
        const state = lines[1].split("\t");
        if (state.length !== 3 || state[0] !== "state"
                || ["available", "defaults", "partial", "unavailable"].indexOf(state[1]) < 0)
            return;
        // Widget lines run up to the options. A helper from before
        // keyboard-layout prints only the other five; it then stays on.
        const parsed = {};
        let index = 2;
        for (; index < lines.length - 1 - optionCount; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 3 || fields[0] !== "widget" || !root.validWidget(fields[1])
                    || (fields[2] !== "enabled" && fields[2] !== "disabled")
                    || parsed[fields[1]] !== undefined) return;
            parsed[fields[1]] = fields[2] === "enabled";
        }
        if (parsed["keyboard-layout"] === undefined) parsed["keyboard-layout"] = true;
        for (const widget of root.widgets) {
            if (parsed[widget.id] === undefined) return;
        }
        const parsedOptions = { "clock-seconds": false };
        const seenOptions = {};
        for (; index < lines.length - 1; index++) {
            const fields = lines[index].split("\t");
            if (fields.length !== 3 || fields[0] !== "option" || !root.validOption(fields[1])
                    || (fields[2] !== "enabled" && fields[2] !== "disabled")
                    || seenOptions[fields[1]] !== undefined) return;
            seenOptions[fields[1]] = true;
            parsedOptions[fields[1]] = fields[2] === "enabled";
        }
        root.values = parsed;
        root.optionValues = parsedOptions;
        root.providerState = state[1];
        root.providerDetail = state[2];
        root.statusParsed = true;
    }

    function setWidget(id, enabled) {
        if ((!root.validWidget(id) && !root.validOption(id)) || root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = id;
        root.pendingValue = enabled ? "enabled" : "disabled";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(
            Commands.panelSettingsCommand("set", [id, root.pendingValue]));
        actionProcess.running = true;
    }

    function toggleWidget(id) {
        root.setWidget(id, !root.widgetEnabled(id));
    }

    function toggleOption(id) {
        if (root.validOption(id)) root.setWidget(id, !root.optionEnabled(id));
    }

    function reset() {
        if (root.busy || !root.mutationReady) return;
        root.busy = true;
        root.pendingWidget = "all";
        root.pendingValue = "enabled";
        root.actionSucceeded = false;
        actionProcess.command = Commands.checkedCommand(Commands.panelSettingsCommand("reset", []));
        actionProcess.running = true;
    }

    function parseAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "panel-settings-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (fields.length !== 4 || fields[0] !== "result") return;
        if (fields[1] === "set")
            root.actionSucceeded = fields[2] === root.pendingWidget
                && fields[3] === root.pendingValue;
        else if (fields[1] === "reset")
            root.actionSucceeded = root.pendingWidget === "all"
                && fields[2] === "all" && fields[3] === "enabled";
    }

    Component.onCompleted: root.refresh()

    FileView {
        id: configWatch
        path: root.configPath
        watchChanges: true
        printErrors: false
        onLoaded: settleTimer.restart()
        onLoadFailed: settleTimer.restart()
        onFileChanged: reload()
    }

    Timer {
        id: settleTimer
        interval: 75
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: statusProcess
        command: Commands.panelSettingsCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseStatus(this.text) }
        stderr: StdioCollector { id: statusError }
        onRunningChanged: if (!running) {
            if (!root.statusParsed) {
                root.useDefaults();
                root.providerState = "unavailable";
                root.providerDetail = statusError.text.trim().length > 0
                    ? statusError.text.trim() : "Panel settings provider returned invalid data";
            }
            if (root.refreshPending) {
                Qt.callLater(root.refresh);
            } else if (root.mutationRefreshPending) {
                root.mutationRefreshPending = false;
                root.busy = false;
            }
        }
    }

    Process {
        id: actionProcess
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAction(this.text) }
        stderr: StdioCollector { id: actionError }
        onRunningChanged: if (!running && root.busy) {
            root.message = root.actionSucceeded ? "Panel visibility updated"
                : actionError.text.trim().length > 0 ? actionError.text.trim()
                : "Panel settings helper did not confirm the change";
            root.mutationRefreshPending = true;
            Qt.callLater(root.refresh);
        }
    }
}
