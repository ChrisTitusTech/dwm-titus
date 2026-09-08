import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

ShellRoot {
    id: root
    property bool manual: Quickshell.env("DWM_CLOCK_MANUAL") === "1"
    property int assertions: 0

    ClockModel { id: clock; timezoneState: ({ status: "available", value: "Etc/UTC" }) }

    function check(value, message) {
        assertions++;
        if (!value) throw new Error(message);
    }
    function checkText() {
        const current = new Date(clock.timestamp);
        check(clock.panelText === Qt.formatDateTime(current, "ddd dd MMM - HH:mm"), "Panel format and epoch");
        check(clock.settingsText === Qt.formatDateTime(current, "dddd, dd MMMM yyyy - HH:mm t"), "Settings format and epoch");
        check(current.getSeconds() === 0, "Minute precision is preserved");
    }
    function run() {
        try {
            check(clock.initialized && clock.observedTimezone === "Etc/UTC", "Initial state is applied after construction");
            checkText();
            // Distinguish the retained instant from a fresh source.date read.
            const oldEpoch = clock.timestamp - 60000;
            clock.timestamp = oldEpoch;
            clock.panelText = "unchanged";
            clock.settingsText = "unchanged";
            for (const state of [null, {}, {status: "partial", value: "America/Chicago"},
                {status: "unavailable", value: "America/Chicago"}, {status: "available", value: ""},
                {status: "available", value: "unknown"}, {status: "available", value: 123},
                {status: "available", value: "Etc/UTC"}]) {
                clock.timezoneState = state;
                check(clock.observedTimezone === "Etc/UTC", "Only a new available identity refreshes timezone");
                check(clock.panelText === "unchanged" && clock.settingsText === "unchanged", "Ignored states preserve display");
            }
            clock.timezoneState = {status: "available", value: "America/Chicago"};
            check(clock.observedTimezone === "America/Chicago", "Verified identity is accepted");
            check(clock.timestamp === oldEpoch, "Timezone refresh does not replace the source epoch");
            checkText();
            clock.panelText = "unchanged";
            clock.settingsText = "unchanged";
            clock.timezoneState = {status: "available", value: "America/Chicago"};
            check(clock.panelText === "unchanged" && clock.settingsText === "unchanged", "Repeated snapshots do not repeat timezone refresh");
            clock.timezoneState = {status: "available", value: "Etc/UTC"};
            check(clock.observedTimezone === "Etc/UTC", "Returning to a previous timezone refreshes again");
            checkText();
            clock.panelText = "stale";
            clock.settingsText = "stale";
            clock.refreshDisplay();
            checkText();
            console.info("Shared clock tests: PASS (" + assertions + " assertions)");
        } catch (error) {
            console.error("Shared clock FAILED: " + error);
        } finally {
            Qt.quit();
        }
    }
    Component.onCompleted: { if (!manual) Qt.callLater(root.run); }

    // Test-only control in an isolated copied configuration, never managed IPC.
    IpcHandler {
        target: "clocktest"
        function sample(): string {
            return JSON.stringify({epoch: clock.timestamp, panel: clock.panelText,
                settings: clock.settingsText, observed: clock.observedTimezone,
                offset: new Date(clock.timestamp).getTimezoneOffset()});
        }
        function publish(status: string, zone: string): string {
            if (!root.manual) return "disabled";
            clock.timezoneState = {status: status, value: zone};
            return sample();
        }
        function stop(): void { Qt.quit(); }
    }

    FloatingWindow {
        visible: root.manual
        title: "Shared clock fixture"
        implicitWidth: 640
        implicitHeight: 180
        color: Theme.menuBackground
        Column {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16
            UiText { text: "Panel: " + clock.panelText }
            UiText { width: parent.width; text: "Settings: " + clock.settingsText; wrapMode: Text.WordWrap }
        }
    }
}
