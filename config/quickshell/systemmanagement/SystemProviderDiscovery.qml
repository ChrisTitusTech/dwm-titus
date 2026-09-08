import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemDiscoveryCycle.js" as Cycle

Scope {
    id: root

    // Only these fixed provider commands are selectable; no caller-supplied argv.
    property string domain: "updates"
    readonly property var definition: root.domainDefinition(root.domain)

    signal snapshotRequested()
    signal invalidated()
    signal ownerArrived()
    property bool externalUnresolved: false
    property string externalDetail: ""
    property var cycle: Cycle.create()
    property bool visible: false
    property bool monitorOwned: false
    property bool stopping: false
    property bool restartPending: false
    property bool ready: false
    property bool failed: false
    property bool unresolved: false
    property string phase: "idle"
    readonly property bool fresh: root.definition !== null && root.visible && root.ready && !root.failed && !root.unresolved && !root.externalUnresolved && root.phase === "idle"
    readonly property string detail: !root.visible ? "" : root.failed
        ? "Live " + root.domainLabel() + " monitoring is unavailable. Reload status to retry; readable state is preserved."
        : root.unresolved
        ? "The " + root.domainLabel() + " state changed during the settling read. Reload status to reconcile it; automatic rereads are paused."
        : !root.ready ? "Connecting to " + root.domainLabel() + " change notifications..." : root.externalDetail

    function domainDefinition(value) {
        if (value === "updates") return { action: "watch-updates", args: [], prefix: "update-event", label: "update" };
        if (value === "time") return { action: "watch-time", args: [], prefix: "time-event", label: "time" };
        if (value === "locale") return { action: "watch-regional", args: ["locale"], prefix: "regional-event", label: "locale" };
        if (value === "accounts") return { action: "watch-accounts", args: [], prefix: "accounts-event", label: "account" };
        if (value === "printers") return { action: "watch-units", args: ["printers"], prefix: "units-event", label: "printer" };
        return null;
    }

    function domainLabel() { return root.definition === null ? "unsupported service" : root.definition.label; }

    onDomainChanged: {
        // Neither an old read token nor a failed-monitor fallback can certify
        // a replacement domain before its own subscription handshake.
        if (!root.visible) return;
        root.ready = false;
        root.failed = false;
        Cycle.begin(root.cycle);
        root.publish();
        root.invalidated();
        root.stopMonitor();
        root.startMonitor();
    }

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
        const selected = root.domainDefinition(root.domain);
        if (selected === null) {
            root.failed = true;
            root.invalidated();
            root.requestPending();
            return;
        }
        monitor.command = Commands.systemManagementCommand(selected.action, selected.args);
        monitor.eventPrefix = selected.prefix;
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
        if (line === monitor.eventPrefix + "\tready" && !root.ready) {
            setupDeadline.stop();
            root.ready = true;
            root.requestPending();
        } else if (line === monitor.eventPrefix + "\tchanged" && root.ready) root.invalidate();
        else if (root.domain === "time" && line === monitor.eventPrefix + "\towner-arrived" && root.ready) root.ownerArrived();
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
        property string eventPrefix: ""
        stdout: SplitParser { onRead: line => root.event(line) }
        onExited: root.finished()
        onRunningChanged: { if (!running && root.monitorOwned) root.finished(); }
    }
}
