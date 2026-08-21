import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    property string statusText: "BT unavailable"
    property string providerState: "idle"
    property string providerDetail: ""
    property string daemonState: "unknown"
    property string adapterState: "unknown"
    property string operationState: "unavailable"
    property var adapters: []
    property var devices: []
    property string message: ""
    property string actionOrigin: ""
    property string actionName: ""
    property string actionAddress: ""
    property string snapshotOrigin: ""
    property string scanOrigin: ""
    property bool actionFailed: false
    readonly property bool available: statusText !== "BT unavailable"
    readonly property bool powered: available && statusText !== "BT off"
    readonly property bool actionsAvailable: operationState === "delegated"
    readonly property bool active: true

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
        root.message = "";
        root.stopUnownedWork("panel");
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh(false, "settings");
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.stopUnownedWork("settings");
    }

    function stopUnownedWork(origin) {
        if (root.actionOrigin === origin && actionProcess.running) actionProcess.running = false;
        if (root.snapshotOrigin === origin && snapshotProcess.running) snapshotProcess.running = false;
        if (root.scanOrigin === origin && scanProcess.running) scanProcess.running = false;
    }

    function toggle() {
        if (root.visible) root.close(); else root.open();
    }

    function refresh(scan, origin) {
        if (!root.active) return;
        if (scan) {
            if (!scanProcess.running) {
                root.scanOrigin = origin || (root.visible ? "panel" : "shared");
                scanProcess.running = true;
            }
            return;
        }
        if (!snapshotProcess.running) {
            root.snapshotOrigin = origin || (root.visible ? "panel" : "shared");
            snapshotProcess.running = true;
        }
    }

    function parseSnapshot(text) {
        const adapters = [];
        const devices = [];
        let protocolValid = false;
        let providerSeen = false;
        let malformed = false;
        root.daemonState = "unknown";
        root.adapterState = "unknown";
        root.operationState = "unavailable";

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "connectivity-protocol") {
                protocolValid = fields.length >= 3 && fields[1] === "1";
            } else if (fields[0] === "provider") {
                if (fields.length < 5 || fields[1] !== "bluetooth") { malformed = true; continue; }
                providerSeen = true;
                root.providerState = fields[2];
                root.providerDetail = fields[4];
            } else if (fields[0] === "bluetooth-adapter") {
                if (fields.length < 7) { malformed = true; continue; }
                adapters.push({ "path": fields[1], "address": fields[2], "name": fields[3] === "-" ? "" : fields[3],
                    "powered": fields[4] === "yes", "discovering": fields[5] === "yes", "pairable": fields[6] === "yes" });
            } else if (fields[0] === "bluetooth-support") {
                if (fields.length < 4) { malformed = true; continue; }
                if (fields[1] === "daemon") root.daemonState = fields[2];
                else if (fields[1] === "adapter") root.adapterState = fields[2];
                else if (fields[1] === "operations") root.operationState = fields[2];
            } else if (fields[0] === "bluetooth-device") {
                if (fields.length < 8) { malformed = true; continue; }
                devices.push({ "path": fields[1], "address": fields[2], "name": fields[3] === "-" ? "" : fields[3],
                    "paired": fields[4] === "yes", "trusted": fields[5] === "yes",
                    "connected": fields[6] === "yes", "adapterPath": fields[7] === "-" ? "" : fields[7] });
            }
        }

        if (!protocolValid || !providerSeen || malformed) {
            root.providerState = "failure";
            root.providerDetail = !protocolValid ? "Unsupported connectivity protocol" : "Malformed Bluetooth provider record";
            root.statusText = "BT unavailable";
            root.message = root.providerDetail;
            root.adapters = [];
            root.devices = [];
            return;
        }

        root.adapters = adapters;
        root.devices = devices;
        if (root.providerState !== "available" || adapters.length === 0) root.statusText = "BT unavailable";
        else if (!adapters[0].powered) root.statusText = "BT off";
        else root.statusText = "BT " + devices.filter(function(device) { return device.connected; }).length;
        if (root.providerState !== "available") root.message = root.providerDetail;
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

    function action(name, args, origin) {
        if (root.busy) return;
        const actionArgs = args || [];
        const address = actionArgs.length > 0 && name !== "bluetooth-power" ? actionArgs[0] : "";
        if (address.length > 0 && !/^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$/.test(address)) {
            root.message = "Invalid Bluetooth device address";
            return;
        }
        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionName = name;
        root.actionAddress = address;
        root.message = address.length > 0 ? name.replace("bluetooth-", "") + " " + address : "Updating adapter...";
        actionProcess.command = Commands.controlsHelperCommand(name, actionArgs);
        actionProcess.running = true;
    }

    Process {
        id: snapshotProcess
        command: Commands.controlsHelperCommand("bluetooth-snapshot")
        stdout: StdioCollector { onStreamFinished: root.parseSnapshot(this.text) }
        stderr: StdioCollector { onStreamFinished: { const error = this.text.trim(); if (error.length > 0) root.message = error; } }
        onRunningChanged: if (!running) root.snapshotOrigin = ""
    }

    Process {
        id: scanProcess
        command: Commands.controlsHelperCommand("bluetooth-scan")
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim().length > 0) root.message = "Bluetooth discovery failed"
        }
        onRunningChanged: if (!running) {
            const completedOrigin = root.scanOrigin;
            if (root.active && !snapshotProcess.running) {
                root.snapshotOrigin = completedOrigin;
                snapshotProcess.running = true;
            }
            root.scanOrigin = "";
        }
    }

    Process {
        command: ["sh", "-c", "command -v busctl >/dev/null 2>&1 && exec busctl --system monitor org.bluez"]
        running: true
        stdout: SplitParser { onRead: monitorSettleTimer.restart() }
    }

    Timer {
        id: monitorSettleTimer
        interval: 600
        onTriggered: root.refresh(false, "shared")
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
                if (!root.actionFailed) root.message = "";
                root.refresh(false);
                root.actionOrigin = "";
                root.actionName = "";
                root.actionAddress = "";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) {
                    root.actionFailed = true;
                    root.message = root.actionName.replace("bluetooth-", "")
                        + (root.actionAddress.length > 0 ? " failed for " + root.actionAddress : " failed");
                }
            }
        }
    }
}
