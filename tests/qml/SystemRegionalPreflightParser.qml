import QtQuick
import Quickshell
import "SystemRegionalPreflightProtocol.js" as Protocol

ShellRoot {
    id: root
    property int assertions: 0
    property string generation: "a".repeat(64)

    function check(condition, message) {
        root.assertions++;
        if (!condition) throw new Error(message);
    }
    function bytes(text) {
        const encoded = unescape(encodeURIComponent(text));
        const result = new Uint8Array(encoded.length);
        for (let i = 0; i < encoded.length; i++) result[i] = encoded.charCodeAt(i);
        return result.buffer;
    }
    function choices(kind, values) {
        return "regional-choices-protocol\t1\t0\t" + kind + "\n"
            + values.map(value => "choice\t" + value + "\n").join("") + "complete\tregional-choices\n";
    }
    function preview(action, argument, current, detail) {
        return "regional-preview-protocol\t1\t0\n" + ["preview", action, argument, root.generation,
            current, action === "locale-set" ? argument.slice(5) : argument, detail].join("\t")
            + "\ncomplete\tregional-preview\n";
    }
    function parse(command, selection, argument, text, code, normal) {
        const parser = Protocol.create(command, selection, argument);
        return Protocol.consume(parser, root.bytes(text)) && Protocol.finish(parser, code, normal !== false);
    }
    function exactChoices(kind, values) {
        const parser = Protocol.create("regional-choices", kind, "");
        root.check(Protocol.consume(parser, root.bytes(root.choices(kind, values)))
            && Protocol.finish(parser, 0, true), kind + " catalog completion");
        root.check(JSON.stringify(parser.choices) === JSON.stringify(values), kind + " exact catalog identities and order");
    }
    function unitTests() {
        for (const command of ["time-status", "ntp-sample"]) {
            const time = command === "time-status";
            const header = command + "-protocol\t1\t0\n";
            const complete = "complete\t" + command + "\n";
            const row = time ? "time\tEtc/UTC\tyes\tno\tyes\n" : "sample\tyes\tno\n";
            const good = header + row + complete;
            const all = root.bytes(good);
            for (let split = 0; split <= all.byteLength; split++) {
                const parser = Protocol.create(command, "", "");
                root.check(Protocol.consume(parser, all.slice(0, split)) && Protocol.consume(parser, all)
                    && Protocol.finish(parser, 0, true), "every observation split: " + command + " " + split);
                root.check(JSON.stringify(parser.observation) === JSON.stringify(time
                    ? { timezone: "Etc/UTC", canNtp: true, ntpEnabled: false, synchronized: true }
                    : { canNtp: true, synchronized: false }), "exact observation");
            }
            for (let bits = 0; bits < (time ? 8 : 4); bits++) {
                const values = Array.from({length: time ? 3 : 2}, (_, i) => bits & (1 << i) ? "yes" : "no");
                root.check(root.parse(command, "", "", header + (time ? "time\tEtc/UTC\t" : "sample\t")
                    + values.join("\t") + "\n" + complete, 0), "every boolean combination");
            }
            const error = "error\t" + command + "\tinternal\tNot available\n";
            for (const bad of [good.slice(0, -1), good + "\n", good + complete,
                    good.replace("\t1\t0", "\t1\t1"), good.replace("\t1\t0", "\t2\t0"),
                    header + complete, header + row + row + complete,
                    header + row + error + complete, header + error + row + complete,
                    good.replace("yes", "true"), good.replace("no", "0"),
                    good.replace(row, row.slice(0, -1) + "\textra\n"),
                    good.replace(row, "choice\tEtc/UTC\n"),
                    good.replace(row, "preview\tntp-set\tenabled\t" + root.generation + "\tdisabled\tenabled\tdetail\n"),
                    good.replace(row, time ? "sample\tyes\tno\n" : "time\tEtc/UTC\tyes\tno\tyes\n"),
                    good.replace(complete, "complete\tregional-preview\n")])
                root.check(!root.parse(command, "", "", bad, 0), "invalid observation");
            for (const code of [1, 2, -1])
                root.check(!root.parse(command, "", "", good, code), "observation exit mismatch");
            root.check(!root.parse(command, "", "", good, 0, false), "crashed observation");
            for (const code of ["missing-provider", "permission-denied", "unsupported", "timeout", "malformed", "internal"]) {
                const failed = header + error.replace("internal", code) + complete;
                root.check(root.parse(command, "", "", failed, 1), "typed observation error");
                root.check(!root.parse(command, "", "", failed, 0), "observation error cannot succeed");
            }
            for (const code of ["network", "interrupted", "canceled", "unknown"])
                root.check(!root.parse(command, "", "", header + error.replace("internal", code) + complete, 1), "closed observation error codes");
            root.check(!root.parse(command, "", "", header + error.replace(command, "regional") + complete, 1), "observation error owner");
            root.check(!root.parse(command, "", "", header + error + error + complete, 1), "duplicate observation error");
            for (const value of ["x".repeat(513), "\u20ac".repeat(171), "bad\u202e"])
                root.check(!root.parse(command, "", "", header + error.replace("Not available", value) + complete, 1), "bounded canonical observation detail");
            root.check(root.parse(command, "", "", header + error.replace("Not available", "\u20ac".repeat(170) + "ab") + complete, 1), "512-byte observation detail");
            for (const request of [[command, "timezone", ""], [command, "", "extra"], [command, null, ""], [command, "", null]])
                root.check(!!Protocol.create(...request).failure, "no observation arguments");
            const bounded = Protocol.create(command, "", "");
            root.check(bounded.limit === 1024 && !Protocol.consume(bounded, new ArrayBuffer(1025)), "observation stream limit");
            if (time) {
                for (const value of ["", "../UTC", "Etc//UTC", "x".repeat(256), "\u00e9"])
                    root.check(!root.parse(command, "", "", good.replace("Etc/UTC", value), 0), "invalid observed timezone");
            }
        }
        for (const kind of ["timezone", "locale"]) {
            const values = kind === "timezone" ? ["America/Chicago", "Etc/UTC"] : ["C", "en_US.utf8"];
            const good = root.choices(kind, values);
            root.exactChoices(kind, values);
            root.exactChoices(kind, []);
            const bad = [good.slice(0, -1), good + "\n", good + "complete\tregional-choices\n",
                good.replace("\t1\t0", "\t1\t1"), good.replace("\t1\t0", "\t2\t0"),
                good.replace("choice\t", "unknown\t"), good.replace("choice\t", "choice\textra\t"),
                good.replace("complete\tregional-choices", "complete\tregional-preview"),
                root.choices(kind, [values[0], values[0]]), root.choices(kind, values.slice().reverse()),
                root.choices(kind, [""]), root.choices(kind, ["bad\rvalue"]), root.choices(kind, ["bad\u0000value"]),
                root.choices(kind, ["\u00e9"]), good.replace("choice\t", "error\tregional\tinternal\tbad\nchoice\t")];
            for (const text of bad) root.check(!root.parse("regional-choices", kind, "", text, 0), "invalid catalog");
            root.check(!root.parse("regional-choices", kind, "", good, 1), "wrong catalog exit");
            root.check(!root.parse("regional-choices", kind, "", good, 0, false), "crashed catalog");
            const count = kind === "timezone" ? 2048 : 4096;
            const maximum = Array.from({length: count}, (_, i) => "Z" + String(i).padStart(4, "0"));
            root.check(root.parse("regional-choices", kind, "", root.choices(kind, maximum), 0), "maximum count");
            maximum.push("Z9999");
            root.check(!root.parse("regional-choices", kind, "", root.choices(kind, maximum), 0), "count overflow");
            const length = kind === "timezone" ? 255 : 128;
            root.check(root.parse("regional-choices", kind, "", root.choices(kind, ["x".repeat(length)]), 0), "maximum identity");
            root.check(!root.parse("regional-choices", kind, "", root.choices(kind, ["x".repeat(length + 1)]), 0), "identity overflow");
        }
        for (const value of ["/Etc/UTC", "Etc//UTC", "Etc/../UTC", "Etc/./UTC", "Etc/UTC/"])
            root.check(!root.parse("regional-choices", "timezone", "", root.choices("timezone", [value]), 0), "unsafe timezone");
        root.check(!root.parse("regional-choices", "locale", "", root.choices("locale", ["en US"]), 0), "locale whitespace");
        const maximumBytes = Array.from({length: 2048}, (_, i) => String(i).padStart(4, "0") + "x".repeat(124));
        root.check(root.parse("regional-choices", "timezone", "", root.choices("timezone", maximumBytes), 0), "timezone payload at limit");
        maximumBytes[2047] += "x";
        root.check(!root.parse("regional-choices", "timezone", "", root.choices("timezone", maximumBytes), 0), "timezone payload overflow");

        for (const request of [["timezone-set", "Etc/UTC", "America/Chicago"],
                ["ntp-set", "enabled", "disabled"], ["locale-set", "LANG=en_US.utf8", "C"]]) {
            const action = request[0], argument = request[1];
            const good = root.preview(action, argument, request[2], "LC_TIME=\u20ac\ud83d\ude00, LANGUAGE=en:de");
            const all = root.bytes(good);
            for (let split = 0; split <= all.byteLength; split++) {
                const parser = Protocol.create("regional-preview", action, argument);
                root.check(Protocol.consume(parser, all.slice(0, split)) && Protocol.consume(parser, all)
                    && Protocol.finish(parser, 0, true), "every UTF-8 split: " + split + " " + parser.failure);
                root.check(parser.preview.detail === "LC_TIME=\u20ac\ud83d\ude00, LANGUAGE=en:de", "full detail retained");
            }
            for (const text of [good.replace(root.generation, "A".repeat(64)), good.replace(root.generation, "a".repeat(63)),
                    good.replace("preview\t" + action, "preview\tntp-unknown"), good.replace("\t" + argument + "\t", "\twrong\t"),
                    good.replace("\t" + (action === "locale-set" ? argument.slice(5) : argument) + "\tLC_TIME", "\twrong\tLC_TIME"),
                    good.replace("\ncomplete", "\textra\ncomplete"), good.slice(0, -1), good + good,
                    good.replace("preview\t", "error\tregional\tinternal\tfailure\npreview\t")])
                root.check(!root.parse("regional-preview", action, argument, text, 0), "invalid preview");
            for (const code of [1, 2, -1]) root.check(!root.parse("regional-preview", action, argument, good, code), "preview exit mismatch");
            for (const detail of ["x".repeat(513), "\u20ac".repeat(171), "\u007f", "\u0085", "\u202e", "\u2028", "\u00a0"])
                root.check(!root.parse("regional-preview", action, argument, root.preview(action, argument, request[2], detail), 0), "unsafe detail: " + detail.codePointAt(0) + "/" + detail.length);
            root.check(root.parse("regional-preview", action, argument, root.preview(action, argument, request[2], "\u20ac".repeat(170) + "ab"), 0), "512 UTF-8 bytes");
        }
        const header = "regional-preview-protocol\t1\t0\n";
        for (const code of ["network", "repository", "conflict", "signature", "package", "unsupported", "malformed",
                "missing-provider", "permission-denied", "canceled", "timeout", "interrupted", "internal"]) {
            const error = header + "error\tregional\t" + code + "\tNot available\ncomplete\tregional-preview\n";
            root.check(root.parse("regional-preview", "ntp-set", "invalid selection", error, 1), "typed recognized-request error");
            root.check(!root.parse("regional-preview", "ntp-set", "enabled", error, 0), "error cannot succeed");
            root.check(!root.parse("regional-preview", "ntp-set", "enabled", error.replace("\tregional\t", "\tupdates\t"), 1), "wrong error owner");
        }
        for (const invalid of [[0xc0, 0x80], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80], [0xe2, 0x28, 0xa1], [0x80]]) {
            const parser = Protocol.create("regional-preview", "ntp-set", "enabled");
            root.check(!Protocol.consume(parser, new Uint8Array(invalid).buffer), "invalid UTF-8");
        }
        const truncated = Protocol.create("regional-preview", "ntp-set", "enabled");
        root.check(Protocol.consume(truncated, new Uint8Array([0xe2]).buffer) && !Protocol.finish(truncated, 0, true), "truncated UTF-8");
        const parser = Protocol.create("regional-preview", "ntp-set", "enabled");
        root.check(Protocol.consume(parser, root.bytes(header)), "partial header");
        root.check(!Protocol.consume(parser, root.bytes(header.replace("1", "2"))), "replaced same-length prefix");
        const shrink = Protocol.create("regional-preview", "ntp-set", "enabled");
        root.check(Protocol.consume(shrink, root.bytes(header)) && !Protocol.consume(shrink, root.bytes("short")), "shrunk collector");
        for (const request of [["unknown", "timezone", ""], ["regional-choices", "unknown", ""],
                ["regional-choices", "locale", "extra"], ["regional-preview", "unknown", ""], ["regional-preview", "ntp-set", null]])
            root.check(!!Protocol.create(...request).failure, "invalid request");
        for (const request of [["regional-choices", "timezone", ""], ["regional-choices", "locale", ""], ["regional-preview", "ntp-set", "enabled"]]) {
            const bounded = Protocol.create(...request);
            root.check(!Protocol.consume(bounded, new ArrayBuffer(bounded.limit + 1)), "whole stream overflow");
        }
        const ended = Protocol.create("regional-choices", "locale", "");
        root.check(Protocol.consume(ended, root.bytes(root.choices("locale", []))) && Protocol.finish(ended, 0, true), "finish once");
        root.check(!Protocol.finish(ended, 0, true), "duplicate finish");
    }
    Component.onCompleted: Qt.callLater(function() {
        try {
            root.unitTests();
            console.info("Regional preflight parser tests: PASS (" + root.assertions + " assertions)");
        } catch (error) { console.error("Regional preflight parser FAILED: " + error); }
        Qt.quit();
    })
}
