import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string statusText: "BT unavailable"
    property var devices: []
    property string message: ""

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
        root.message = "";
    }

    function toggle() {
        if (root.visible) root.close(); else root.open();
    }

    function refresh(scan) {
        if (!statusProcess.running) statusProcess.running = true;
        if (!devicesProcess.running) {
            devicesProcess.command = Commands.controlsHelperCommand(scan ? "bluetooth-scan" : "bluetooth-devices");
            devicesProcess.running = true;
        }
    }

    function parseDevices(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        for (const line of lines) {
            const fields = line.split("\t");
            if (fields.length < 4) continue;
            rows.push({ "address": fields[0], "name": fields[1], "paired": fields[2] === "yes", "connected": fields[3] === "yes" });
        }
        root.devices = rows;
    }

    function action(name, args) {
        if (root.busy) return;
        root.busy = true;
        root.message = "Working...";
        actionProcess.command = Commands.controlsHelperCommand(name, args || []);
        actionProcess.running = true;
    }

    Process {
        id: statusProcess
        command: Commands.controlsHelperCommand("bluetooth-status")
        stdout: StdioCollector { onStreamFinished: root.statusText = this.text.trim() || "BT unavailable" }
    }

    Process {
        id: devicesProcess
        command: Commands.controlsHelperCommand("bluetooth-devices")
        stdout: StdioCollector { onStreamFinished: root.parseDevices(this.text) }
    }

    Process {
        id: actionProcess
        command: ["sh", "-c", "exit 0"]
        onRunningChanged: {
            if (!running && root.busy) {
                root.busy = false;
                root.message = "";
                root.refresh(false);
            }
        }
    }
}
