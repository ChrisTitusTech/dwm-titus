import QtQuick
import Quickshell

Scope {
    id: root

    // Only the system provider's published timezone state belongs here, never
    // a selected choice or an unverified mutation target.
    property var timezoneState: null
    property string observedTimezone: ""
    property bool initialized: false
    property string panelText: ""
    property string settingsText: ""
    property double timestamp: 0

    function refreshDisplay() {
        if (!root.initialized) return;
        // Capture the epoch at ticks, not after a timezone change: the source
        // retains local wall-clock fields that Qt can reinterpret in a new zone.
        // Reassigning an equal date alone also cannot notify text bindings.
        const current = new Date(root.timestamp);
        root.panelText = Qt.formatDateTime(current, "ddd dd MMM - HH:mm");
        root.settingsText = Qt.formatDateTime(current, "dddd, dd MMMM yyyy - HH:mm t");
    }

    function refreshTimezone() {
        const state = root.timezoneState;
        if (!root.initialized || !state || state.status !== "available"
                || typeof state.value !== "string" || state.value.length === 0
                || state.value === "unknown" || state.value === root.observedTimezone) return;
        root.observedTimezone = state.value;
        Date.timeZoneUpdated();
        root.refreshDisplay();
    }

    onTimezoneStateChanged: root.refreshTimezone()
    Component.onCompleted: {
        root.timestamp = source.date.getTime();
        root.initialized = true;
        root.refreshTimezone();
        root.refreshDisplay();
    }

    SystemClock {
        id: source
        precision: SystemClock.Minutes
        onDateChanged: {
            if (root.initialized) {
                root.timestamp = source.date.getTime();
                root.refreshDisplay();
            }
        }
    }
}
