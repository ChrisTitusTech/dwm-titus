import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.systemmanagement as System

ShellRoot {
    id: root
    property var domains: ["storage", "security", "time", "locale", "accounts", "printers", "updates"]
    property int domainIndex: 0
    property int stage: 0
    property bool done: false
    property int assertions: 0
    property int requests: 0
    property int invalidations: 0
    property var retired: null
    property int retiredSerial: -1
    property int retiredGeneration: -1

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Provider generation FAILED: " + observer.domain + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }
    function capture() {
        root.retired = observer.monitor.callbacks;
        root.retiredSerial = observer.monitor.identity.serial;
        root.retiredGeneration = observer.generation;
    }
    function replay() {
        const owner = observer.monitor;
        const requests = root.requests;
        const invalidations = root.invalidations;
        root.check(owner.identity.serial !== root.retiredSerial, "Replacement has distinct launch identity");
        root.retired.line(observer.domain === "storage" ? "mount-monitor-ready" : observer.definition.prefix + "\tready");
        root.retired.line(observer.domain === "storage" ? "mount-change\tmount" : observer.definition.prefix + "\tchanged");
        root.retired.setup();
        root.retired.stop();
        root.retired.finish();
        root.check(observer.monitor === owner && observer.monitorOwned, "Retired exit cannot release replacement");
        root.check(!observer.ready && !observer.failed && !observer.stopping, "Retired parser and deadlines cannot certify or stop replacement");
        root.check(requests === root.requests && invalidations === root.invalidations && !observer.canTake(),
            "Retired callbacks cannot request unmonitored baseline");
    }
    function control(action) {
        controller.command = Commands.systemManagementCommand("fixture-control", [observer.domain, action]);
        controller.running = true;
    }
    function settle() {
        const token = observer.take();
        root.check(token !== null, "Current launch requests its own baseline");
        observer.beforePublish(token);
        observer.complete(token, true);
        root.check(observer.fresh, "Current baseline makes replacement fresh");
    }
    function advance() {
        if (root.done || controller.running) return;
        if (root.stage === 0 && observer.monitorOwned) {
            root.capture();
            observer.close();
            observer.open();
            root.stage = 1;
        } else if (root.stage === 1 && observer.monitorOwned && !observer.stopping
                   && observer.monitor.identity.serial !== root.retiredSerial) {
            root.check(observer.generation !== root.retiredGeneration, "Reopened pane advances generation");
            root.replay();
            root.stage = 2;
            root.control("ready");
        } else if (root.stage === 2 && observer.ready) {
            root.settle();
            root.capture();
            root.stage = 3;
            root.control("exit");
        } else if (root.stage === 3 && !observer.monitorOwned && observer.failed) {
            observer.refresh();
            root.check(observer.generation === root.retiredGeneration, "Explicit monitor retry keeps pane generation");
            root.replay();
            root.stage = 4;
            root.control("ready");
        } else if (root.stage === 4 && observer.ready) {
            root.settle();
            observer.close();
            root.stage = 5;
        } else if (root.stage === 5 && !observer.monitorOwned) {
            root.domainIndex++;
            if (root.domainIndex === root.domains.length) {
                root.done = true;
                console.info("Provider generation tests: PASS (" + root.assertions + " assertions)");
                Qt.quit();
                return;
            }
            observer.domain = root.domains[root.domainIndex];
            root.stage = 0;
            observer.open();
        }
    }
    System.SystemProviderDiscovery {
        id: observer
        domain: "storage"
        onSnapshotRequested: root.requests++
        onInvalidated: root.invalidations++
    }
    Process {
        id: controller
        onExited: (code, status) => root.check(code === 0, "Fixture control succeeded")
    }
    Timer { interval: 15; running: !root.done; repeat: true; onTriggered: root.advance() }
    Timer { interval: 30000; running: !root.done; onTriggered: { root.check(false, "Lifecycle deadline"); Qt.quit(); } }
    Component.onCompleted: observer.open()
}
