import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core

Scope {
    id: root

    property bool settingsVisible: false
    property bool controlCenterVisible: false
    property bool busy: false
    property string providerState: "idle"
    property string providerDetail: "Power state has not been loaded"
    property string message: ""
    property string mutationOrigin: ""
    property string pendingAction: ""
    property int mutationGeneration: 0
    property int actionGeneration: 0
    property int snapshotGeneration: 0
    property bool snapshotPending: false
    property bool actionSucceeded: false
    property string actionError: ""

    property bool batteryAvailable: false
    property int batteryPercent: 0
    property string batteryStatus: "unknown"
    property int batteryTimeToEmpty: 0
    property int batteryTimeToFull: 0
    property real batteryRate: 0
    property string batteryDetail: "No system battery is present"
    property string externalPowerState: "unknown"
    property string externalPowerDetail: "External power state is unavailable"

    property string profileState: "idle"
    property string profileDetail: "Power Profiles service has not been queried"
    property var profiles: []
    property string activeProfile: ""
    property bool nativeProfileObserved: false

    property string dpmsState: "idle"
    property bool dpmsAvailable: false
    property bool dpmsEnabled: false
    property int dpmsTimeout: 600
    property string dpmsDetail: "Display power state has not been queried"

    property string lockState: "idle"
    property bool lockAvailable: false
    property bool lockEnabled: false
    property bool lockRunning: false
    property int lockTimeout: 600
    property string lockDetail: "Automatic lock state has not been queried"

    property string suspendState: "idle"
    property string suspendCapabilityClass: "read-only"
    property string suspendDetail: "Suspend capability has not been queried"
    property string lidState: "idle"
    property string lidPosition: "unknown"
    property string lidCapabilityClass: "read-only"
    property string lidDetail: "Lid capability has not been queried"
    property string lidPolicyState: "idle"
    property string lidPolicy: "unknown"
    property string lidExternalPowerPolicy: "unknown"
    property string lidDockedPolicy: "unknown"
    property string lidPolicyCapabilityClass: "read-only"
    property string lidPolicyDetail: "Persistent lid policy has not been queried"

    readonly property bool sectionVisible: root.settingsVisible || root.controlCenterVisible
    readonly property var nativeBattery: UPower.displayDevice
    readonly property var timeoutPresets: [
        { "label": "5m", "seconds": 300 },
        { "label": "10m", "seconds": 600 },
        { "label": "15m", "seconds": 900 },
        { "label": "30m", "seconds": 1800 },
        { "label": "1h", "seconds": 3600 }
    ]

    function validState(value) {
        return value === "available" || value === "partial" || value === "restricted"
            || value === "unavailable";
    }

    function validBoolean(value) {
        return value === "yes" || value === "no";
    }

    function validCapabilityClass(value) {
        return value === "read-only" || value === "user-session" || value === "delegated"
            || value === "restricted" || value === "privileged";
    }

    function boundedInteger(value, minimum, maximum) {
        if (typeof value !== "string" || !/^[0-9]+$/.test(value)) return -1;
        const parsed = Number(value);
        return Number.isInteger(parsed) && parsed >= minimum && parsed <= maximum ? parsed : -1;
    }

    function boundedNumber(value, minimum, maximum) {
        if (typeof value !== "string" || !/^[0-9]+(?:\.[0-9]+)?$/.test(value)) return -1;
        const parsed = Number(value);
        return isFinite(parsed) && parsed >= minimum && parsed <= maximum ? parsed : -1;
    }

    function validLidAction(value) {
        return value === "default" || value === "ignore" || value === "poweroff"
            || value === "reboot" || value === "halt" || value === "kexec"
            || value === "suspend" || value === "hibernate" || value === "hybrid-sleep"
            || value === "suspend-then-hibernate" || value === "lock" || value === "unknown";
    }

    function clearDpmsState(detail) {
        root.dpmsState = "unavailable";
        root.dpmsAvailable = false;
        root.dpmsEnabled = false;
        root.dpmsTimeout = 0;
        root.dpmsDetail = detail;
    }

    function clearLockState(detail) {
        root.lockState = "unavailable";
        root.lockAvailable = false;
        root.lockEnabled = false;
        root.lockRunning = false;
        root.lockTimeout = 0;
        root.lockDetail = detail;
    }

    function clearExternalPowerState(detail) {
        root.externalPowerState = "unknown";
        root.externalPowerDetail = detail;
    }

    function clearBatteryState(detail) {
        root.batteryAvailable = false;
        root.batteryPercent = 0;
        root.batteryStatus = "unknown";
        root.batteryTimeToEmpty = 0;
        root.batteryTimeToFull = 0;
        root.batteryRate = 0;
        root.batteryDetail = detail;
    }

    function clearPolicyState(detail) {
        root.clearDpmsState(detail);
        root.clearLockState(detail);
        root.profileState = "unavailable";
        root.profileDetail = detail;
        root.profiles = [];
        root.activeProfile = "";
        root.suspendState = "unavailable";
        root.suspendCapabilityClass = "read-only";
        root.suspendDetail = detail;
        root.lidState = "unavailable";
        root.lidPosition = "unknown";
        root.lidCapabilityClass = "read-only";
        root.lidDetail = detail;
        root.lidPolicyState = "unavailable";
        root.lidPolicy = "unknown";
        root.lidExternalPowerPolicy = "unknown";
        root.lidDockedPolicy = "unknown";
        root.lidPolicyCapabilityClass = "read-only";
        root.lidPolicyDetail = detail;
        if (root.nativeBattery === null || !root.nativeBattery.ready) {
            root.clearExternalPowerState(detail);
            root.clearBatteryState(detail);
        }
    }

    function updateNativeBattery() {
        const battery = root.nativeBattery;
        if (battery === null || !battery.ready) {
            root.clearExternalPowerState("UPower external-power state is unavailable");
            root.clearBatteryState("UPower display battery is unavailable");
            return;
        }
        root.externalPowerState = UPower.onBattery ? "off" : "on";
        root.externalPowerDetail = UPower.onBattery
            ? "System is running on battery power" : "External power is available";
        if (!battery.isPresent) {
            root.batteryAvailable = false;
            root.batteryPercent = 0;
            root.batteryStatus = "unknown";
            root.batteryTimeToEmpty = 0;
            root.batteryTimeToFull = 0;
            root.batteryRate = 0;
            root.batteryDetail = "No system battery is present";
            return;
        }

        root.batteryAvailable = true;
        root.batteryPercent = Math.max(0, Math.min(100, Math.round(battery.percentage * 100)));
        root.batteryStatus = UPowerDeviceState.toString(battery.state).toLowerCase();
        root.batteryTimeToEmpty = Math.max(0, Math.round(battery.timeToEmpty));
        root.batteryTimeToFull = Math.max(0, Math.round(battery.timeToFull));
        root.batteryRate = Math.max(0, battery.changeRate);
        root.batteryDetail = battery.model.length > 0 ? battery.model : "UPower display battery";
    }

    function updateNativeProfile() {
        if (root.profileState !== "available") return;
        let profile = "";
        if (PowerProfiles.profile === PowerProfile.PowerSaver) profile = "power-saver";
        else if (PowerProfiles.profile === PowerProfile.Balanced) profile = "balanced";
        else if (PowerProfiles.profile === PowerProfile.Performance) profile = "performance";
        if (profile.length > 0 && root.profiles.some(function(item) { return item.id === profile; })) {
            root.activeProfile = profile;
            root.profiles = root.profiles.map(function(item) {
                return Object.assign({}, item, { "active": item.id === profile });
            });
        }
    }

    function openSettings() {
        root.settingsVisible = true;
        root.syncSectionLifecycle();
        root.refresh();
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.syncSectionLifecycle();
    }

    function openControlCenter() {
        root.controlCenterVisible = true;
        root.syncSectionLifecycle();
        root.refresh();
    }

    function closeControlCenter() {
        root.controlCenterVisible = false;
        root.syncSectionLifecycle();
    }

    function syncSectionLifecycle() {
        if (root.sectionVisible) {
            if (!watchProcess.running) watchProcess.running = true;
        } else {
            watchRestartTimer.stop();
            watchSettleTimer.stop();
            watchProcess.running = false;
            snapshotProcess.running = false;
            root.snapshotPending = false;
        }
    }

    function refresh() {
        root.updateNativeBattery();
        root.updateNativeProfile();
        if (!root.sectionVisible) return;
        if (snapshotProcess.running) {
            root.snapshotPending = true;
            return;
        }
        root.snapshotPending = false;
        root.snapshotGeneration = root.mutationGeneration;
        snapshotProcess.running = true;
    }

    function parseSnapshot(text) {
        if (root.snapshotGeneration !== root.mutationGeneration) return;

        let protocolValid = false;
        let providerSeen = false;
        let providerState = "unavailable";
        let providerDetail = "Power provider returned no status";
        let dpms = null;
        let lock = null;
        let battery = null;
        let externalPower = null;
        let profileSupport = null;
        const profileRows = [];
        let suspend = null;
        let lid = null;
        let lidPolicy = null;

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "power-protocol") {
                protocolValid = fields.length >= 3 && fields[1] === "1"
                    && root.boundedInteger(fields[2], 0, 2147483647) >= 0;
            } else if (fields[0] === "provider" && fields.length >= 5 && fields[1] === "power"
                    && root.validState(fields[2]) && root.validCapabilityClass(fields[3])) {
                providerSeen = true;
                providerState = fields[2];
                providerDetail = fields.slice(4).join("\t");
            } else if (fields[0] === "power-dpms" && fields.length >= 6
                    && root.validState(fields[1]) && root.validBoolean(fields[2])
                    && root.validCapabilityClass(fields[4])) {
                const timeout = root.boundedInteger(fields[3], 0, 86400);
                if (timeout >= 0) dpms = { "state": fields[1], "enabled": fields[2] === "yes",
                    "timeout": timeout, "detail": fields.slice(5).join("\t") };
            } else if (fields[0] === "power-lock" && fields.length >= 7
                    && root.validState(fields[1]) && root.validBoolean(fields[2])
                    && root.validBoolean(fields[4]) && root.validCapabilityClass(fields[5])) {
                const timeout = root.boundedInteger(fields[3], 0, 86400);
                if (timeout >= 0) lock = { "state": fields[1], "enabled": fields[2] === "yes",
                    "timeout": timeout, "running": fields[4] === "yes",
                    "detail": fields.slice(6).join("\t") };
            } else if (fields[0] === "power-external" && fields.length >= 3
                    && (fields[1] === "on" || fields[1] === "off" || fields[1] === "unknown")) {
                externalPower = { "state": fields[1], "detail": fields.slice(2).join("\t") };
            } else if (fields[0] === "power-battery" && fields.length >= 8
                    && root.validState(fields[1])
                    && (fields[2] === "unknown" || fields[2] === "charging"
                        || fields[2] === "discharging" || fields[2] === "empty"
                        || fields[2] === "full" || fields[2] === "pending-charge"
                        || fields[2] === "pending-discharge")) {
                const percent = root.boundedInteger(fields[3], 0, 100);
                const empty = root.boundedInteger(fields[4], 0, Number.MAX_SAFE_INTEGER);
                const full = root.boundedInteger(fields[5], 0, Number.MAX_SAFE_INTEGER);
                const rate = root.boundedNumber(fields[6], 0, Number.MAX_VALUE);
                if (percent >= 0 && empty >= 0 && full >= 0 && rate >= 0) {
                    battery = { "state": fields[1], "status": fields[2], "percent": percent,
                        "empty": empty, "full": full, "rate": rate,
                        "detail": fields.slice(7).join("\t") };
                }
            } else if (fields[0] === "power-profile-support" && fields.length >= 4
                    && root.validState(fields[1]) && root.validCapabilityClass(fields[2])) {
                profileSupport = { "state": fields[1], "detail": fields.slice(3).join("\t") };
            } else if (fields[0] === "power-profile" && fields.length >= 3
                    && (fields[1] === "power-saver" || fields[1] === "balanced" || fields[1] === "performance")
                    && (fields[2] === "active" || fields[2] === "available")) {
                profileRows.push({ "id": fields[1], "active": fields[2] === "active" });
            } else if (fields[0] === "power-suspend" && fields.length >= 4
                    && root.validState(fields[1]) && root.validCapabilityClass(fields[2])) {
                suspend = { "state": fields[1], "capabilityClass": fields[2],
                    "detail": fields.slice(3).join("\t") };
            } else if (fields[0] === "power-lid" && fields.length >= 5
                    && root.validState(fields[1])
                    && (fields[2] === "open" || fields[2] === "closed" || fields[2] === "unknown")
                    && root.validCapabilityClass(fields[3])) {
                lid = { "state": fields[1], "position": fields[2], "capabilityClass": fields[3],
                    "detail": fields.slice(4).join("\t") };
            } else if (fields[0] === "power-lid-policy" && fields.length >= 7
                    && root.validState(fields[1]) && root.validLidAction(fields[2])
                    && root.validLidAction(fields[3]) && root.validLidAction(fields[4])
                    && root.validCapabilityClass(fields[5])) {
                lidPolicy = { "state": fields[1], "policy": fields[2], "external": fields[3],
                    "docked": fields[4], "capabilityClass": fields[5],
                    "detail": fields.slice(6).join("\t") };
            }
        }

        if (!protocolValid || !providerSeen) {
            root.providerState = "unavailable";
            root.providerDetail = "Power provider returned an unsupported response";
            root.clearPolicyState(root.providerDetail);
            return;
        }

        root.providerState = providerState;
        root.providerDetail = providerDetail;
        if (dpms !== null) {
            root.dpmsState = dpms.state; root.dpmsAvailable = dpms.state === "available";
            root.dpmsEnabled = dpms.enabled; root.dpmsTimeout = dpms.timeout; root.dpmsDetail = dpms.detail;
        } else {
            root.clearDpmsState("Display power provider returned malformed state");
        }
        if (lock !== null) {
            root.lockState = lock.state; root.lockAvailable = lock.state === "available";
            root.lockEnabled = lock.enabled; root.lockTimeout = lock.timeout;
            root.lockRunning = lock.running; root.lockDetail = lock.detail;
        } else {
            root.clearLockState("Automatic lock provider returned malformed state");
        }
        if (externalPower !== null && (root.nativeBattery === null || !root.nativeBattery.ready)) {
            root.externalPowerState = externalPower.state; root.externalPowerDetail = externalPower.detail;
        } else if (externalPower === null && (root.nativeBattery === null || !root.nativeBattery.ready)) {
            root.clearExternalPowerState("External power provider returned malformed state");
        }
        if (battery !== null && (root.nativeBattery === null || !root.nativeBattery.ready)) {
            root.batteryAvailable = battery.state === "available";
            root.batteryStatus = battery.status; root.batteryPercent = battery.percent;
            root.batteryTimeToEmpty = battery.empty; root.batteryTimeToFull = battery.full;
            root.batteryRate = battery.rate; root.batteryDetail = battery.detail;
        } else if (battery === null && (root.nativeBattery === null || !root.nativeBattery.ready)) {
            root.clearBatteryState("Battery provider returned malformed state");
        }
        if (profileSupport !== null) {
            root.profileState = profileSupport.state; root.profileDetail = profileSupport.detail;
            root.profiles = profileSupport.state === "available" ? profileRows : [];
            const active = profileRows.find(function(item) { return item.active; });
            root.activeProfile = active ? active.id : "";
            if (root.nativeProfileObserved) root.updateNativeProfile();
        } else {
            root.profileState = "unavailable"; root.profileDetail = "Power profile provider returned malformed state";
            root.profiles = []; root.activeProfile = "";
        }
        if (suspend !== null) {
            root.suspendState = suspend.state; root.suspendCapabilityClass = suspend.capabilityClass;
            root.suspendDetail = suspend.detail;
        } else {
            root.suspendState = "unavailable"; root.suspendCapabilityClass = "read-only";
            root.suspendDetail = "Suspend provider returned malformed state";
        }
        if (lid !== null) {
            root.lidState = lid.state; root.lidPosition = lid.position;
            root.lidCapabilityClass = lid.capabilityClass; root.lidDetail = lid.detail;
        } else {
            root.lidState = "unavailable"; root.lidPosition = "unknown";
            root.lidCapabilityClass = "read-only"; root.lidDetail = "Lid provider returned malformed state";
        }
        if (lidPolicy !== null) {
            root.lidPolicyState = lidPolicy.state; root.lidPolicy = lidPolicy.policy;
            root.lidExternalPowerPolicy = lidPolicy.external; root.lidDockedPolicy = lidPolicy.docked;
            root.lidPolicyCapabilityClass = lidPolicy.capabilityClass;
            root.lidPolicyDetail = lidPolicy.detail;
        } else {
            root.lidPolicyState = "unavailable"; root.lidPolicy = "unknown";
            root.lidExternalPowerPolicy = "unknown"; root.lidDockedPolicy = "unknown";
            root.lidPolicyCapabilityClass = "read-only";
            root.lidPolicyDetail = "Lid policy provider returned malformed state";
        }
    }

    function expectedResult(action, args) {
        if (action === "power-profile-set") return "power-profile\t" + args[0];
        if (action === "power-dpms") return "power-dpms\t" + (args[0] === "on" ? "1" : "0");
        if (action === "power-dpms-timeout") return "power-dpms-timeout\t" + args[0];
        if (action === "power-lock") return "power-lock\t" + (args[0] === "on" ? "1" : "0");
        if (action === "power-lock-timeout") return "power-lock-timeout\t" + args[0];
        return "";
    }

    function messageFor(origin) {
        return root.mutationOrigin.length === 0 || root.mutationOrigin === origin ? root.message : "";
    }

    function runAction(action, args, origin) {
        if (root.busy || actionProcess.running) return;
        const expected = root.expectedResult(action, args || []);
        if (expected.length === 0) return;
        root.mutationGeneration++;
        root.actionGeneration = root.mutationGeneration;
        root.pendingAction = action;
        root.mutationOrigin = origin || "settings";
        root.actionSucceeded = false;
        root.actionError = "";
        root.message = "Applying power setting...";
        actionProcess.expectedResult = expected;
        actionProcess.command = Commands.powerHelperCommand(action, args || []);
        root.busy = true;
        actionProcess.running = true;
    }

    function setProfile(profile, origin) {
        if (profile === "power-saver" || profile === "balanced" || profile === "performance")
            root.runAction("power-profile-set", [profile], origin);
    }

    function setDpms(enabled, origin) {
        root.runAction("power-dpms", [enabled ? "on" : "off"], origin);
    }

    function setDpmsTimeout(seconds, origin) {
        if (Number.isInteger(seconds) && seconds >= 60 && seconds <= 86400)
            root.runAction("power-dpms-timeout", [seconds.toString()], origin);
    }

    function setLock(enabled, origin) {
        root.runAction("power-lock", [enabled ? "on" : "off"], origin);
    }

    function setLockTimeout(seconds, origin) {
        if (Number.isInteger(seconds) && seconds >= 60 && seconds <= 86400)
            root.runAction("power-lock-timeout", [seconds.toString()], origin);
    }

    Connections {
        target: UPower
        function onOnBatteryChanged() { root.updateNativeBattery(); }
    }

    Connections {
        target: root.nativeBattery
        function onReadyChanged() { root.updateNativeBattery(); }
        function onIsPresentChanged() { root.updateNativeBattery(); }
        function onPercentageChanged() { root.updateNativeBattery(); }
        function onStateChanged() { root.updateNativeBattery(); }
        function onTimeToEmptyChanged() { root.updateNativeBattery(); }
        function onTimeToFullChanged() { root.updateNativeBattery(); }
        function onChangeRateChanged() { root.updateNativeBattery(); }
    }

    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            root.nativeProfileObserved = true;
            root.updateNativeProfile();
        }
        function onHasPerformanceProfileChanged() {
            if (root.sectionVisible) root.refresh();
        }
    }

    Process {
        id: snapshotProcess
        command: Commands.powerHelperCommand("power-snapshot")
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseSnapshot(this.text) }
        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0 && root.snapshotGeneration === root.mutationGeneration) {
                    root.providerState = "unavailable";
                    root.providerDetail = error;
                    root.clearPolicyState(error);
                }
            }
        }
        onRunningChanged: {
            if (!running && root.snapshotPending && root.sectionVisible) {
                root.snapshotPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }

    Process {
        id: watchProcess
        command: Commands.powerHelperCommand("power-watch")
        running: false
        stdout: SplitParser { onRead: watchSettleTimer.restart() }
        onRunningChanged: {
            if (!running && root.sectionVisible) watchRestartTimer.restart();
        }
    }

    Timer {
        id: watchSettleTimer
        interval: 250
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: watchRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.sectionVisible && !watchProcess.running) watchProcess.running = true;
        }
    }

    Process {
        id: actionProcess
        property string expectedResult: ""
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                root.actionSucceeded = lines.indexOf(actionProcess.expectedResult) !== -1;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (root.actionGeneration !== root.mutationGeneration) return;
                root.actionError = this.text.trim();
            }
        }
        onRunningChanged: {
            if (running || root.actionGeneration !== root.mutationGeneration) return;
            root.busy = false;
            if (root.actionSucceeded) {
                root.message = "Power setting updated";
            } else {
                root.message = root.actionError.length > 0
                    ? root.actionError : "Power helper did not confirm the requested change";
            }
            root.pendingAction = "";
            if (root.sectionVisible) root.refresh();
        }
    }

    Component.onCompleted: root.updateNativeBattery()
}
