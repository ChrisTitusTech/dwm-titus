.pragma library

const providerOrder = ["fedora", "dwm-titus", "flatpak", "mise"];
const providerStates = ["available", "partial", "restricted", "unavailable", "unsupported"];
const freshnessStates = ["fresh", "cached", "stale", "error"];
const errorCodes = ["", "malformed", "timeout", "missing-provider", "internal", "scan-failed", "busy",
    "network", "repository", "conflict", "signature", "package", "unsupported",
    "permission-denied", "canceled", "interrupted"];
const operationActions = ["update", "recover"];
const operationPhases = ["reserved", "launched", "running", "preparing", "fedora-executing",
    "desktop-starting", "flatpak-system", "flatpak-system-complete", "flatpak-user",
    "flatpak-user-complete", "mise-inventory", "mise-update", "mise-recheck", "recovering",
    "completed", "failed", "interrupted", "system-failed", "system-complete/user-failed", "closed"];
const operationOutcomes = ["pending", "succeeded", "failed", "unknown"];
const itemActions = ["install", "update", "remove", "reinstall", "downgrade", "obsolete"];

function deepFreeze(value) {
    if (value && typeof value === "object" && !Object.isFrozen(value)) {
        Object.keys(value).forEach(key => deepFreeze(value[key]));
        Object.freeze(value);
    }
    return value;
}

function integer(text, maximum) {
    if (typeof text !== "string" || !/^(0|[1-9][0-9]*)$/.test(text)) return null;
    const value = Number(text);
    return Number.isSafeInteger(value) && value <= maximum ? value : null;
}

function utf8Bytes(text) {
    return unescape(encodeURIComponent(text)).length;
}

function field(text) {
    if (typeof text !== "string" || text.indexOf("\0") >= 0) throw new Error("invalid field");
    let result = "";
    for (let index = 0; index < text.length; index++) {
        let character = text[index];
        if (character === "\\") {
            index++;
            if (index >= text.length || "\\tnr".indexOf(text[index]) < 0) throw new Error("invalid escape");
            character = ({ "\\": "\\", "t": "\t", "n": "\n", "r": "\r" })[text[index]];
        }
        result += character;
    }
    return result;
}

function records(payload, header, terminator) {
    if (typeof payload !== "string" || payload.length === 0 || utf8Bytes(payload) > 8 * 1024 * 1024
            || payload.indexOf("\0") >= 0 || !payload.endsWith("\n")) throw new Error("invalid payload");
    for (let index = 0; index < payload.length; index++) {
        const code = payload.charCodeAt(index);
        if ((code < 32 && code !== 9 && code !== 10) || (code >= 127 && code <= 159)) throw new Error("invalid control");
    }
    const lines = payload.slice(0, -1).split("\n");
    if (lines.length < 2 || lines.length > 16384 || lines[0] !== header || lines[lines.length - 1] !== terminator)
        throw new Error("invalid envelope");
    if (lines.some(line => utf8Bytes(line) > 8192)) throw new Error("record too large");
    return lines.slice(1, -1).map(line => line.split("\t").map(field));
}

function parseSnapshot(payload) {
    try {
        const lines = records(payload, "update-center-protocol\t1\t0", "complete\tsnapshot");
        const providers = [];
        const indexed = {};
        for (const values of lines) {
            if (values[0] === "provider") {
                if (values.length !== 11 || providerOrder.indexOf(values[1]) < 0 || indexed[values[1]]
                        || providerStates.indexOf(values[3]) < 0 || freshnessStates.indexOf(values[6]) < 0
                        || errorCodes.indexOf(values[9]) < 0 || (values[8] !== "yes" && values[8] !== "no")) throw new Error("invalid provider");
                const pending = integer(values[4], 4096);
                const managed = values[5] === "unknown" ? null : integer(values[5], 10000000);
                const lastSuccess = integer(values[7], Number.MAX_SAFE_INTEGER);
                if (pending === null || (managed === null && values[5] !== "unknown") || lastSuccess === null) throw new Error("invalid count");
                const provider = { id: values[1], name: values[2], status: values[3], pending: pending,
                    managed: managed, freshness: values[6], lastSuccess: lastSuccess,
                    updateAvailable: values[8] === "yes", canUpdate: true, canRecover: true,
                    icon: values[1], errorCode: values[9], detail: values[10], restart: "none",
                    items: [], itemIds: {} };
                indexed[provider.id] = provider;
                providers.push(provider);
            } else if (values[0] === "guidance") {
                if (values.length !== 4 || !indexed[values[1]] || values[2] !== "restart"
                        || ["session", "system"].indexOf(values[3]) < 0
                        || indexed[values[1]].restart !== "none") throw new Error("invalid guidance");
                indexed[values[1]].restart = values[3];
            } else if (values[0] === "item") {
                if (values.length !== 9 || !indexed[values[1]] || itemActions.indexOf(values[2]) < 0
                        || !values[3] || !values[6] || (values[8] && !/^https:\/\/[^\s]+$/.test(values[8]))) throw new Error("invalid item");
                const identity = values[7] + "\0" + values[6];
                if (indexed[values[1]].itemIds[identity]) throw new Error("duplicate item");
                indexed[values[1]].itemIds[identity] = true;
                indexed[values[1]].items.push({ providerId: values[1], action: values[2], name: values[3],
                    current: values[4], available: values[5], packageId: values[6], scope: values[7], url: values[8] });
                if (indexed[values[1]].items.length > 4096) throw new Error("too many items");
            } else throw new Error("unknown record");
        }
        if (providers.length === 0) throw new Error("empty snapshot");
        for (let index = 0; index < providers.length; index++) {
            const provider = providers[index];
            if (provider.pending !== provider.items.length
                    || (index > 0 && providerOrder.indexOf(providers[index - 1].id) >= providerOrder.indexOf(provider.id)))
                throw new Error("inconsistent snapshot");
            delete provider.itemIds;
        }
        return deepFreeze({ providers: providers,
            totalUpdates: providers.reduce((total, provider) => total + provider.pending, 0) });
    } catch (error) {
        return null;
    }
}

function parseAction(payload) {
    try {
        const lines = records(payload, "update-center-action-protocol\t1\t0", "complete\taction");
        if (lines.length !== 1) throw new Error("invalid action");
        const values = lines[0];
        if (values.length === 2 && values[0] === "active" && values[1] === "none")
            return deepFreeze({ operationId: "", providerId: "", action: "", phase: "", outcome: "" });
        if (values.length !== 6 || values[0] !== "operation" || !/^op-[0-9a-f]{32}$/.test(values[1])
                || providerOrder.indexOf(values[2]) < 0 || operationActions.indexOf(values[3]) < 0
                || operationPhases.indexOf(values[4]) < 0 || operationOutcomes.indexOf(values[5]) < 0)
            throw new Error("invalid operation");
        if ((values[4] === "completed" && values[5] !== "succeeded")
                || (["failed", "system-failed", "system-complete/user-failed"].indexOf(values[4]) >= 0 && values[5] !== "failed")
                || (values[4] === "interrupted" && values[5] !== "unknown")
                || (values[4] === "closed" && ["succeeded", "failed"].indexOf(values[5]) < 0)
                || (["completed", "failed", "interrupted", "system-failed", "system-complete/user-failed", "closed"].indexOf(values[4]) < 0
                    && values[5] !== "pending")) throw new Error("inconsistent operation");
        return deepFreeze({ operationId: values[1], providerId: values[2], action: values[3], phase: values[4], outcome: values[5] });
    } catch (error) {
        return null;
    }
}

function parseSettings(payload) {
    try {
        const lines = records(payload, "update-center-settings-protocol\t1\t0", "complete\tstatus");
        let state = null, refreshSeconds = null, alwaysShow = null, baseline = null;
        for (const values of lines) {
            if (values[0] === "state" && values.length === 3 && state === null
                    && ["available", "defaults", "partial", "unavailable"].indexOf(values[1]) >= 0)
                state = { status: values[1], detail: values[2] };
            else if (values[0] === "preference" && values.length === 3 && values[1] === "refreshSeconds" && refreshSeconds === null)
                refreshSeconds = integer(values[2], 21600);
            else if (values[0] === "preference" && values.length === 3 && values[1] === "alwaysShow" && alwaysShow === null
                    && (values[2] === "enabled" || values[2] === "disabled")) alwaysShow = values[2] === "enabled";
            else if (values[0] === "baseline" && values.length === 2 && baseline === null
                    && (values[1] === "absent" || /^[0-9a-f]{64}$/.test(values[1]))) baseline = values[1];
            else throw new Error("invalid setting");
        }
        if (state === null || refreshSeconds === null || refreshSeconds < 300 || alwaysShow === null || baseline === null)
            throw new Error("incomplete settings");
        return deepFreeze({ state: state.status, detail: state.detail, refreshSeconds: refreshSeconds,
            alwaysShow: alwaysShow, baseline: baseline });
    } catch (error) {
        return null;
    }
}
