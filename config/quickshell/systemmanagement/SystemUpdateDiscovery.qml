import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemDiscoveryCycle.js" as Cycle

Scope {
    id: root

    signal snapshotRequested()
    signal invalidated()
    property var cycle: Cycle.create()
    property bool visible: false
    property bool monitorOwned: false
    property bool stopping: false
    property bool restartPending: false
    property bool ready: false
    property bool failed: false
    property bool unresolved: false
    property string phase: "idle"
    readonly property bool fresh: root.visible && root.ready && !root.failed && !root.unresolved && root.phase === "idle"
    readonly property string detail: !root.visible ? "" : root.failed
        ? "Live update monitoring is unavailable. Reload status to retry; readable package state is preserved."
        : root.unresolved
        ? "Update state changed during the settling read. Reload status to reconcile it; automatic rereads are paused."
        : !root.ready ? "Connecting to update change notifications..." : ""

    function publish() {
        root.unresolved = root.cycle.unresolved;
        root.phase = root.cycle.phase;
    }

    function requestPending() {
        if (root.visible && (root.ready || root.failed) && Cycle.pending(root.cycle))
            root.snapshotRequested();
    }

    function open() {
        root.visible = true;
        Cycle.begin(root.cycle);
        root.publish();
        root.startMonitor();
    }

    function close() {
        root.visible = false;
        root.restartPending = false;
        Cycle.close(root.cycle);
        root.publish();
        root.stopMonitor();
    }

    function refresh() {
        if (!root.visible) return;
        Cycle.begin(root.cycle);
        root.publish();
        if (!root.monitorOwned || root.stopping) root.startMonitor();
        root.requestPending();
    }

    function invalidate() {
        Cycle.invalidate(root.cycle);
        root.publish();
        root.invalidated();
        root.requestPending();
    }

    function canTake() {
        return root.visible && (root.ready || root.failed) && Cycle.pending(root.cycle);
    }

    function take() {
        if (!root.canTake()) return null;
        const token = Cycle.take(root.cycle);
        root.publish();
        return token;
    }

    function beforePublish(token) { Cycle.beforePublish(root.cycle, token); }

    function complete(token, successful) {
        Cycle.complete(root.cycle, token, successful);
        root.publish();
        // Process.runningChanged for the old snapshot follows its exit signal.
        Qt.callLater(root.requestPending);
    }

    function startMonitor() {
        if (!root.visible) return;
        if (root.monitorOwned) {
            if (root.stopping) {
                root.restartPending = true;
                // A new explicit cycle must wait for replacement subscriptions,
                // not consume the previous monitor's failed-read fallback.
                root.ready = false;
                root.failed = false;
            }
            return;
        }
        root.restartPending = false;
        root.ready = false;
        root.failed = false;
        root.stopping = false;
        root.monitorOwned = true;
        setupDeadline.restart();
        monitor.running = true;
    }

    function stopMonitor() {
        root.ready = false;
        setupDeadline.stop();
        if (!root.monitorOwned || root.stopping) return;
        root.stopping = true;
        monitor.signal(15);
        stopDeadline.restart();
    }

    function failMonitor() {
        if (!root.monitorOwned || root.stopping) return;
        root.failed = true;
        root.invalidated();
        root.stopMonitor();
        root.requestPending();
    }

    function event(line) {
        if (!root.monitorOwned || root.stopping || !root.visible) return;
        if (line === "update-event\tready" && !root.ready) {
            setupDeadline.stop();
            root.ready = true;
            root.requestPending();
        } else if (line === "update-event\tchanged" && root.ready) root.invalidate();
        else root.failMonitor();
    }

    function finished() {
        if (!root.monitorOwned) return;
        const restart = root.restartPending;
        root.monitorOwned = false;
        root.ready = false;
        setupDeadline.stop();
        stopDeadline.stop();
        if (!root.visible) return;
        if (restart) Qt.callLater(root.startMonitor);
        else {
            root.failed = true;
            root.invalidated();
            root.requestPending();
        }
    }

    Timer { id: setupDeadline; interval: 12000; repeat: false; onTriggered: root.failMonitor() }
    Timer { id: stopDeadline; interval: 1500; repeat: false; onTriggered: monitor.signal(9) }
    Process {
        id: monitor
        command: Commands.systemManagementCommand("watch-updates", [])
        stdout: SplitParser { onRead: line => root.event(line) }
        onExited: root.finished()
        onRunningChanged: { if (!running && root.monitorOwned) root.finished(); }
    }
}
