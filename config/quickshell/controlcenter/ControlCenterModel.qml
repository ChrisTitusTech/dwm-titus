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
    property var powerRows: []
    property bool powerDpmsAvailable: false
    property bool powerDpmsEnabled: false
    property int powerDpmsTimeout: 600
    property bool powerLockAvailable: false
    property bool powerLockEnabled: false
    property bool powerLockRunning: false
    property int powerLockTimeout: 600
    property string powerConfigFile: ""

    function openPage(name, message, process) {
        root.page = name;
        root.message = message;
        if (process && !process.running) {
            process.running = true;
        }
    }

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
        root.openPage("overview", "", null);
    }

    function openHealth() {
        root.openPage("health", "Checking system health...", healthProcess);
    }

    function openActions() {
        root.openPage("actions", "", null);
    }

    function openAppearance() {
        root.openPage("appearance", "Loading themes...", themesProcess);
    }

    function openKeybinds() {
        root.visible = true;
        root.openPage("keybinds", "Loading keybinds...", keybindsProcess);
    }

    function openPower() {
        root.openPage("power", "Loading power settings...", powerStatusProcess);
    }

    function openInfo() {
        root.openPage("info", "Loading system info...", infoProcess);
    }

    function refreshCurrentPage() {
        if (root.page === "health") {
            root.openHealth();
        } else if (root.page === "appearance") {
            root.openAppearance();
        } else if (root.page === "keybinds") {
            root.openKeybinds();
        } else if (root.page === "power") {
            root.openPower();
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

    function rowValue(rows, key, fallback) {
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].key === key) {
                return rows[i].value;
            }
        }

        return fallback;
    }

    function boolValue(value) {
        return value === "1" || value === "true" || value === "yes" || value === "enabled";
    }

    function intValue(value, fallback) {
        const parsed = parseInt(value, 10);
        return isNaN(parsed) ? fallback : parsed;
    }

    function applyPowerRows(rows) {
        root.powerRows = rows;
        root.powerDpmsAvailable = root.boolValue(root.rowValue(rows, "dpms_available", "0"));
        root.powerDpmsEnabled = root.boolValue(root.rowValue(rows, "dpms_enabled", "0"));
        root.powerDpmsTimeout = root.intValue(root.rowValue(rows, "dpms_timeout", "600"), 600);
        root.powerLockAvailable = root.boolValue(root.rowValue(rows, "lock_available", "0"));
        root.powerLockEnabled = root.boolValue(root.rowValue(rows, "lock_enabled", "0"));
        root.powerLockRunning = root.boolValue(root.rowValue(rows, "lock_running", "0"));
        root.powerLockTimeout = root.intValue(root.rowValue(rows, "lock_timeout", "600"), 600);
        root.powerConfigFile = root.rowValue(rows, "config_file", "");
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

    function runPowerAction(action, args) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.message = "Updating power settings...";
        powerActionProcess.command = Commands.controlCenterHelperCommand(action, args || []);
        powerActionProcess.running = true;
    }

    function setPowerDpms(enabled) {
        root.runPowerAction("power-dpms", [enabled ? "on" : "off"]);
    }

    function setPowerDpmsTimeout(seconds) {
        root.runPowerAction("power-dpms-timeout", [seconds.toString()]);
    }

    function setPowerLock(enabled) {
        root.runPowerAction("power-lock", [enabled ? "on" : "off"]);
    }

    function setPowerLockTimeout(seconds) {
        root.runPowerAction("power-lock-timeout", [seconds.toString()]);
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
        id: powerStatusProcess

        command: Commands.controlCenterHelperCommand("power-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const rows = root.parseRows(this.text, ["key", "value"]);
                root.applyPowerRows(rows);
                root.message = "";
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

    Process {
        id: powerActionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.message = "Power settings updated";
                root.openPower();
            }
        }
    }
}
