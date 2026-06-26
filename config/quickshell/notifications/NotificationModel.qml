import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Scope {
    id: root

    property var notifications: []
    property int sequence: 0

    readonly property int popupTimeoutMs: 6000
    readonly property int criticalTimeoutMs: 10000
    readonly property int maxVisible: 4

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
