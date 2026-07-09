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

    readonly property int popupTimeoutMs: 6000
    readonly property int criticalTimeoutMs: 10000
    readonly property int maxVisible: 4
    readonly property int maxHistory: 50
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/dwm-titus"
    readonly property string historyPath: cacheDir + "/notification-history.json"

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", cacheDir])

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

        const existing = root.notifications.filter(n => n.notification && n.notification.id !== notification.id);
        root.notifications = [item].concat(existing).slice(0, root.maxVisible);
        root.addHistory(item);
    }

    function remove(key) {
        root.notifications = root.notifications.filter(n => n.key !== key);
    }

    function clear() {
        const current = root.notifications.slice();
        for (const item of current) {
            if (item && item.notification) {
                item.notification.dismiss();
            }
        }
        root.notifications = [];
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

    function dismiss(key) {
        const item = root.notifications.find(n => n.key === key);
        if (item && item.notification) {
            item.notification.dismiss();
        }
        root.remove(key);
    }

    function expire(key) {
        const item = root.notifications.find(n => n.key === key);
        if (item && item.notification) {
            item.notification.expire();
        }
        root.remove(key);
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
