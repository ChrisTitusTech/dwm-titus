import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property bool editorAvailable: false
    property int selectedIndex: 0
    property string statusText: "NET offline"
    property string message: ""
    property var devices: []
    property var connections: []

    readonly property var activeConnections: root.connections.filter(function(profile) {
        return profile.active;
    })
    readonly property var savedProfiles: root.connections.filter(function(profile) {
        return !profile.active && root.isSupportedProfile(profile.type);
    })

    function isSupportedProfile(type) {
        return type === "802-3-ethernet" || type === "ethernet" || type === "802-11-wireless" || type === "wifi" || type === "vpn";
    }

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
        root.selectedIndex = 0;
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
        if (!statusProcess.running) {
            statusProcess.running = true;
        }
        if (!devicesProcess.running) {
            devicesProcess.running = true;
        }
        if (!connectionsProcess.running) {
            connectionsProcess.running = true;
        }
        if (!editorCheckProcess.running) {
            editorCheckProcess.running = true;
        }
    }

    function parseDevices(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 4) {
                continue;
            }

            rows.push({
                "device": fields[0],
                "type": fields[1],
                "state": fields[2],
                "connection": fields[3]
            });
        }

        root.devices = rows;
    }

    function parseConnections(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 5) {
                continue;
            }

            rows.push({
                "name": fields[0],
                "uuid": fields[1],
                "type": fields[2],
                "active": fields[3] === "yes",
                "device": fields[4]
            });
        }

        root.connections = rows;
        if (root.selectedIndex >= rows.length) {
            root.selectedIndex = Math.max(0, rows.length - 1);
        }
    }

    function connectProfile(profile) {
        if (!profile || profile.uuid.length === 0) {
            return;
        }

        root.busy = true;
        root.message = "Connecting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("connect", [profile.uuid]);
        actionProcess.running = true;
    }

    function disconnectDevice(device) {
        if (!device || device.length === 0) {
            return;
        }

        root.busy = true;
        root.message = "Disconnecting " + device;
        actionProcess.command = Commands.networkHelperCommand("disconnect", [device]);
        actionProcess.running = true;
    }

    function openEditor() {
        if (!root.editorAvailable) {
            return;
        }

        editorProcess.running = true;
    }

    Process {
        id: statusProcess

        command: Commands.networkHelperCommand("status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();

                root.statusText = text.length > 0 ? text : "NET offline";
            }
        }
    }

    Process {
        id: devicesProcess

        command: Commands.networkHelperCommand("devices")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(this.text)
        }
    }

    Process {
        id: connectionsProcess

        command: Commands.networkHelperCommand("connections")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseConnections(this.text)
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running) {
                root.busy = false;
                root.message = "";
                root.refresh();
            }
        }
    }

    Process {
        id: editorProcess

        command: Commands.networkHelperCommand("editor")
        running: false
    }

    Process {
        id: editorCheckProcess

        command: ["sh", "-c", "command -v nm-connection-editor >/dev/null 2>&1 && printf yes || printf no"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.editorAvailable = this.text.trim() === "yes"
        }
    }
}
