import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    property bool editorAvailable: false
    property bool actionUsesPasswordStdin: false
    property bool statusRefreshPending: false
    property bool wifiPasswordPromptVisible: false
    property string wifiPasswordPromptOrigin: ""
    property int selectedIndex: 0
    property int selectedWifiIndex: -1
    property string statusText: "NET offline"
    property string connectionKind: "disconnected"
    property int wifiSignal: -1
    readonly property string barIconState: root.connectionKind
    property string message: ""
    property string providerState: "idle"
    property string providerDetail: ""
    property string operationState: "read-only"
    property string actionOrigin: ""
    property string actionLabel: ""
    property string snapshotOrigin: ""
    property bool actionFailed: false
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
    readonly property bool active: true
    readonly property bool actionsAvailable: (providerState === "available" || providerState === "restricted")
        && operationState === "delegated"

    function isSupportedProfile(type) {
        return type === "802-3-ethernet" || type === "ethernet" || type === "802-11-wireless" || type === "wifi" || type === "vpn";
    }

    function supportsFixedWifiSecurity(security) {
        const value = (security || "").toUpperCase();
        return value.indexOf("802.1X") < 0 && value.indexOf("EAP") < 0
            && value.indexOf("ENTERPRISE") < 0;
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
        root.wifiPasswordPromptOrigin = "";
        root.message = "";
        root.wifiPassword = "";
        root.stopUnownedWork("panel");
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh(false, "settings");
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.selectedWifiIndex = -1;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.wifiPassword = "";
        root.stopUnownedWork("settings");
    }

    function stopUnownedWork(origin) {
        if (root.actionOrigin === origin && actionProcess.running) actionProcess.running = false;
        if (root.snapshotOrigin === origin && snapshotProcess.running) snapshotProcess.running = false;
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh(rescanWifi, origin) {
        if (!root.active || snapshotProcess.running) return;
        root.providerState = "loading";
        root.snapshotOrigin = origin || (root.visible ? "panel" : "shared");
        snapshotProcess.command = Commands.networkHelperCommand("snapshot", ["--rescan", rescanWifi ? "yes" : "no"]);
        snapshotProcess.running = true;
        if (!editorCheckProcess.running) {
            editorCheckProcess.running = true;
        }
    }

    function refreshWifi(rescan, origin) {
        root.refresh(rescan === true, origin);
    }

    function parseSnapshot(text) {
        const devices = [];
        const connections = [];
        const wifiNetworks = [];
        let protocolValid = false;
        let providerSeen = false;
        let malformed = false;
        let connectedDevice = "";
        root.operationState = "read-only";

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "connectivity-protocol") {
                protocolValid = fields.length >= 3 && fields[1] === "1";
            } else if (fields[0] === "provider") {
                if (fields.length < 5 || fields[1] !== "network") { malformed = true; continue; }
                providerSeen = true;
                root.providerState = fields[2];
                root.operationState = fields[3];
                root.providerDetail = fields[4];
            } else if (fields[0] === "network-device") {
                if (fields.length < 5) { malformed = true; continue; }
                devices.push({ "device": fields[1], "type": fields[2], "state": fields[3], "connection": fields[4] === "-" ? "" : fields[4] });
                if (connectedDevice.length === 0 && fields[3] === "connected") connectedDevice = fields[1];
            } else if (fields[0] === "network-profile") {
                if (fields.length < 6) { malformed = true; continue; }
                connections.push({ "name": fields[1], "uuid": fields[2], "type": fields[3], "active": fields[4] === "yes", "device": fields[5] === "-" ? "" : fields[5] });
            } else if (fields[0] === "wifi-network") {
                if (fields.length < 8) { malformed = true; continue; }
                const security = fields[5] === "--" ? "" : fields[5];
                wifiNetworks.push({ "active": fields[1] === "*", "bssid": fields[2], "ssid": fields[3],
                    "signal": fields[4], "security": security, "channel": fields[6], "device": fields[7], "secured": security.length > 0 });
            }
        }

        if (!protocolValid || !providerSeen || malformed) {
            root.providerState = "failure";
            root.providerDetail = !protocolValid ? "Unsupported connectivity protocol" : "Malformed network provider record";
            root.statusText = "NET unavailable";
            root.devices = [];
            root.connections = [];
            root.wifiNetworks = [];
            root.message = root.providerDetail;
            return;
        }

        root.devices = devices;
        root.connections = connections;
        root.wifiNetworks = wifiNetworks;
        const stateReadable = root.providerState === "available" || root.providerState === "restricted";
        root.statusText = stateReadable ? (connectedDevice.length > 0 ? "NET " + connectedDevice : "NET offline") : "NET unavailable";
        if (root.providerState !== "available") root.message = root.providerDetail;
        else if (!root.actionFailed && !root.busy) root.message = "";
        if (root.selectedIndex >= connections.length) root.selectedIndex = Math.max(0, connections.length - 1);
        if (root.selectedWifiIndex >= wifiNetworks.length) root.selectedWifiIndex = -1;
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
        root.wifiPasswordPromptOrigin = "";
        root.selectedWifiIndex = -1;
        root.wifiPassword = "";
        root.message = "";
    }

    function connectWifi(network, origin) {
        if (!network || network.device.length === 0 || network.bssid.length === 0 || network.ssid.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        if (!root.supportsFixedWifiSecurity(network.security)) {
            root.message = "Enterprise Wi-Fi opens in Advanced NetworkManager settings";
            root.openEditor();
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
            root.wifiPasswordPromptOrigin = origin || "panel";
            root.message = "";
            return;
        }

        const args = [network.device, network.bssid, network.ssid];
        if (network.secured) {
            args.push("--password-stdin");
            args.push(network.security);
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "connect Wi-Fi";
        root.actionUsesPasswordStdin = network.secured;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.message = "Connecting " + network.ssid;
        actionProcess.command = Commands.networkHelperCommand("wifi-connect", args);
        actionProcess.running = true;
    }

    function connectSelectedWifi(origin) {
        root.connectWifi(root.selectedWifiNetwork(), origin);
    }

    function connectProfile(profile, origin) {
        if (!profile || profile.uuid.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "activate profile";
        root.actionUsesPasswordStdin = false;
        root.message = "Connecting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("connect", [profile.uuid]);
        actionProcess.running = true;
    }

    function disconnectDevice(device, origin) {
        if (!device || device.length === 0) {
            return;
        }
        if (!root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "disconnect device";
        root.actionUsesPasswordStdin = false;
        root.message = "Disconnecting " + device;
        actionProcess.command = Commands.networkHelperCommand("disconnect", [device]);
        actionProcess.running = true;
    }

    function forgetProfile(profile, origin) {
        if (!root.actionsAvailable || !profile || profile.uuid.length === 0 || root.busy || actionProcess.running) return;
        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || "panel";
        root.actionLabel = "forget profile";
        root.actionUsesPasswordStdin = false;
        root.message = "Forgetting " + profile.name;
        actionProcess.command = Commands.networkHelperCommand("forget", [profile.uuid]);
        actionProcess.running = true;
    }

    function openEditor() {
        if (!root.editorAvailable) {
            return;
        }

        editorProcess.running = true;
    }

    Process {
        id: snapshotProcess

        command: Commands.networkHelperCommand("snapshot", ["--rescan", "no"])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSnapshot(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) {
                    root.providerState = "failure";
                    root.providerDetail = error;
                    root.message = error;
                }
            }
        }
        onRunningChanged: if (!running) root.snapshotOrigin = ""
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
                if (!root.actionFailed) root.message = "";
                root.refresh(false);
                root.actionOrigin = "";
                root.actionLabel = "";
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0) {
                    root.actionFailed = true;
                    root.message = root.actionLabel + " failed: " + error;
                }
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
        id: networkMonitorProcess
        command: Commands.networkHelperCommand("monitor")
        running: true

        stdout: SplitParser {
            onRead: root.refresh(false)
        }
        onRunningChanged: {
            if (!running) networkMonitorRestartTimer.restart();
        }
    }

    Timer {
        id: networkMonitorRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!networkMonitorProcess.running) networkMonitorProcess.running = true;
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
