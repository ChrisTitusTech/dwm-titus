import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root
    property bool visible: false
    property var targetScreen: null
    property var workspaceNames: []
    property var windows: []
    property var rows: []
    property string query: ""
    property string message: ""
    property int selectedIndex: 0
    readonly property bool busy: activation.running

    function tagLabel(mask) {
        const names = [];
        for (let index = 0; index < 31; index++) {
            if (mask & (1 << index)) names.push(root.workspaceNames[index] || String(index + 1));
        }
        return names.join(", ");
    }
    function filter() {
        const previous = root.rows[root.selectedIndex];
        const query = root.query.trim().toLowerCase();
        root.rows = root.visible ? root.windows.filter(function(window) {
            return (window.title + " " + window.app + " " + root.tagLabel(window.tags)).toLowerCase().indexOf(query) >= 0;
        }) : [];
        const restored = previous ? root.rows.findIndex(function(window) { return window.id === previous.id; }) : -1;
        root.selectedIndex = restored >= 0 ? restored : Math.max(0, Math.min(root.selectedIndex, root.rows.length - 1));
    }
    function parse(text) {
        try {
            const state = JSON.parse(text);
            if (state.protocol !== 1 || !Array.isArray(state.windows)) throw new Error("Invalid window list");
            if (state.available === false) root.message = state.detail;
            root.windows = state.windows;
            root.filter();
        } catch (error) { root.message = "Could not read the window list"; }
    }
    function openOnScreen(screen) {
        if (root.busy) return;
        root.targetScreen = screen;
        root.query = "";
        root.message = "";
        root.selectedIndex = 0;
        root.visible = true;
    }
    function close() {
        root.visible = false;
        root.windows = [];
        root.rows = [];
    }
    function toggle(screen) { if (root.visible) root.close(); else root.openOnScreen(screen); }
    function selectRelative(delta) {
        if (root.rows.length) root.selectedIndex = ((root.selectedIndex + delta) % root.rows.length + root.rows.length) % root.rows.length;
    }
    function activate(index) {
        if (root.busy || index < 0 || index >= root.rows.length) return;
        const window = root.rows[index];
        root.close();
        activation.command = Commands.helperCommand("dwm-window-overview", "activate", [window.id], true);
        // Let the overview unmap before dwm focuses the selected client.
        Qt.callLater(function() { activation.running = true; });
    }
    onQueryChanged: root.filter()

    Process {
        command: Commands.helperCommand("dwm-window-overview", "watch", [], true)
        running: root.visible
        stdout: SplitParser { onRead: data => root.parse(data) }
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.message = text.trim(); } }
        onExited: { // qmllint disable signal-handler-parameters
            if (root.visible) root.message = "Window tracking stopped; close and reopen to retry";
        }
    }
    Process {
        id: activation
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.message = text.trim(); } }
        onExited: (code, status) => { // qmllint disable signal-handler-parameters
            if (code !== 0 || status !== 0) root.visible = true;
        }
    }
}
