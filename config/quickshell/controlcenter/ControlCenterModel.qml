import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string page: "overview"
    property bool utilityVisible: false
    property string utilityPage: ""
    property string barColorSelection: "Accent"
    property bool showVolumeWidget: true
    property bool showBluetoothWidget: true
    property bool showNetworkWidget: true
    property bool showPowerWidget: true
    property bool showWorkspaceWidget: true
    property string message: ""
    property var healthRows: []
    property var infoRows: []
    property var themeRows: []
    property var keybindRows: []
    readonly property var actions: [
        { "id": "restart-picom", "label": "Restart Picom" },
        { "id": "restart-quickshell", "label": "Restart Quickshell" },
        { "id": "reload-wallpaper", "label": "Reload Wallpaper" },
        { "id": "restart-networkmanager", "label": "Restart NetworkManager" },
        { "id": "dependency-check", "label": "Dependency Check" },
        { "id": "install-missing-deps", "label": "Install Missing Deps" },
        { "id": "open-wallpapers", "label": "Wallpaper Folder" },
        { "id": "gtk-settings", "label": "GTK Settings" }
    ]

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

    function closeUtility() {
        root.utilityVisible = false;
        root.utilityPage = "";
        root.message = "";
    }

    function widgetEnabled(name) {
        if (name === "Volume") return root.showVolumeWidget;
        if (name === "Bluetooth") return root.showBluetoothWidget;
        if (name === "Network") return root.showNetworkWidget;
        if (name === "Power") return root.showPowerWidget;
        return root.showWorkspaceWidget;
    }

    function toggleWidget(name) {
        if (name === "Volume") root.showVolumeWidget = !root.showVolumeWidget;
        else if (name === "Bluetooth") root.showBluetoothWidget = !root.showBluetoothWidget;
        else if (name === "Network") root.showNetworkWidget = !root.showNetworkWidget;
        else if (name === "Power") root.showPowerWidget = !root.showPowerWidget;
        else if (name === "Workspaces") root.showWorkspaceWidget = !root.showWorkspaceWidget;
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
        root.utilityPage = "health";
        root.utilityVisible = true;
        root.openPage("health", "Checking system health...", healthProcess);
    }

    function openActions() {
        root.openPage("actions", "", null);
    }

    function openAppearance() {
        root.openPage("appearance", "Loading themes...", themesProcess);
    }

    function openKeybinds() {
        root.utilityPage = "keybinds";
        root.utilityVisible = true;
        root.openPage("keybinds", "Loading keybinds...", keybindsProcess);
    }

    function openInfo() {
        root.utilityPage = "info";
        root.utilityVisible = true;
        root.openPage("info", "Loading system info...", infoProcess);
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
