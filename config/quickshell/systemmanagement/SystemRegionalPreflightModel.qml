import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import "SystemRegionalPreflightProtocol.js" as Protocol

Scope {
    id: root

    property bool active: false
    property var current: null
    property var result: null
    property int serial: 0
    readonly property bool busy: root.current !== null
    signal completed(var outcome)

    onActiveChanged: { if (!root.active) root.cancel(); }

    function argumentsFor(command, selection, argument) {
        if (command === "regional-choices")
            return ["timezone", "locale"].indexOf(selection) >= 0 && argument === "" ? [selection] : null;
        if (command !== "regional-preview" || typeof argument !== "string") return null;
        if (selection === "timezone-set" && Protocol.timezone(argument)) return [selection, argument];
        if (selection === "ntp-set" && ["enabled", "disabled"].indexOf(argument) >= 0) return [selection, argument];
        if (selection === "locale-set" && argument.slice(0, 5) === "LANG=" && Protocol.locale(argument.slice(5)))
            return [selection, argument];
        return null;
    }

    function requestChoices(kind) { return root.start("regional-choices", kind, ""); }
    function requestPreview(action, argument) { return root.start("regional-preview", action, argument); }

    function start(command, selection, argument) {
        const args = root.argumentsFor(command, selection, argument);
        if (!root.active || root.current !== null || args === null) return false;
        const run = { id: root.serial + 1, command: command, selection: selection,
            parser: Protocol.create(command, selection, argument), started: false,
            stopping: false, retired: false, finished: false, failure: null };
        // Claim the source owner before any property can invoke a UI callback.
        root.current = run;
        if (root.current !== run || run.retired) return false;
        root.serial = run.id;
        if (root.current !== run || run.retired) return false;
        root.result = null;
        if (root.current !== run || run.retired || !root.active) return false;
        reader.command = Commands.systemManagementCommand(command, args);
        Qt.callLater(function() { root.launch(run); });
        return true;
    }

    function launch(run) {
        if (root.current !== run || run.retired || run.finished || run.started) return;
        if (!root.active) { root.cancel(); return; }
        run.started = true;
        readDeadline.restart();
        reader.running = true;
    }

    function cancel() {
        const run = root.current;
        if (run !== null) run.retired = true;
        root.result = null;
        if (run === null || root.current !== run || run.finished) return;
        if (!run.started) root.finish(run, -1, false);
        else root.stop(run);
    }

    function stop(run) {
        if (root.current !== run || run.finished || run.stopping) return;
        run.stopping = true;
        readDeadline.stop();
        reader.signal(15);
        stopDeadline.restart();
    }

    function fail(run, code, detail) {
        if (root.current !== run || run.finished || run.retired || run.failure !== null) return;
        run.failure = { code: code, detail: detail };
        root.stop(run);
    }

    function consume(data) {
        const run = root.current;
        if (run === null || !run.started || run.retired || run.finished || run.failure !== null) return;
        if (!Protocol.consume(run.parser, data)) root.fail(run, "malformed", run.parser.failure);
    }

    function finish(run, exitCode, normalExit) {
        if (run === null || root.current !== run || run.finished) return;
        run.finished = true;
        readDeadline.stop();
        stopDeadline.stop();
        try {
            if (!run.retired) {
                // The shell can start while the selected helper is absent.
                // Do not relabel a helper's already-emitted protocol as missing.
                if (run.failure === null && normalExit && exitCode === 127 && run.parser.offset === 0)
                    run.failure = { code: "missing-provider", detail: "The regional helper is unavailable. Check the installed desktop helpers." };
                if (run.failure === null && !Protocol.finish(run.parser, exitCode, normalExit))
                    run.failure = { code: "malformed", detail: run.parser.failure };
                const error = run.failure || run.parser.error;
                const outcome = { id: run.id, command: run.command, selection: run.selection,
                    status: error === null ? "available" : "failure", error: error,
                    choices: error === null ? run.parser.choices.slice() : [],
                    preview: error === null ? run.parser.preview : null };
                root.result = outcome;
                // Closing from resultChanged must not publish a stale completion.
                if (root.current === run && !run.retired) root.completed(outcome);
            }
        } finally {
            // Completion callbacks still see the old owner. New requests can
            // start only after all old timers and publication have finished.
            if (root.current === run) root.current = null;
        }
    }

    Timer {
        id: readDeadline
        interval: 25000
        onTriggered: {
            const run = root.current;
            if (run !== null) root.fail(run, "timeout", "Regional preflight timed out. Retry the read explicitly.");
        }
    }
    Timer {
        id: stopDeadline
        interval: 3000
        onTriggered: { if (root.current !== null && root.current.stopping) reader.signal(9); }
    }
    Process {
        id: reader
        stdout: StdioCollector { id: output; waitForEnd: false; onDataChanged: root.consume(data) }
        stderr: StdioCollector {
            waitForEnd: false
            onDataChanged: {
                const run = root.current;
                if (run !== null && run.started && data.byteLength > 8192)
                    root.fail(run, "malformed", "Regional preflight error output exceeded its limit.");
            }
        }
        onExited: (exitCode, exitStatus) => {
            root.consume(output.data);
            root.finish(root.current, exitCode, exitStatus === 0);
        }
        // FailedToStart has no exited signal. Never consume retained collector
        // data here, or confuse an old exit with a queued unlaunched replacement.
        onRunningChanged: {
            const run = root.current;
            if (!running && run !== null && run.started && !run.finished) {
                run.failure = { code: "missing-provider", detail: "The regional helper could not start. Check the installed desktop helpers." };
                root.finish(run, -1, false);
            }
        }
    }
}
