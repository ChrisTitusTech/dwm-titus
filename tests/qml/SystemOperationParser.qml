import QtQuick
import Quickshell
import Quickshell.Io
import "SystemOperationProtocol.js" as Protocol

ShellRoot {
    id: root
    property string operationId: "op-11111111111111111111111111111111"
    property string header: "system-management-protocol\t1\t0\n"
    property var streamParser: null
    property bool sawLivePending: false
    property int assertions: 0

    function check(condition, detail) {
        root.assertions++;
        if (!condition) throw new Error(detail);
    }

    function operation(state, action, detail) {
        action = action || "updates-refresh";
        return ["operation", root.operationId, action, Protocol.actionKind(action), state,
            "unknown", "no", detail || "Fixture"].join("\t") + "\n";
    }

    function audit(state, action) {
        action = action || "updates-refresh";
        return ["audit", root.operationId, action, Protocol.actionKind(action), state,
            "2026-09-05T12:00:00Z", "2026-09-04T12:00:00Z", "Clock rollback is valid"].join("\t") + "\n";
    }

    function fixture(state, action) {
        action = action || "updates-refresh";
        let text = root.header + root.operation("pending", action);
        if (state === "succeeded") text += root.operation("running", action);
        if (state === "permission-denied") text += root.operation("authorizing", action);
        if (state === "failed") text += "error\t" + Protocol.owner(action) + "\tconflict\tFixture failure\n";
        return text + root.operation(state, action) + root.audit(state, action) + "complete\toperation\n";
    }

    function bytes(text) {
        const encoded = unescape(encodeURIComponent(text));
        const result = new Uint8Array(encoded.length);
        for (let i = 0; i < encoded.length; i++) result[i] = encoded.charCodeAt(i);
        return result.buffer;
    }

    function parse(text, code, replay) {
        const parser = Protocol.create(root.operationId, "");
        return Protocol.consume(parser, root.bytes(text)) && Protocol.finish(parser, code, true, replay === true);
    }

    function unitTests() {
        for (const action of ["updates-refresh", "updates-install-all", "timezone-set", "ntp-set",
                "locale-set", "accounts-open", "password-open", "printers-open", "sources-open"]) {
            for (const state of ["succeeded", "permission-denied", "failed", "interrupted", "canceled"]) {
                root.check(root.parse(root.fixture(state, action), state === "succeeded" ? 0 : 1), action + ": " + state);
                root.check(root.parse(root.fixture(state, action), 0, true), action + ": replay " + state);
            }
        }
        const good = root.fixture("succeeded");
        const pending = root.operation("pending");
        const running = root.operation("running");
        const failed = root.fixture("failed");
        const invalid = [
            good.slice(root.header.length), good.replace("\t1\t0", "\t2\t0"),
            good.replace("\t1\t0", "\t1\t1"), root.header + good,
            good.replace(pending, running), good.replace(running, ""),
            good.replace(running, root.operation("permission-denied")),
            good.replace("\tsucceeded\tunknown\tno", "\tsucceeded\tunknown\tyes"),
            good.replace("\tunknown\tno", "\t101\tno"),
            good.replace("\tunknown\tno", "\t01\tno"),
            good.replace("\tunknown\tno", "\tunknown\ttrue"),
            good.replace("\tpending\t", "\tinvented\t"),
            good.replace(pending, pending.replace("updates-refresh", "updates-install-all")),
            good.replace(pending, pending.replace(root.operationId, "op-22222222222222222222222222222222")),
            good.replace(pending, pending.replace(root.operationId, "op-ABC")),
            good.replace(pending, pending.replace("updates-refresh", "updates-cancel")),
            good.replace(pending, pending.replace("\trefresh\t", "\tdelegate\t")),
            good.replace("Fixture", "x".repeat(513)),
            good.replace("Fixture", "\u20ac".repeat(171)),
            good.replace("Fixture", "\u0000"), good.replace("Fixture", "\r"),
            good.replace("complete\toperation\n", ""), good.slice(0, -1),
            good + "complete\toperation\n", good + "future\tx\n", good + "\n",
            good.replace("complete\toperation", "complete\tsnapshot"),
            good.replace(root.audit("succeeded"), ""),
            good.replace(root.audit("succeeded"), root.audit("succeeded") + root.audit("succeeded")),
            good.replace(root.audit("succeeded"), root.audit("failed")),
            good.replace("2026-09-04T12:00:00Z", "2026-02-30T12:00:00Z"),
            good.replace("2026-09-04T12:00:00Z", "2026-09-04T12:00:60Z"),
            good.replace("2026-09-04T12:00:00Z", "0000-09-04T12:00:00Z"),
            good.replace("2026-09-04T12:00:00Z", "2026-09-04T12:00:00+00:00"),
            good.replace(running, root.audit("succeeded") + running),
            good.replace("complete\toperation", running + "complete\toperation"),
            failed.replace("error\tupdates\tconflict\tFixture failure\n", ""),
            failed.replace("error\tupdates", "error\trecovery"),
            failed.replace("error\tupdates", "error\tregional"),
            failed.replace("\tconflict\t", "\tDBus.Error\t"),
            failed.replace("error\tupdates\tconflict\tFixture failure\n", "error\tupdates\tconflict\tX\nerror\tupdates\tconflict\tY\n")
        ];
        for (const type of ["snapshot-generation", "provider", "state", "update", "package-change",
                "repository", "account", "filesystem", "action", "active-operation", "terminal-handoff"])
            invalid.push(good.replace(running, type + "\tx\n" + running));
        for (const text of invalid) root.check(!root.parse(text, text.indexOf("\tfailed\t") >= 0 ? 1 : 0), "Accepted malformed fixture: " + text);
        for (const type of ["operation", "error", "audit", "complete"])
            root.check(!root.parse(good.replace(running, type + "\n" + running), 0), "Missing fields: " + type);
        root.check(root.parse(good.replace(running, "future\tx\n" + running), 0), "Unknown record");
        root.check(root.parse(good.trim().split("\n").map(line => line + "\t" + "x".repeat(513)).join("\n") + "\n", 0), "Trailing extension fields");
        root.check(root.parse(good.replace("Fixture", "\u20ac".repeat(170) + "ab"), 0), "512-byte field");
        root.check(!root.parse(good, 1), "Success with failed exit");
        root.check(!root.parse(failed, 0), "Failed origin with successful exit");
        root.check(!root.parse(failed, 1, true), "Failed replay with failed exit");
        const progress = good.replace(running, pending + root.operation("authorizing")
            + root.operation("authorizing") + running + running + root.operation("cancel-requested")
            + root.operation("cancel-requested"));
        root.check(root.parse(progress, 0), "Same-state progress and completion/cancel race");
        root.check(root.parse(good.replace(running, running.repeat(255)), 0), "256 nonterminal records");
        root.check(!root.parse(good.replace(running, running.repeat(256)), 0), "257 nonterminal records");

        const unicode = root.bytes(good.replace("Fixture", "split \u00a2\u20ac\ud83d\ude00"));
        const parser = Protocol.create(root.operationId, "updates-refresh");
        for (let i = 0; i <= unicode.byteLength; i++)
            root.check(Protocol.consume(parser, unicode.slice(0, i)), "Byte boundary " + i);
        root.check(Protocol.finish(parser, 0, true, false), "Split Unicode completion");
        root.check(parser.records[0].detail === "split \u00a2\u20ac\ud83d\ude00", "Unicode preserved");
        root.check(!Protocol.consume(parser, unicode), "Data after EOF");
        for (const malformed of [[0xc0, 0xaf], [0xe0, 0x80, 0xaf], [0xed, 0xa0, 0x80],
                [0xf4, 0x90, 0x80, 0x80], [0x80], [0xc2, 0x20]])
            root.check(!Protocol.consume(Protocol.create(), new Uint8Array(malformed).buffer), "Malformed UTF-8");
        const truncated = Protocol.create();
        root.check(Protocol.consume(truncated, new Uint8Array([0xe2]).buffer), "Pending UTF-8");
        root.check(!Protocol.finish(truncated, 0, true, false), "Truncated UTF-8");
        root.check(!Protocol.consume(Protocol.create(), new ArrayBuffer(8 * 1024 * 1024 + 1)), "Byte limit");
        const extension = "future\t" + "x".repeat(8 * 1024 * 1024 - root.bytes(good).byteLength - 8) + "\n";
        root.check(root.parse(good.replace(running, extension + running), 0), "Exact byte limit with ignored extension");
        const replaced = Protocol.create();
        Protocol.consume(replaced, root.bytes(root.header));
        root.check(!Protocol.consume(replaced, new ArrayBuffer(0)), "Shrinking collector");
        root.check(!Protocol.consume(Protocol.create("bad"), root.bytes(good)), "Invalid expected ID");
        root.check(!Protocol.consume(Protocol.create("", "health-open"), root.bytes(good)), "Invalid expected action");
        root.check(!Protocol.consume(Protocol.create("", "updates-install-all"), root.bytes(good)), "Mismatched expected action");
        const crashed = Protocol.create();
        Protocol.consume(crashed, root.bytes(good));
        root.check(!Protocol.finish(crashed, 0, false, false), "Crash is not success");
    }

    Component.onCompleted: {
        try {
            root.unitTests();
            root.streamParser = Protocol.create(root.operationId, "updates-refresh");
            // Deliberately split a multibyte field across separate native pipe
            // reads, and leave pending visible before a valid failed exit.
            const payload = root.fixture("failed").replace("Fixture", "split \u20ac\ud83d\ude00");
            process.command = ["/usr/bin/python3", "-c", "import os,time; data=" + JSON.stringify(payload)
                + ".encode('utf-8'); cut=data.index(bytes([226])); "
                + "os.write(1,data[:cut+1]); time.sleep(.15); os.write(1,data[cut+1:cut+2]); "
                + "time.sleep(.15); end=data.index(b'\\n',cut)+1; os.write(1,data[cut+2:end]); "
                + "time.sleep(.15); os.write(1,data[end:]); raise SystemExit(1)"];
            process.running = true;
        } catch (error) {
            console.error("Operation parser fixture failed: " + error);
            Qt.quit();
        }
    }

    Process {
        id: process
        stdout: StdioCollector {
            id: output
            waitForEnd: false
            onDataChanged: {
                if (!root.streamParser) return;
                Protocol.consume(root.streamParser, output.data);
                if (root.streamParser.operation && root.streamParser.operation.state === "pending" && process.running)
                    root.sawLivePending = true;
            }
        }
        onExited: (exitCode, exitStatus) => {
            try {
                root.check(Protocol.consume(root.streamParser, output.data), root.streamParser.failure);
                // Quickshell 0.2.1 passes QProcess::ExitStatus but does not
                // export that enum on Process; Qt defines NormalExit as zero.
                root.check(Protocol.finish(root.streamParser, exitCode, exitStatus === 0, false), root.streamParser.failure);
                root.check(root.sawLivePending, "Progress was not delivered live");
                root.check(root.streamParser.records[0].detail === "split \u20ac\ud83d\ude00", "Native UTF-8 was corrupted");
                console.info("Operation parser native tests: PASS (" + root.assertions + " assertions)");
            } catch (error) {
                console.error("Operation parser native fixture failed: " + error);
            }
            Qt.quit();
        }
    }
    Timer {
        interval: 15000
        running: true
        onTriggered: { console.error("Operation parser fixture timed out"); Qt.quit(); }
    }
}
