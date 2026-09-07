import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.systemmanagement as System

ShellRoot {
    id: root
    property var domains: ["time", "locale", "accounts", "printers", "updates"]
    property int domainIndex: 0
    property int stage: 0
    property int assertions: 0
    property int requests: 0
    property int requestsBefore: 0
    property int invalidations: 0
    property int expectedEvents: 0
    property var token: null
    property string continuation: ""
    property bool done: false
    property bool replacingDomain: false
    property bool replaceAfterExit: false

    function check(condition, detail) {
        root.assertions++;
        if (!condition) {
            console.error("Provider discovery FAILED: " + observer.domain + ": " + detail);
            Qt.callLater(function() { Qt.quit(); });
            throw new Error(detail);
        }
    }

    function control(action, next) {
        if (action === "emit") root.expectedEvents = root.invalidations + 100;
        root.continuation = next;
        controller.command = Commands.systemManagementCommand("fixture-control", [observer.domain, action]);
        controller.running = true;
    }

    function controlled() {
        if (root.continuation === "first") root.stage = 1;
        else if (root.continuation === "settling") root.stage = 2;
        else if (root.continuation === "blocked") root.stage = 3;
        else if (root.continuation === "bad") { root.stage = 5; observer.open(); }
        else if (root.continuation === "next") {
            root.domainIndex++;
            observer.domain = root.domains[root.domainIndex];
            root.stage = 0;
            observer.open();
        } else if (root.continuation === "replacement") {
            observer.domain = "time";
            root.stage = 8;
            observer.open();
        } else if (root.continuation === "replacement-ready") {
            root.finish(observer.take());
            root.check(observer.fresh, "Fresh fixed replacement command is usable");
            observer.close();
            observer.open();
            root.replacingDomain = true;
            observer.domain = "printers";
            root.replacingDomain = false;
            root.check(!observer.ready && !observer.failed && !observer.canTake(),
                "Queued replacement cannot use failed fallback before readiness");
            root.stage = 10;
        } else if (root.continuation === "queued-ready") {
            root.finish(observer.take());
            root.check(observer.fresh, "Queued replacement gets its own baseline");
            observer.close();
            root.stage = 11;
        } else if (root.continuation === "exit-ready") {
            root.finish(observer.take());
            root.check(observer.fresh, "Exit callback replacement has a fresh baseline");
            observer.close();
            root.stage = 15;
        }
    }

    function finish(token) {
        observer.beforePublish(token);
        observer.complete(token, true);
    }

    function advance() {
        if (root.done || controller.running) return;
        if (root.stage === 0 && observer.ready) {
            root.check(observer.monitorOwned && !observer.failed && observer.canTake(), "Fixed command reaches readiness before read");
            root.token = observer.take();
            root.check(root.token !== null && !observer.fresh, "Initial read owns its token");
            root.stage = -1;
            root.control("emit", "first");
        } else if (root.stage === 1 && root.invalidations >= root.expectedEvents && observer.cycle.dirty) {
            root.finish(root.token);
            root.check(observer.phase === "settling-pending", "Event burst reserves one settling read");
            root.token = observer.take();
            root.stage = -1;
            root.control("emit", "settling");
        } else if (root.stage === 2 && root.invalidations >= root.expectedEvents && observer.unresolved) {
            root.finish(root.token);
            root.check(observer.phase === "blocked" && !observer.canTake() && !observer.fresh,
                "Dirty settling stops automatic reads");
            root.requestsBefore = root.requests;
            root.stage = -1;
            root.control("emit", "blocked");
        } else if (root.stage === 3 && root.invalidations >= root.expectedEvents) {
            root.check(root.requests === root.requestsBefore && observer.phase === "blocked", "Later burst cannot reserve third read");
            observer.refresh();
            root.finish(observer.take());
            root.check(observer.unresolved && observer.phase === "settling-pending", "Explicit retry preserves unresolved evidence");
            root.finish(observer.take());
            root.check(observer.fresh && !observer.unresolved, "Quiet retry clears unresolved evidence");
            observer.invalidate();
            root.token = observer.take();
            observer.close();
            root.finish(root.token);
            observer.event(observer.definition.prefix + "\tchanged");
            root.check(observer.phase === "idle" && !observer.fresh && !observer.canTake(), "Closed callbacks cannot resurrect read cycle");
            root.stage = 4;
        } else if (root.stage === 4 && !observer.monitorOwned) {
            root.stage = -1;
            root.control("wrong-prefix", "bad");
        } else if (root.stage === 5 && observer.failed && !observer.monitorOwned) {
            root.check(observer.canTake() && !observer.ready && observer.detail.indexOf("Reload status") >= 0,
                "Wrong prefix preserves one finite-read fallback and retry guidance");
            root.finish(observer.take());
            root.check(!observer.fresh && !observer.canTake(), "Failed monitoring cannot advertise freshness");
            observer.close();
            root.stage = 6;
        } else if (root.stage === 6 && !observer.monitorOwned) {
            root.stage = -1;
            root.control("quiet", root.domainIndex + 1 < root.domains.length ? "next" : "replacement");
        } else if (root.stage === 8 && observer.ready) {
            root.finish(observer.take());
            root.check(observer.fresh, "Replacement fixture begins with verified freshness");
            observer.invalidate();
            root.token = observer.take();
            root.replacingDomain = true;
            observer.domain = "locale";
            root.replacingDomain = false;
            root.check(!observer.fresh && !observer.ready && !observer.failed,
                "Changed domain cannot inherit old freshness or fallback");
            root.finish(root.token);
            root.check(observer.phase === "initial-pending", "Old read cannot consume replacement baseline");
            root.stage = 9;
        } else if (root.stage === 9 && observer.ready) {
            root.stage = -1;
            root.control("assert-active", "replacement-ready");
        } else if (root.stage === 10 && observer.ready) {
            root.stage = -1;
            root.control("assert-active", "queued-ready");
        } else if (root.stage === 11 && !observer.monitorOwned) {
            observer.domain = "arbitrary-command";
            observer.open();
            root.check(observer.failed && !observer.monitorOwned && observer.canTake(), "Unknown domain never launches a process");
            root.finish(observer.take());
            root.check(!observer.fresh, "Unknown domain cannot advertise freshness");
            observer.close();
            observer.domain = "time";
            observer.open();
            root.stage = 12;
        } else if (root.stage === 12 && observer.ready) {
            root.finish(observer.take());
            root.replaceAfterExit = true;
            root.stage = 13;
            root.control("exit", "exiting");
        } else if (root.stage === 14 && observer.failed && !observer.monitorOwned) {
            root.check(false, "Exit callback replacement lost ownership");
        } else if (root.stage === 14 && observer.ready) {
            root.stage = -1;
            root.control("assert-active", "exit-ready");
        } else if (root.stage === 15 && !observer.monitorOwned) {
            root.done = true;
            console.info("Provider discovery tests: PASS (" + root.assertions + " assertions)");
            Qt.quit();
        }
    }

    System.SystemProviderDiscovery {
        id: observer
        domain: "time"
        onSnapshotRequested: root.requests++
        onInvalidated: {
            root.invalidations++;
            if (root.replaceAfterExit && observer.failed && !observer.monitorOwned) {
                root.replaceAfterExit = false;
                observer.domain = "accounts";
                root.check(!observer.fresh && !observer.canTake(), "Exit replacement waits for its own handshake");
                root.stage = 14;
            }
            if (root.replacingDomain)
                root.check(!observer.ready && !observer.failed && !observer.canTake(),
                    "Replacement invalidation cannot expose a reentrant read");
        }
    }
    Process {
        id: controller
        onExited: (code, status) => {
            root.check(code === 0 && status === 0, "Private fixture control succeeds");
            Qt.callLater(root.controlled);
        }
    }
    Timer { interval: 25; repeat: true; running: !root.done; onTriggered: root.advance() }
    Timer { interval: 30000; running: true; onTriggered: root.check(false, "Scenario timeout at stage " + root.stage) }
    Component.onCompleted: observer.open()
}
