import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    readonly property bool initialLoading: snapshotProcess.running || editorCheckProcess.running

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    property bool editorAvailable: false
    property bool actionUsesPasswordStdin: false
    property bool wifiPasswordPromptVisible: false
    property string wifiPasswordPromptOrigin: ""
    property bool hiddenPromptVisible: false
    property string hiddenPromptOrigin: ""
    property string hiddenSsid: ""
    property string hiddenSecurity: "wpa-psk"
    property string hiddenDevice: ""
    property string hiddenError: ""
    property bool hiddenConnectPending: false
    property string hiddenPromptPendingOrigin: ""
    property int selectedIndex: 0
    property int selectedWifiIndex: -1
    property string statusText: "NET offline"
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
    readonly property var wifiDevices: root.devices.filter(function(device) {
        return device.type === "wifi" && device.state !== "unmanaged" && device.state !== "unavailable";
    })
    readonly property bool promptVisible: root.wifiPasswordPromptVisible || root.hiddenPromptVisible
    readonly property string hiddenSsidError: root.validateHiddenSsid(root.hiddenSsid)
    readonly property string hiddenPasswordError: root.validateHiddenPassword(root.hiddenSecurity, root.wifiPassword)
    readonly property bool hiddenFormValid: root.hiddenSsidError.length === 0
        && root.hiddenPasswordError.length === 0 && root.hiddenSecurity !== "enterprise"
        && root.hiddenDevice.length > 0
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

    function utf8Length(text) {
        try {
            return encodeURIComponent(text).replace(/%[0-9A-F]{2}/g, "x").length;
        } catch (error) {
            return 33;
        }
    }

    // Mirrors wifi-connect-hidden validation in scripts/dwm-quickshell-network.
    function validateHiddenSsid(ssid) {
        if (ssid.length === 0) return "Network name is required";
        if (root.utf8Length(ssid) > 32) return "Network name is longer than 32 bytes";
        if (/[\x00-\x1f\x7f]/.test(ssid)) return "Network name must not contain control characters";
        return "";
    }

    function validateHiddenPassword(security, password) {
        if (security === "wpa-psk") {
            if (/^[0-9A-Fa-f]{64}$/.test(password)) return "";
            if (/^[\x20-\x7e]{8,63}$/.test(password)) return "";
            return "8 to 63 characters, or 64 hex digits";
        }
        if (security === "sae" || security === "wep") {
            return password.length > 0 ? "" : "Password is required";
        }
        return "";
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
        if (root.hiddenPromptOrigin === "panel" || root.hiddenPromptPendingOrigin === "panel") root.resetHiddenPrompt();
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
        if (root.hiddenPromptOrigin === "settings" || root.hiddenPromptPendingOrigin === "settings") root.resetHiddenPrompt();
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
        root.openPendingHiddenPrompt();
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

    function openHiddenPrompt(origin) {
        if (root.busy) return;
        if (snapshotProcess.running || root.providerState === "loading") {
            // Opened together with the popover: wait for the snapshot that open() started.
            root.hiddenPromptPendingOrigin = origin || "panel";
            return;
        }
        root.hiddenPromptPendingOrigin = "";
        if (!root.actionsAvailable || root.wifiDevices.length === 0) return;
        root.wifiPasswordPromptVisible = false;
        root.wifiPasswordPromptOrigin = "";
        root.selectedWifiIndex = -1;
        root.wifiPassword = "";
        root.hiddenError = "";
        const names = root.wifiDevices.map(device => device.device);
        if (names.indexOf(root.hiddenDevice) < 0) {
            const idle = root.wifiDevices.filter(device => device.state === "disconnected");
            root.hiddenDevice = idle.length > 0 ? idle[0].device : names[0];
        }
        if (root.hiddenSecurity === "enterprise" && !root.editorAvailable) root.hiddenSecurity = "wpa-psk";
        root.hiddenPromptOrigin = origin || "panel";
        root.hiddenPromptVisible = true;
        root.message = "";
    }

    function openPendingHiddenPrompt() {
        if (root.hiddenPromptPendingOrigin.length > 0) root.openHiddenPrompt(root.hiddenPromptPendingOrigin);
    }

    function resetHiddenPrompt() {
        root.hiddenPromptPendingOrigin = "";
        root.hiddenPromptVisible = false;
        root.hiddenPromptOrigin = "";
        root.hiddenSsid = "";
        root.hiddenSecurity = "wpa-psk";
        root.hiddenDevice = "";
        root.hiddenError = "";
        root.wifiPassword = "";
    }

    function cancelHiddenPrompt() {
        root.resetHiddenPrompt();
        root.message = "";
    }

    function openEditorForHidden() {
        root.cancelHiddenPrompt();
        root.message = "Enterprise Wi-Fi opens in Advanced NetworkManager settings";
        root.openEditor();
    }

    function connectHidden(origin) {
        if (!root.hiddenFormValid || !root.actionsAvailable || root.busy || actionProcess.running) {
            return;
        }

        const secured = root.hiddenSecurity !== "none";
        const args = [root.hiddenDevice, root.hiddenSsid, root.hiddenSecurity];
        if (secured) args.push("--password-stdin");

        root.busy = true;
        root.actionFailed = false;
        root.actionOrigin = origin || root.hiddenPromptOrigin || "panel";
        root.actionLabel = "connect hidden Wi-Fi";
        root.actionUsesPasswordStdin = secured;
        root.hiddenConnectPending = true;
        root.hiddenError = "";
        root.hiddenPromptVisible = false;
        root.message = "Connecting " + root.hiddenSsid;
        actionProcess.command = Commands.networkHelperCommand("wifi-connect-hidden", args);
        actionProcess.running = true;
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
            root.resetHiddenPrompt();
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
        onRunningChanged: {
            if (running) return;
            root.snapshotOrigin = "";
            root.openPendingHiddenPrompt();
        }
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
                if (root.hiddenConnectPending) {
                    root.hiddenConnectPending = false;
                    if (root.actionFailed) {
                        // Keep name, security, and device; only the password is retyped.
                        root.hiddenPromptOrigin = root.actionOrigin;
                        root.hiddenPromptVisible = root.actionOrigin === "panel" ? root.visible : root.settingsVisible;
                    } else {
                        root.resetHiddenPrompt();
                    }
                }
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
                    if (root.hiddenConnectPending) root.hiddenError = error;
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
}
