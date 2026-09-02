import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

pragma ComponentBehavior: Bound

Scope {
    id: root

    property var notifications: []
    property var history: []
    property bool historyVisible: false
    property int sequence: 0
    property bool doNotDisturb: false
    property int popupTimeoutMs: 6000
    property string policyState: "loading"
    property string policyDetail: "Loading notification policy"
    property bool policySaving: false
    property bool policyReloadPending: false
    property bool policySelfWriteExpected: false
    property bool confirmedDoNotDisturb: false
    property int confirmedPopupTimeoutMs: 6000

    readonly property int criticalTimeoutMs: 10000
    readonly property int maxVisible: 4
    readonly property int maxHistory: 50
    readonly property var popupTimeoutOptions: [4000, 6000, 10000]
    readonly property bool popupSuppressed: root.policyState === "loading"
        || root.doNotDisturb || (root.policySaving && root.confirmedDoNotDisturb)
    readonly property bool policyMutationReady: !root.policySaving
        && (root.policyState === "available" || root.policyState === "defaults")
    readonly property bool policyResetReady: !root.policySaving
        && root.policyState !== "loading" && root.policyState !== "unavailable"
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME") || ""
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string configDir: root.configHome + "/dwm-titus"
    readonly property string policyPath: root.configDir + "/notification-settings.json"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/dwm-titus"
    readonly property string historyPath: cacheDir + "/notification-history.json"

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", configDir, cacheDir])

    function validPopupTimeout(value) {
        return root.popupTimeoutOptions.indexOf(value) >= 0;
    }

    function usePolicyDefaults() {
        root.doNotDisturb = false;
        root.popupTimeoutMs = 6000;
    }

    function dismissNonCriticalPopups() {
        const current = root.notifications.slice();
        for (const item of current) {
            if (item.urgencyName !== "critical") root.closeItem(item, false);
        }
    }

    function applyDoNotDisturb(enabled) {
        root.doNotDisturb = enabled;
        if (enabled) root.dismissNonCriticalPopups();
    }

    function beginPolicyReload(dismissExisting) {
        root.policyState = "loading";
        root.policyDetail = "Reloading notification policy";
        if (dismissExisting !== false) root.dismissNonCriticalPopups();
        policyFile.reload();
    }

    function loadPolicy() {
        if (policyFile.version !== 1 || typeof policyFile.doNotDisturb !== "boolean"
                || !root.validPopupTimeout(policyFile.popupTimeoutMs)) {
            root.usePolicyDefaults();
            root.policyState = "partial";
            root.policyDetail = "Saved notification policy is invalid; safe defaults are active until reset";
            return;
        }
        root.applyDoNotDisturb(policyFile.doNotDisturb);
        root.popupTimeoutMs = policyFile.popupTimeoutMs;
        if (root.policySaving) return;
        root.confirmedDoNotDisturb = root.doNotDisturb;
        root.confirmedPopupTimeoutMs = root.popupTimeoutMs;
        root.policyState = "available";
        root.policyDetail = "Managed notification policy is active";
    }

    function savePolicy() {
        policyFile.version = 1;
        policyFile.doNotDisturb = root.doNotDisturb;
        policyFile.popupTimeoutMs = root.popupTimeoutMs;
        root.policySaving = true;
        root.policySelfWriteExpected = true;
        policySelfWriteGuard.restart();
        root.policyState = "saving";
        root.policyDetail = "Saving notification policy";
        policyFile.writeAdapter();
    }

    function setDoNotDisturb(enabled) {
        if (!root.policyMutationReady || root.doNotDisturb === enabled) return;
        root.applyDoNotDisturb(enabled);
        root.savePolicy();
    }

    function setPopupTimeout(value) {
        if (!root.policyMutationReady || !root.validPopupTimeout(value)
                || root.popupTimeoutMs === value) return;
        root.popupTimeoutMs = value;
        root.savePolicy();
    }

    function resetPolicy() {
        if (!root.policyResetReady) return;
        if (root.policyState !== "partial" && !root.doNotDisturb
                && root.popupTimeoutMs === 6000) return;
        root.usePolicyDefaults();
        root.savePolicy();
    }

    function policyStatus() {
        return "notification-policy\t1\t" + Quickshell.processId + "\t"
            + (root.policyMutationReady ? "available" : "unavailable");
    }

    function urgencyName(urgency) {
        if (urgency === NotificationUrgency.Critical) {
            return "critical";
        }
        if (urgency === NotificationUrgency.Low) {
            return "low";
        }
        return "normal";
    }

    function add(notification) {
        if (!notification) {
            return;
        }

        notification.tracked = true;
        root.sequence += 1;

        const item = {
            "key": notification.id + "-" + root.sequence,
            "notification": notification,
            "appName": notification.appName || "Notification",
            "summary": notification.summary || "",
            "body": notification.body || "",
            "urgency": notification.urgency,
            "urgencyName": root.urgencyName(notification.urgency),
            "timeoutMs": notification.urgency === NotificationUrgency.Critical ? root.criticalTimeoutMs : root.popupTimeoutMs
        };

        notification.closed.connect(() => root.remove(item.key));
        root.addHistory(item);

        if (root.popupSuppressed && item.urgencyName !== "critical") {
            notification.expire();
            return;
        }

        const existing = root.notifications.filter(n => n.notification && n.notification.id !== notification.id);
        const candidates = [item].concat(existing);
        const overflow = candidates.slice(root.maxVisible);
        root.notifications = candidates.slice(0, root.maxVisible);

        for (const overflowItem of overflow) {
            root.closeItem(overflowItem, false);
        }
    }

    function remove(key) {
        root.notifications = root.notifications.filter(n => n.key !== key);
    }

    function clear() {
        const current = root.notifications.slice();
        root.notifications = [];

        for (const item of current) {
            root.closeItem(item, false);
        }
    }

    function addHistory(item) {
        const entry = {
            "key": item.key,
            "appName": item.appName,
            "summary": item.summary,
            "body": item.body,
            "urgency": item.urgency,
            "urgencyName": item.urgencyName,
            "timestamp": Date.now()
        };

        root.history = [entry].concat(root.history).slice(0, root.maxHistory);
        root.saveHistory();
    }

    function clearHistory() {
        root.history = [];
        root.saveHistory();
    }

    function closeHistory() {
        root.historyVisible = false;
    }

    function openHistory() {
        root.historyVisible = true;
    }

    function toggleHistory() {
        root.historyVisible = !root.historyVisible;
    }

    function historyLatestSummary() {
        return root.history.length > 0 ? root.history[0].summary : "";
    }

    function loadHistory() {
        root.history = (historyFile.notifications || []).slice(0, root.maxHistory);
    }

    function saveHistory() {
        historyFile.notifications = root.history;
        historyFile.writeAdapter();
    }

    function closeItem(item, expired) {
        if (!item) {
            return;
        }

        root.remove(item.key);
        if (!item.notification) {
            return;
        }

        if (expired) {
            item.notification.expire();
        } else {
            item.notification.dismiss();
        }
    }

    function dismiss(key) {
        root.closeItem(root.notifications.find(n => n.key === key), false);
    }

    function expire(key) {
        root.closeItem(root.notifications.find(n => n.key === key), true);
    }

    FileView {
        id: policyFile

        property alias version: policyAdapter.version
        property alias doNotDisturb: policyAdapter.doNotDisturb
        property alias popupTimeoutMs: policyAdapter.popupTimeoutMs

        path: root.policyPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.loadPolicy()
        onFileChanged: {
            if (root.policySelfWriteExpected) {
                root.policySelfWriteExpected = false;
                policySelfWriteGuard.stop();
            } else if (root.policySaving) root.policyReloadPending = true;
            else root.beginPolicyReload(true);
        }
        onSaved: {
            root.confirmedDoNotDisturb = root.doNotDisturb;
            root.confirmedPopupTimeoutMs = root.popupTimeoutMs;
            root.policySaving = false;
            if (root.policyReloadPending) {
                root.policyReloadPending = false;
                root.policyState = "loading";
                root.policyDetail = "Reloading notification policy";
                Qt.callLater(policyFile.reload);
            } else {
                root.policyState = "available";
                root.policyDetail = "Managed notification policy is active";
            }
        }
        onSaveFailed: error => {
            root.policySelfWriteExpected = false;
            policySelfWriteGuard.stop();
            root.applyDoNotDisturb(root.confirmedDoNotDisturb);
            root.popupTimeoutMs = root.confirmedPopupTimeoutMs;
            root.policySaving = false;
            if (root.policyReloadPending) {
                root.policyReloadPending = false;
                root.policyState = "loading";
                root.policyDetail = "Reloading notification policy after save error " + error;
                Qt.callLater(policyFile.reload);
            } else {
                root.policyState = "unavailable";
                root.policyDetail = "Notification policy could not be saved (error " + error + ")";
            }
        }
        onLoadFailed: error => {
            root.usePolicyDefaults();
            if (error === 2) {
                root.policyState = "defaults";
                root.policyDetail = "Default notification policy is active";
                Qt.callLater(root.savePolicy);
            } else {
                root.policyState = "unavailable";
                root.policyDetail = "Notification policy could not be loaded";
            }
        }

        // qmllint disable unresolved-type
        adapter: JsonAdapter {
            id: policyAdapter

            property int version: 0
            property bool doNotDisturb: false
            property int popupTimeoutMs: 6000
        }
    }

    Timer {
        id: policySelfWriteGuard

        interval: 500
        repeat: false
        onTriggered: root.policySelfWriteExpected = false
    }

    FileView {
        id: historyFile

        property alias notifications: historyAdapter.notifications

        path: root.historyPath
        printErrors: false
        onLoaded: root.loadHistory()
        onLoadFailed: error => {
            if (error === 2) {
                root.saveHistory();
            }
        }

        // qmllint disable unresolved-type
        adapter: JsonAdapter {
            id: historyAdapter

            property var notifications: []
        }
    }

    NotificationServer {
        id: server

        keepOnReload: false
        actionsSupported: false
        bodySupported: true
        bodyMarkupSupported: false
        imageSupported: false
        persistenceSupported: true

        onNotification: notification => root.add(notification)
    }
}
