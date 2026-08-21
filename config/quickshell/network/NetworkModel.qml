import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property bool editorAvailable: false
    property bool actionUsesPasswordStdin: false
    property bool statusRefreshPending: false
    property bool wifiPasswordPromptVisible: false
    property int selectedIndex: 0
    property int selectedWifiIndex: -1
    property string statusText: "NET offline"
    property string connectionKind: "disconnected"
    property int wifiSignal: -1
    readonly property string barIconState: root.connectionKind
    property string message: ""
    property string wifiPassword: ""
    property var devices: []
    property var connections: []
    property var wifiNetworks: []

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
        root.refresh(true);
    }

    function close() {
        root.visible = false;
        root.selectedIndex = 0;
        root.selectedWifiIndex = -1;
        root.wifiPasswordPromptVisible = false;
        root.message = "";
        root.wifiPassword = "";
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh(rescanWifi) {
        root.refreshStatus();
        if (!devicesProcess.running) {
            devicesProcess.running = true;
        }
        if (!connectionsProcess.running) {
            connectionsProcess.running = true;
        }
        root.refreshWifi(rescanWifi === true);
        if (!editorCheckProcess.running) {
            editorCheckProcess.running = true;
        }
    }

    function refreshStatus() {
        if (statusProcess.running) {
            root.statusRefreshPending = true;
            return;
        }

        root.statusRefreshPending = false;
        statusProcess.running = true;
    }

    function refreshWifi(rescan) {
        if (!wifiScanProcess.running) {
            wifiScanProcess.command = Commands.networkHelperCommand("wifi-scan", rescan ? ["--rescan", "yes"] : ["--rescan", "no"]);
            wifiScanProcess.running = true;
        }
    }

    function parseStatus(text) {
        const trimmed = text.trim();
        const fields = trimmed.split("\t");
        const kind = fields.length >= 4 ? fields[0] : "disconnected";
        const device = fields.length >= 4 ? fields[1] : "";
        const signal = fields.length >= 4 ? parseInt(fields[3], 10) : -1;

        root.connectionKind = kind === "ethernet" || kind === "wifi" ? kind : "disconnected";
        root.wifiSignal = root.connectionKind === "wifi" && !isNaN(signal)
            ? Math.max(0, Math.min(100, signal)) : -1;
        root.statusText = root.connectionKind === "disconnected" || device.length === 0
            ? "NET offline" : "NET " + device;
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

    function parseWifiNetworks(text) {
        const rows = [];
        const lines = text.trim().length > 0 ? text.trim().split("\n") : [];
        const selectedBssid = root.selectedWifiNetwork() ? root.selectedWifiNetwork().bssid : "";

        for (const line of lines) {
            const fields = line.split("\t");

            if (fields.length < 7 || fields[2].length === 0) {
                continue;
            }

            const security = fields[4] === "--" ? "" : fields[4];

            rows.push({
                "active": fields[0] === "*",
                "bssid": fields[1],
                "ssid": fields[2],
                "signal": fields[3],
                "security": security,
                "channel": fields[5],
                "device": fields[6],
                "secured": security.length > 0
            });
        }

        root.wifiNetworks = rows;
        root.selectedWifiIndex = -1;

        for (let i = 0; i < rows.length; i++) {
            if (rows[i].bssid === selectedBssid) {
                root.selectedWifiIndex = i;
                break;
            }
        }

        if (root.wifiPasswordPromptVisible && root.selectedWifiIndex < 0) {
            root.cancelWifiPasswordPrompt();
        }
    }

    function selectedWifiNetwork() {
        if (root.selectedWifiIndex < 0 || root.selectedWifiIndex >= root.wifiNetworks.length) {
            return null;
        }

        return root.wifiNetworks[root.selectedWifiIndex];
    }

    function selectWifi(index) {
        if (index < 0 || index >= root.wifiNetworks.length) {
            return;
        }

        if (root.selectedWifiIndex === index) {
            return;
        }

        root.selectedWifiIndex = index;
        root.wifiPasswordPromptVisible = false;
        root.wifiPassword = "";
        root.message = "";
    }

    function cancelWifiPasswordPrompt() {
        root.wifiPasswordPromptVisible = false;
        root.selectedWifiIndex = -1;
        root.wifiPassword = "";
        root.message = "";
    }

    function connectWifi(network) {
        if (!network || network.device.length === 0 || network.bssid.length === 0 || network.ssid.length === 0) {
            return;
        }
        if (root.busy || actionProcess.running) {
            return;
        }

        if (network.secured && root.wifiPassword.length === 0) {
            for (let i = 0; i < root.wifiNetworks.length; i++) {
                if (root.wifiNetworks[i].bssid === network.bssid && root.wifiNetworks[i].device === network.device) {
                    root.selectedWifiIndex = i;
                    break;
                }
            }
            root.wifiPasswordPromptVisible = true;
            root.message = "";
            return;
        }

        const args = [network.device, network.bssid, network.ssid];
        if (network.secured) {
            args.push("--password-stdin");
            args.push(network.security);
        }

        root.busy = true;
        root.actionUsesPasswordStdin = network.secured;
        root.wifiPasswordPromptVisible = false;
        root.message = "Connecting " + network.ssid;
        actionProcess.command = Commands.networkHelperCommand("wifi-connect", args);
        actionProcess.running = true;
    }

    function connectSelectedWifi() {
        root.connectWifi(root.selectedWifiNetwork());
    }

    function connectProfile(profile) {
        if (!profile || profile.uuid.length === 0) {
            return;
        }
        if (root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionUsesPasswordStdin = false;
        root.message = "Connecting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("connect", [profile.uuid]);
        actionProcess.running = true;
    }

    function disconnectDevice(device) {
        if (!device || device.length === 0) {
            return;
        }
        if (root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionUsesPasswordStdin = false;
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

        onRunningChanged: {
            if (!running && root.statusRefreshPending) {
                root.statusRefreshPending = false;
                statusProcess.running = true;
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseStatus(this.text);
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
        stdinEnabled: true

        onStarted: {
            if (root.actionUsesPasswordStdin) {
                write(root.wifiPassword + "\n");
                root.actionUsesPasswordStdin = false;
                root.wifiPassword = "";
            }
        }

        onRunningChanged: {
            if (!running) {
                root.busy = false;
                root.actionUsesPasswordStdin = false;
                root.wifiPassword = "";
                root.message = "";
                root.refresh(false);
            }
        }
    }

    Process {
        id: wifiScanProcess

        command: Commands.networkHelperCommand("wifi-scan", ["--rescan", "no"])
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseWifiNetworks(this.text)
        }
    }

    Process {
        command: Commands.networkHelperCommand("monitor")
        running: true

        stdout: SplitParser {
            onRead: root.refresh(false)
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

    Component.onCompleted: root.refresh(false)
}
