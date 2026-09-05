.pragma library

// A parser owns one stream. It never runs a command or acknowledges a journal.
// Feed cumulative StdioCollector.data (ArrayBuffer), not arbitrary QString
// chunks: a pipe read can split a UTF-8 character or a protocol record.
function create(expectedId, expectedAction) {
    const parser = {
        expectedId: expectedId || "", expectedAction: expectedAction || "",
        offset: 0, line: "", remaining: 0, codepoint: 0, minimum: 0,
        header: false, complete: false, ended: false, failure: "",
        operation: null, audit: null, error: null, records: []
    };
    if ((parser.expectedId && !/^op-[0-9a-f]{32}$/.test(parser.expectedId))
            || (parser.expectedAction && !actionKind(parser.expectedAction)))
        fail(parser, "Invalid expected operation identity");
    return parser;
}

function fail(parser, detail) {
    if (!parser.failure) parser.failure = detail;
    return false;
}

function actionKind(action) {
    if (action === "updates-refresh") return "refresh";
    if (action === "updates-install-all") return "update";
    if (action === "timezone-set") return "timezone";
    if (action === "ntp-set") return "ntp";
    if (action === "locale-set") return "locale";
    if (["accounts-open", "password-open", "printers-open", "sources-open"].indexOf(action) >= 0)
        return "delegate";
    return "";
}

function owner(action) {
    const kind = actionKind(action);
    if (kind === "refresh" || kind === "update") return "updates";
    if (kind === "timezone" || kind === "ntp" || kind === "locale") return "regional";
    if (action === "accounts-open" || action === "password-open") return "accounts";
    if (action === "printers-open") return "printers";
    if (action === "sources-open") return "sources";
    return "";
}

function terminal(state) {
    return ["permission-denied", "canceled", "failed", "interrupted", "succeeded"].indexOf(state) >= 0;
}

function transition(previous, next) {
    if (terminal(previous)) return false;
    // Same-state records update progress without inventing a new transition.
    if (previous === next) return true;
    if (previous === "pending") return ["authorizing", "running", "canceled", "failed", "interrupted"].indexOf(next) >= 0;
    if (previous === "authorizing") return ["running", "permission-denied", "canceled", "failed", "interrupted"].indexOf(next) >= 0;
    if (previous === "running") return ["cancel-requested", "succeeded", "failed", "interrupted"].indexOf(next) >= 0;
    if (previous === "cancel-requested") return ["canceled", "succeeded", "failed", "interrupted"].indexOf(next) >= 0;
    return false;
}

function utf8Bytes(text) {
    let count = 0;
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code < 0x80) count++;
        else if (code < 0x800) count += 2;
        else if (code >= 0xd800 && code <= 0xdbff) { count += 4; i++; }
        else count += 3;
    }
    return count;
}

function fieldsFit(fields, count) {
    if (fields.length < count) return false;
    for (let i = 1; i < count; i++)
        if (utf8Bytes(fields[i]) > 512) return false;
    return true;
}

function timestamp(value) {
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/.test(value)
            || value.slice(0, 4) === "0000") return false;
    const date = new Date(value);
    return !isNaN(date.getTime()) && date.toISOString() === value.slice(0, -1) + ".000Z";
}

function acceptLine(parser, line) {
    if (parser.complete) return fail(parser, "Records after operation completion");
    const fields = line.split("\t");
    const type = fields[0];
    if (!type) return fail(parser, "Empty operation record type");
    if (!parser.header) {
        if (type !== "system-management-protocol" || !fieldsFit(fields, 3)
                || fields[1] !== "1" || fields[2] !== "0")
            return fail(parser, "Unsupported or missing operation protocol header");
        parser.header = true;
        return true;
    }
    if (type === "system-management-protocol") return fail(parser, "Duplicate protocol header");
    if (type === "operation") {
        if (!fieldsFit(fields, 8) || !/^op-[0-9a-f]{32}$/.test(fields[1])
                || !actionKind(fields[2]) || actionKind(fields[2]) !== fields[3]
                || !/^(unknown|0|[1-9][0-9]?|100)$/.test(fields[5])
                || (fields[6] !== "yes" && fields[6] !== "no"))
            return fail(parser, "Invalid operation fields");
        const previous = parser.operation;
        if ((parser.expectedId && fields[1] !== parser.expectedId)
                || (parser.expectedAction && fields[2] !== parser.expectedAction)
                || (previous && (fields[1] !== previous.id || fields[2] !== previous.actionId)))
            return fail(parser, "Operation identity changed or does not match");
        if ((!previous && fields[4] !== "pending")
                || (previous && !transition(previous.state, fields[4]))
                || (terminal(fields[4]) && fields[6] !== "no"))
            return fail(parser, "Invalid operation transition or terminal cancelability");
        if (fields[4] === "failed" && !parser.error)
            return fail(parser, "Failed operation has no preceding error");
        if (!terminal(fields[4]) && parser.records.length >= 256)
            return fail(parser, "Too many operation progress records");
        parser.operation = { id: fields[1], actionId: fields[2], kind: fields[3],
            state: fields[4], percent: fields[5], cancelable: fields[6] === "yes", detail: fields[7] };
        parser.records.push(parser.operation);
    } else if (type === "error") {
        if (!fieldsFit(fields, 4) || parser.error || !parser.operation
                || terminal(parser.operation.state) || fields[1] !== owner(parser.operation.actionId)
                || ["network", "repository", "conflict", "signature", "package", "unsupported",
                    "malformed", "missing-provider", "permission-denied", "canceled", "timeout",
                    "interrupted", "internal"].indexOf(fields[2]) < 0)
            return fail(parser, "Invalid operation error");
        parser.error = { provider: fields[1], code: fields[2], detail: fields[3] };
    } else if (type === "audit") {
        const operation = parser.operation;
        if (!fieldsFit(fields, 8) || parser.audit || !operation || !terminal(operation.state)
                || fields[1] !== operation.id || fields[2] !== operation.actionId
                || fields[3] !== operation.kind || fields[4] !== operation.state
                || !timestamp(fields[5]) || !timestamp(fields[6]))
            return fail(parser, "Invalid terminal audit");
        parser.audit = { id: fields[1], actionId: fields[2], kind: fields[3], result: fields[4],
            started: fields[5], finished: fields[6], detail: fields[7] };
    } else if (type === "complete") {
        if (!fieldsFit(fields, 2) || fields[1] !== "operation" || !parser.audit)
            return fail(parser, "Incomplete operation result");
        parser.complete = true;
    } else if (["snapshot-generation", "provider", "state", "update", "package-change",
                "repository", "account", "filesystem", "action", "active-operation",
                "terminal-handoff"].indexOf(type) >= 0) {
        return fail(parser, "Snapshot record in operation stream");
    }
    // Unknown records and trailing fields are append-only extension space.
    return true;
}

function consume(parser, buffer) {
    if (parser.failure) return false;
    if (parser.ended || !(buffer instanceof ArrayBuffer) || buffer.byteLength < parser.offset)
        return fail(parser, "Operation byte stream was replaced or already ended");
    if (buffer.byteLength > 8 * 1024 * 1024) return fail(parser, "Operation stream exceeds byte limit");
    const bytes = new Uint8Array(buffer);
    while (parser.offset < bytes.length) {
        const byte = bytes[parser.offset++];
        if (parser.remaining) {
            if ((byte & 0xc0) !== 0x80) return fail(parser, "Invalid operation UTF-8");
            parser.codepoint = (parser.codepoint << 6) | (byte & 0x3f);
            if (--parser.remaining) continue;
            if (parser.codepoint < parser.minimum || parser.codepoint > 0x10ffff
                    || (parser.codepoint >= 0xd800 && parser.codepoint <= 0xdfff))
                return fail(parser, "Invalid operation UTF-8");
            parser.line += String.fromCodePoint(parser.codepoint);
        } else if (byte === 10) {
            if (!acceptLine(parser, parser.line)) return false;
            parser.line = "";
        } else if (byte < 0x80) {
            if (byte === 0 || byte === 13) return fail(parser, "Noncanonical operation text");
            parser.line += String.fromCharCode(byte);
        } else {
            if (byte >= 0xc2 && byte <= 0xdf) { parser.remaining = 1; parser.minimum = 0x80; parser.codepoint = byte & 0x1f; }
            else if (byte >= 0xe0 && byte <= 0xef) { parser.remaining = 2; parser.minimum = 0x800; parser.codepoint = byte & 0x0f; }
            else if (byte >= 0xf0 && byte <= 0xf4) { parser.remaining = 3; parser.minimum = 0x10000; parser.codepoint = byte & 0x07; }
            else return fail(parser, "Invalid operation UTF-8");
        }
    }
    return true;
}

function finish(parser, exitCode, normalExit, replay) {
    if (parser.failure) return false;
    if (parser.ended) return fail(parser, "Operation stream already ended");
    parser.ended = true;
    if (parser.remaining || parser.line.length || !parser.complete)
        return fail(parser, "Truncated operation stream");
    const expectedExit = replay || parser.operation.state === "succeeded" ? 0 : 1;
    if (!normalExit || exitCode !== expectedExit)
        return fail(parser, "Operation process exit does not match its result");
    return true;
}
