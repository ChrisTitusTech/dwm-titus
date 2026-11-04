import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root
    property bool visible: false
    property string location: ""
    property string unit: "c"
    property var weather: null
    property double fetched: 0
    property string message: ""
    readonly property bool busy: process.running
    property bool initialized: false
    function parse(text) {
        if (!text.trim()) return;
        try {
            const value = JSON.parse(text);
            if (value.protocol !== 1) return;
            root.location = value.location;
            root.unit = value.unit;
            root.weather = value.weather;
            root.fetched = value.fetched;
        } catch (error) { root.message = "Could not read saved weather"; }
    }
    function toggle() {
        root.visible = !root.visible;
        if (root.visible && !root.initialized && !root.busy) {
            root.initialized = true;
            process.command = Commands.checkedCommand(Commands.helperCommand("dwm-weather", "status", [], true));
            process.running = true;
        }
    }
    function close() { root.visible = false; }
    function fetch(location, unit) {
        if (root.busy) return;
        root.message = "";
        process.command = Commands.checkedCommand(Commands.helperCommand("dwm-weather", "fetch", [location, unit], true));
        process.running = true;
    }
    Process {
        id: process
        stdout: StdioCollector { onStreamFinished: root.parse(text) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.message = text.trim(); } }
    }
}
