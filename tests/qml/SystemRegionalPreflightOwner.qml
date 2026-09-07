import QtQuick
import Quickshell
import qs.systemmanagement

ShellRoot {
    id: root
    property string scenario: Quickshell.env("DWM_PREFLIGHT_SCENARIO")
    property int phase: 0
    property int assertions: 0
    property int completions: 0
    property bool starting: false
    property bool advancing: false
    property bool startedTest: false
    property bool done: false
    property bool canceled: false
    property bool provisional: false
    property double startedAt: 0
    property double canceledAt: 0
    property var received: null
    property var oldRun: null
    property var lastRun: null
    property var requests: [["regional-choices", "timezone", ""], ["regional-choices", "locale", ""],
        ["regional-preview", "timezone-set", "Etc/UTC"], ["regional-preview", "ntp-set", "enabled"],
        ["regional-preview", "locale-set", "LANG=C"], ["regional-choices", "timezone", ""]]
    readonly property bool replaces: ["close", "kill-close", "timeout", "cancel-queued", "cancel-claim", "close-result"].indexOf(scenario) >= 0

    function check(condition, detail) {
        assertions++;
        if (!condition) {
            console.error("Regional preflight owner FAILED: " + scenario + ": " + detail);
            throw new Error(detail);
        }
    }
    function scheduleAdvance() {
        if (!startedTest || starting || advancing || done || model.current !== null) return;
        advancing = true;
        Qt.callLater(function() { root.advancing = false; root.afterIdle(); });
    }
    function begin() {
        received = null;
        starting = true;
        model.active = true;
        const request = scenario === "success" ? requests[phase]
            : phase === 1 ? requests[1] : requests[3];
        const accepted = model.start(request[0], request[1], request[2]);
        check(accepted === !(scenario === "cancel-claim" && phase === 0), "Expected request admission");
        if (scenario === "cancel-queued" && phase === 0) model.cancel();
        if (oldRun !== null) {
            model.launch(oldRun);
            model.finish(oldRun, 0, true);
            model.fail(oldRun, "timeout", "Stale callback");
            check(model.current !== oldRun, "Retired callbacks cannot own replacement");
        }
        if (model.current !== null) check(!model.requestChoices("locale"), "Pre-output duplicate rejected");
        starting = false;
        scheduleAdvance();
    }
    function afterIdle() {
        if (done || model.current !== null) return;
        check(!model.busy, "Source owner and public busy state released");
        if (replaces && phase === 0) {
            if (scenario === "timeout") {
                check(received !== null && received.error.code === "timeout", "Deadline reports typed failure");
                check(Date.now() - startedAt >= 27500, "Real deadline retains kill grace");
            } else {
                check(received === null && model.result === null && completions === 0, "Retired read publishes no completion or result");
                if (scenario === "kill-close") check(Date.now() - canceledAt >= 2800, "Close retains ownership through kill grace");
            }
            oldRun = lastRun;
            phase++;
            begin();
            return;
        }
        if (scenario === "success" && phase < requests.length - 1) {
            oldRun = lastRun;
            phase++;
            begin();
            return;
        }
        check(completions === (scenario === "success" ? 6 : scenario === "timeout" ? 2 : 1), "No duplicate or missing completion");
        if (["success", "typed-error", "wrong-exit"].indexOf(scenario) >= 0 || replaces)
            check(provisional, "Complete bytes were observed before process exit without a result");
        const retained = model.result;
        model.consume(new Uint8Array([0]).buffer);
        model.finish(oldRun, 0, true);
        check(model.result === retained, "Late data and exit leave retained result unchanged");
        model.active = false;
        check(model.result === null && !model.busy, "Close clears retained optional data");
        done = true;
        console.info("Regional preflight owner tests: PASS (" + scenario + ", " + assertions + " assertions)");
        Qt.quit();
    }
    function run() {
        check(!model.requestChoices("timezone"), "Hidden owner cannot start a read");
        model.active = true;
        for (const args of [["unknown", "timezone", ""], ["regional-choices", "unknown", ""],
                ["regional-choices", "timezone", "extra"], ["regional-preview", "unknown", "enabled"],
                ["regional-preview", "timezone-set", "../etc"], ["regional-preview", "timezone-set", null],
                ["regional-preview", "ntp-set", "yes"], ["regional-preview", "locale-set", "LANG="],
                ["regional-preview", "locale-set", "LANG=C\n"]])
            check(!model.start(...args), "Invalid fixed request rejected before helper");
        startedTest = true;
        startedAt = Date.now();
        begin();
    }
    SystemRegionalPreflightModel {
        id: model
        onCurrentChanged: {
            if (current !== null) {
                root.check(!model.requestChoices("timezone"), "Reentrant owner publication cannot overlap");
                root.lastRun = current;
                if (root.scenario === "cancel-claim" && root.phase === 0) model.cancel();
            } else root.scheduleAdvance();
        }
        onResultChanged: {
            if (result !== null && root.scenario === "close-result" && root.phase === 0)
                model.active = false;
        }
        onCompleted: outcome => {
            root.completions++;
            root.received = outcome;
            root.check(model.current !== null && !model.requestChoices("timezone"), "Completion retains owner through callbacks");
            const success = root.scenario === "success" || root.phase === 1;
            root.check(outcome.status === (success ? "available" : "failure"), "Typed result status");
            if (success) {
                root.check(outcome.error === null, "Successful result has no error");
                if (outcome.command === "regional-choices")
                    root.check(JSON.stringify(outcome.choices) === JSON.stringify(outcome.selection === "timezone"
                        ? ["America/Chicago", "Etc/UTC"] : ["C", "en_US.utf8"]), "Exact catalog retained across collector reuse");
                else root.check(outcome.preview.detail === "Full fixture detail", "Complete preview retained");
            } else {
                const expected = root.scenario === "typed-error" ? "permission-denied"
                    : root.scenario === "timeout" ? "timeout" : root.scenario === "failed-start" ? "missing-provider" : "malformed";
                root.check(outcome.error.code === expected && outcome.choices.length === 0 && outcome.preview === null,
                    "Failed result withholds provisional data and preserves error");
            }
        }
    }
    Timer {
        interval: 10
        repeat: true
        running: !root.done
        onTriggered: {
            const run = model.current;
            if (run === null) return;
            if (run.parser.complete && !run.finished) {
                root.check(model.result === null, "Result remains provisional before EOF");
                root.provisional = true;
            }
            if (["close", "kill-close"].indexOf(root.scenario) >= 0 && root.phase === 0 && run.parser.header && !root.canceled) {
                root.canceled = true;
                root.canceledAt = Date.now();
                model.active = false;
                root.check(model.current !== null && !model.requestChoices("locale"), "Close retains launched owner until exit");
            }
        }
    }
    Timer { interval: 40000; running: true; onTriggered: { console.error("Regional preflight owner FAILED: fixture timeout"); Qt.quit(); } }
    Component.onCompleted: Qt.callLater(root.run)
}
