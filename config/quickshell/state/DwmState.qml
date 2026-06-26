import Quickshell
import Quickshell.Io

Scope {
    id: root

    property int currentWorkspace: 0
    property var workspaceNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    property string activeWindowTitle: "Desktop"
    property string statusText: ""
    property var statusSegments: []

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
            } else if (key === "names") {
                root.workspaceNames = value.length > 0 ? value.split("|") : [];
            } else if (key === "title") {
                root.activeWindowTitle = value.length > 0 ? value : "Desktop";
            } else if (key === "status") {
                root.statusText = value;
                root.updateStatusSegments();
            }
        }
    }

    function updateStatusSegments() {
        const text = root.statusText.trim();

        if (text.length === 0 || text.indexOf("dwm-titus:") === 0) {
            root.statusSegments = [];
            return;
        }

        root.statusSegments = text.split(/\s+\|\s+| {2,}/).filter(function(segment) {
            return segment.trim().length > 0;
        });
    }

    function switchWorkspace(index) {
        switchWorkspaceProcess.command = ["dwm-quickshell-state", "switch", index.toString()];
        switchWorkspaceProcess.running = true;
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
}
