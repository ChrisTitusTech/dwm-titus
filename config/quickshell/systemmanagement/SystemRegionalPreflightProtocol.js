.pragma library

// One bounded, read-only result. Feed cumulative StdioCollector.data bytes.
// Consumers must wait for finish(); parsed rows alone are not usable evidence.
function create(command, selection, argument) {
    const choices = command === "regional-choices";
    const observation = command === "time-status" || command === "ntp-sample";
    const parser = { command: command, selection: selection, argument: argument,
        limit: observation ? 1024 : choices ? (selection === "timezone" ? 524288 : 1048576) : 8192,
        offset: 0, previous: new Uint8Array(0), line: "", lineBytes: 0,
        remaining: 0, minimum: 0, codepoint: 0, header: false, complete: false,
        ended: false, failure: "", choices: [], identityBytes: 0, preview: null, observation: null, error: null };
    if (observation ? (selection !== "" || argument !== "")
        : choices ? (["timezone", "locale"].indexOf(selection) < 0 || argument !== "")
            : (command !== "regional-preview"
                || ["timezone-set", "ntp-set", "locale-set"].indexOf(selection) < 0
                || typeof argument !== "string" || argument.length > 512))
        fail(parser, "Invalid preflight request");
    return parser;
}

function fail(parser, detail) {
    if (!parser.failure) parser.failure = detail;
    return false;
}

function timezone(value) {
    return value.length > 0 && value.length <= 255 && !/[^\x20-\x7e]/.test(value)
        && !value.split("/").some(part => part === "" || part === "." || part === "..");
}

function locale(value) {
    return value.length > 0 && value.length <= 128 && !/[^\x21-\x7e]/.test(value);
}

function utf8Bytes(value) {
    let size = 0;
    for (const char of value) {
        const code = char.codePointAt(0);
        size += code < 128 ? 1 : code < 2048 ? 2 : code < 65536 ? 3 : 4;
    }
    return size;
}

function validPreview(parser, fields) {
    if (fields.length !== 7 || fields[1] !== parser.selection || fields[2] !== parser.argument
            || fields[3].length !== 64 || !/^[0-9a-f]+$/.test(fields[3])) return false;
    if (fields[1] === "timezone-set")
        return timezone(fields[2]) && timezone(fields[4]) && fields[5] === fields[2];
    if (fields[1] === "ntp-set")
        return ["enabled", "disabled"].indexOf(fields[2]) >= 0
            && ["enabled", "disabled"].indexOf(fields[4]) >= 0 && fields[5] === fields[2];
    // Readable LANG can be absent, empty, or broader than localed's mutation grammar.
    return fields[2].slice(0, 5) === "LANG=" && locale(fields[2].slice(5))
        && fields[5] === fields[2].slice(5);
}

function acceptLine(parser, line) {
    if (parser.complete) return fail(parser, "Records after preflight completion");
    const fields = line.split("\t");
    if (fields.some(field => utf8Bytes(field) > 512)) return fail(parser, "Oversized preflight field");
    const choices = parser.command === "regional-choices";
    const observation = parser.command === "time-status" || parser.command === "ntp-sample";
    if (!parser.header) {
        const expected = parser.command + "-protocol\t1\t0" + (choices ? "\t" + parser.selection : "");
        if (line !== expected) return fail(parser, "Unsupported preflight header");
        parser.header = true;
    } else if (fields[0] === "choice" && choices) {
        const count = parser.selection === "timezone" ? 2048 : 4096;
        const valid = parser.selection === "timezone" ? timezone(fields[1] || "") : locale(fields[1] || "");
        if (fields.length !== 2 || !valid || parser.error || parser.choices.length >= count
                || (parser.choices.length && fields[1] <= parser.choices[parser.choices.length - 1]))
            return fail(parser, "Invalid, duplicate, or unordered preflight choice");
        parser.identityBytes += fields[1].length;
        if (parser.selection === "timezone" && parser.identityBytes > 262144)
            return fail(parser, "Timezone identities exceed byte limit");
        parser.choices.push(fields[1]);
    } else if (observation && fields[0] === (parser.command === "time-status" ? "time" : "sample")) {
        const time = parser.command === "time-status";
        if (parser.observation || parser.error || fields.length !== (time ? 5 : 3)
                || (time && !timezone(fields[1]))
                || fields.slice(time ? 2 : 1).some(value => ["yes", "no"].indexOf(value) < 0))
            return fail(parser, "Invalid time observation");
        parser.observation = time
            ? { timezone: fields[1], canNtp: fields[2] === "yes", ntpEnabled: fields[3] === "yes", synchronized: fields[4] === "yes" }
            : { canNtp: fields[1] === "yes", synchronized: fields[2] === "yes" };
    } else if (fields[0] === "preview" && parser.command === "regional-preview") {
        if (parser.preview || parser.error || !validPreview(parser, fields))
            return fail(parser, "Invalid or mismatched preflight preview");
        parser.preview = { actionId: fields[1], argument: fields[2], generation: fields[3],
            current: fields[4], target: fields[5], detail: fields[6] };
    } else if (fields[0] === "error") {
        const codes = observation ? ["missing-provider", "permission-denied", "timeout", "malformed", "interrupted", "internal"]
            : ["network", "repository", "conflict", "signature", "package",
                    "unsupported", "malformed", "missing-provider", "permission-denied", "canceled",
                    "timeout", "interrupted", "internal"];
        if (fields.length !== 4 || fields[1] !== (observation ? parser.command : "regional")
                || parser.error || parser.preview || parser.observation || parser.choices.length || codes.indexOf(fields[2]) < 0)
            return fail(parser, "Invalid preflight error");
        parser.error = { code: fields[2], detail: fields[3] };
    } else if (fields[0] === "complete") {
        if (fields.length !== 2 || fields[1] !== parser.command
                || (!choices && !parser.preview && !parser.observation && !parser.error))
            return fail(parser, "Incomplete preflight result");
        parser.complete = true;
    } else return fail(parser, "Unexpected preflight record");
    return true;
}

function consume(parser, buffer) {
    if (parser.failure) return false;
    if (parser.ended || !(buffer instanceof ArrayBuffer) || buffer.byteLength < parser.offset)
        return fail(parser, "Preflight stream replaced or already ended");
    if (buffer.byteLength > parser.limit) return fail(parser, "Preflight stream exceeds byte limit");
    const bytes = new Uint8Array(buffer);
    for (let i = 0; i < parser.previous.length; i++)
        if (bytes[i] !== parser.previous[i]) return fail(parser, "Preflight prefix changed");
    while (parser.offset < bytes.length) {
        const byte = bytes[parser.offset++];
        if (++parser.lineBytes > 8192) return fail(parser, "Preflight line exceeds byte limit");
        if (parser.remaining) {
            if ((byte & 0xc0) !== 0x80) return fail(parser, "Invalid preflight UTF-8");
            parser.codepoint = (parser.codepoint << 6) | (byte & 0x3f);
            if (--parser.remaining) continue;
            if (parser.codepoint < parser.minimum || parser.codepoint > 0x10ffff
                    || (parser.codepoint >= 0xd800 && parser.codepoint <= 0xdfff))
                return fail(parser, "Invalid preflight UTF-8");
            const char = String.fromCodePoint(parser.codepoint);
            // QML's ES7 engine does not implement Unicode property escapes.
            // Reject Unicode 16 control/formatting and separator characters explicitly;
            // the producer additionally validates Unicode printability.
            if (/[\u0080-\u00a0\u00ad\u0600-\u0605\u061c\u06dd\u070f\u0890-\u0891\u08e2\u1680\u180e\u2000-\u200f\u2028-\u202f\u205f-\u206f\u3000\ufeff\ufff9-\ufffb]/.test(char)
                    || parser.codepoint === 0x110bd || parser.codepoint === 0x110cd
                    || (parser.codepoint >= 0x13430 && parser.codepoint <= 0x1343f)
                    || (parser.codepoint >= 0x1bca0 && parser.codepoint <= 0x1bca3)
                    || (parser.codepoint >= 0x1d173 && parser.codepoint <= 0x1d17a)
                    || (parser.codepoint >= 0xe0000 && parser.codepoint <= 0xe007f))
                return fail(parser, "Noncanonical preflight text");
            parser.line += char;
        } else if (byte === 10) {
            if (!acceptLine(parser, parser.line)) return false;
            parser.line = "";
            parser.lineBytes = 0;
        } else if (byte < 0x80) {
            if ((byte < 32 && byte !== 9) || byte === 127) return fail(parser, "Noncanonical preflight text");
            parser.line += String.fromCharCode(byte);
        } else {
            if (byte >= 0xc2 && byte <= 0xdf) { parser.remaining = 1; parser.minimum = 0x80; parser.codepoint = byte & 0x1f; }
            else if (byte >= 0xe0 && byte <= 0xef) { parser.remaining = 2; parser.minimum = 0x800; parser.codepoint = byte & 0x0f; }
            else if (byte >= 0xf0 && byte <= 0xf4) { parser.remaining = 3; parser.minimum = 0x10000; parser.codepoint = byte & 7; }
            else return fail(parser, "Invalid preflight UTF-8");
        }
    }
    parser.previous = bytes.slice();
    return true;
}

function finish(parser, exitCode, normalExit) {
    if (parser.failure) return false;
    if (parser.ended) return fail(parser, "Preflight stream already ended");
    parser.ended = true;
    parser.previous = new Uint8Array(0);
    if (parser.remaining || parser.line.length || !parser.complete)
        return fail(parser, "Truncated preflight stream");
    if (normalExit !== true || exitCode !== (parser.error ? 1 : 0))
        return fail(parser, "Preflight exit does not match its result");
    return true;
}
