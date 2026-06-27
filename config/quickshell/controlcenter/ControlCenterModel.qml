import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string page: "overview"
    property string message: ""
    property var healthRows: []
    property var infoRows: []
    property var themeRows: []
    property var keybindRows: []

    function open() {
        root.visible = true;
        root.openOverview();
    }

    function close() {
        root.visible = false;
        root.message = "";
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh() {
        root.refreshCurrentPage();
    }

    function openOverview() {
        root.page = "overview";
        root.message = "";
    }

    function openHealth() {
        root.page = "health";
        root.message = "Checking system health...";
        if (!healthProcess.running) {
            healthProcess.running = true;
        }
    }

    function openActions() {
        root.page = "actions";
        root.message = "";
    }

    function openAppearance() {
        root.page = "appearance";
        root.message = "Loading themes...";
        if (!themesProcess.running) {
            themesProcess.running = true;
        }
    }

    function openKeybinds() {
        root.visible = true;
        root.page = "keybinds";
        root.message = "Loading keybinds...";
        if (!keybindsProcess.running) {
            keybindsProcess.running = true;
        }
    }

    function openInfo() {
        root.page = "info";
        root.message = "Loading system info...";
        if (!infoProcess.running) {
            infoProcess.running = true;
        }
    }

    function refreshCurrentPage() {
        if (root.page === "health") {
            root.openHealth();
        } else if (root.page === "appearance") {
            root.openAppearance();
        } else if (root.page === "keybinds") {
            root.openKeybinds();
        } else if (root.page === "info") {
            root.openInfo();
        }
    }

    function parseRows(text, names) {
        const rows = [];
        const lines = text.trim().split("\n");

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim().length === 0) {
                continue;
            }

            const fields = lines[i].split("\t");
            const row = {};
            for (let f = 0; f < names.length; f++) {
                row[names[f]] = fields.length > f ? fields[f] : "";
            }
            rows.push(row);
        }

        return rows;
    }

    function runAction(action) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.message = "Running " + action + "...";
        actionProcess.command = Commands.controlCenterHelperCommand("action", [action]);
        actionProcess.running = true;
    }

    function setTheme(name) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.message = "Applying " + name + "...";
        themeSetProcess.command = Commands.controlCenterHelperCommand("theme-set", [name]);
        themeSetProcess.running = true;
    }

    Process {
        id: healthProcess

        command: Commands.controlCenterHelperCommand("health")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.healthRows = root.parseRows(this.text, ["status", "label", "detail"]);
                root.message = root.healthRows.length + " checks";
            }
        }
    }

    Process {
        id: infoProcess

        command: Commands.controlCenterHelperCommand("info")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.infoRows = root.parseRows(this.text, ["label", "value"]);
                root.message = "";
            }
        }
    }

    Process {
        id: themesProcess

        command: Commands.controlCenterHelperCommand("themes")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.themeRows = root.parseRows(this.text, ["status", "name"]);
                root.message = root.themeRows.length + " themes";
            }
        }
    }

    Process {
        id: keybindsProcess

        command: Commands.controlCenterHelperCommand("keybinds")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.keybindRows = root.parseRows(this.text, ["keys", "description"]);
                root.message = root.keybindRows.length + " keybinds";
            }
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.message = "Action dispatched";
                root.refreshCurrentPage();
            }
        }
    }

    Process {
        id: themeSetProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.message = "Theme applied";
                root.openAppearance();
            }
        }
    }
}
