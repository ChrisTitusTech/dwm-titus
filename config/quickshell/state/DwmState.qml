import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int currentWorkspace: 0
    property var monitorWorkspaceRows: []
    property var workspaceNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    property var occupiedWorkspaces: []
    property var runningApps: []
    property string activeWindowTitle: "Desktop"
    property string activeWindowClass: "application-x-executable"
    property string statusText: ""
    property var statusSegments: []
    property bool batteryAvailable: false
    property int batteryPercent: 0
    property string batteryStatus: ""

    function parseState(text) {
        const lines = text.trim().split("\n");

        for (const line of lines) {
            const separator = line.indexOf("=");

            if (separator < 0) {
                continue;
            }

            const key = line.slice(0, separator);
            const value = line.slice(separator + 1);

            if (key === "current") {
                const parsed = parseInt(value, 10);

                root.currentWorkspace = isNaN(parsed) ? 0 : parsed;
            } else if (key === "monitor_desktops") {
                const fields = value.length > 0 ? value.split(",") : [];
                const rows = [];

                for (let index = 0; index + 4 < fields.length; index += 5) {
                    rows.push({
                        "x": parseInt(fields[index], 10),
                        "y": parseInt(fields[index + 1], 10),
                        "width": parseInt(fields[index + 2], 10),
                        "height": parseInt(fields[index + 3], 10),
                        "desktop": parseInt(fields[index + 4], 10)
                    });
                }
                root.monitorWorkspaceRows = rows;
            } else if (key === "names") {
                root.workspaceNames = value.length > 0 ? value.split("|") : [];
            } else if (key === "occupied") {
                root.occupiedWorkspaces = value.length > 0 ? value.split("|").map(function(workspace) {
                    return parseInt(workspace, 10);
                }) : [];
            } else if (key === "apps") {
                root.runningApps = value.length > 0 ? value.split("|").map(function(app) {
                    const separator = app.indexOf(":");
                    return { "windowId": app.slice(0, separator), "appClass": app.slice(separator + 1) };
                }) : [];
            } else if (key === "title") {
                root.activeWindowTitle = value.length > 0 ? value : "Desktop";
            } else if (key === "class") {
                root.activeWindowClass = value.length > 0 ? value : "application-x-executable";
            } else if (key === "status") {
                root.statusText = value;
                root.updateStatusSegments();
            }
        }
    }

    function workspaceOccupied(index) {
        return root.occupiedWorkspaces.indexOf(index) !== -1;
    }

    function screenIndex(screen) {
        const pixelRatio = screen && screen.devicePixelRatio > 0
            ? screen.devicePixelRatio : 1;
        const pixelX = screen ? Math.round(screen.x) : 0;
        const pixelY = screen ? Math.round(screen.y) : 0;
        const pixelWidth = screen ? Math.round(screen.width * pixelRatio) : 0;
        const pixelHeight = screen ? Math.round(screen.height * pixelRatio) : 0;

        for (let index = 0; index < root.monitorWorkspaceRows.length; index++) {
            const row = root.monitorWorkspaceRows[index];
            const logicalMatch = screen && row.x === screen.x && row.y === screen.y
                && row.width === screen.width && row.height === screen.height;
            const pixelMatch = screen && row.x === pixelX && row.y === pixelY
                && row.width === pixelWidth && row.height === pixelHeight;

            if (logicalMatch || pixelMatch) {
                return index;
            }
        }

        for (let index = 0; index < Quickshell.screens.length; index++) {
            if (Quickshell.screens[index] === screen
                    || (screen && Quickshell.screens[index].name === screen.name)) {
                return index;
            }
        }

        return 0;
    }

    function workspaceIndexes(screen) {
        const indexes = [];
        const workspaceCount = root.workspaceNames.length;

        if (workspaceCount === 0) {
            return indexes;
        }

        const screenCount = Math.max(1, root.monitorWorkspaceRows.length > 0
            ? root.monitorWorkspaceRows.length : Quickshell.screens.length);
        const logicalIndex = Math.min(root.screenIndex(screen), screenCount - 1);
        const workspacesPerScreen = Math.max(1, Math.floor(workspaceCount / screenCount));
        let start = logicalIndex * workspacesPerScreen;
        let end = logicalIndex === screenCount - 1
            ? workspaceCount : start + workspacesPerScreen;

        if (start >= workspaceCount) {
            start = workspaceCount - 1;
        }
        end = Math.min(end, workspaceCount);

        for (let index = start; index < end; index++) {
            indexes.push(index);
        }

        return indexes;
    }

    function currentWorkspaceForScreen(screen) {
        const logicalIndex = root.screenIndex(screen);
        const indexes = root.workspaceIndexes(screen);
        const reported = logicalIndex < root.monitorWorkspaceRows.length
            ? root.monitorWorkspaceRows[logicalIndex].desktop : root.currentWorkspace;

        return indexes.indexOf(reported) !== -1
            ? reported : (indexes.length > 0 ? indexes[0] : -1);
    }

    function switchWorkspaceForScreen(screen, index) {
        if (root.workspaceIndexes(screen).indexOf(index) === -1) {
            return;
        }

        root.switchWorkspace(index);
    }

    function updateStatusSegments() {
        const text = root.statusText.trim();

        root.batteryAvailable = false;
        root.batteryPercent = 0;
        root.batteryStatus = "";

        if (text.length === 0 || text.indexOf("dwm-titus:") === 0) {
            root.statusSegments = [];
            return;
        }

        root.statusSegments = text.split(/\s+\|\s+| {2,}/).filter(function(segment) {
            const trimmed = segment.trim();

            if (trimmed.indexOf("BAT ") === 0) {
                const battery = trimmed.match(/^BAT\s+([0-9]+)%\s*(.*)$/);

                if (battery) {
                    root.batteryAvailable = true;
                    root.batteryPercent = Math.max(0, Math.min(100, parseInt(battery[1], 10)));
                    root.batteryStatus = battery[2].trim();
                }

                return false;
            }

            return trimmed.length > 0 && trimmed !== "AC"
                && trimmed.indexOf("NET ") !== 0 && trimmed.indexOf("VOL ") !== 0;
        });
    }

    function switchWorkspace(index) {
        switchWorkspaceProcess.command = ["dwm-quickshell-state", "switch", index.toString()];
        switchWorkspaceProcess.running = true;
    }

    function focusWindow(windowId) {
        focusWindowProcess.command = ["dwm-quickshell-state", "focus", windowId];
        focusWindowProcess.running = true;
    }

    Process {
        command: ["dwm-quickshell-state", "watch"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: function(data) {
                root.parseState(data);
            }
        }
    }

    Process {
        id: switchWorkspaceProcess

        command: ["dwm-quickshell-state", "switch", root.currentWorkspace.toString()]
        running: false
    }

    Process {
        id: focusWindowProcess

        command: ["dwm-quickshell-state", "focus", "0"]
        running: false
    }
}
