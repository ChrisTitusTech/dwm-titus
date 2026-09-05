import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool settingsVisible: false
    property string snapshotState: "idle"
    property string message: "System management has not been loaded"
    property string generation: ""
    property var updateProvider: root.providerFallback("Update status has not been loaded")
    property var recoveryProvider: root.recoveryFallback("Recovery status has not been loaded")
    property var updateSummary: root.stateFallback("Update status has not been loaded")
    property var updateLastRefresh: root.stateFallback("Refresh history has not been loaded")
    property var updateRestart: root.stateFallback("Restart guidance has not been loaded")
    property var actions: []
    property var updates: []
    property var packageChanges: []
    property var errors: []
    property var activeOperation: null
    property var terminalHandoff: null
    property bool snapshotPending: false
    property int requestGeneration: 0

    readonly property bool busy: snapshotProcess.running
    readonly property string providerState: root.updateProvider.status
    readonly property string providerDetail: root.updateProvider.detail

    function providerFallback(detail) {
        return { "status": "unavailable", "providerClass": "delegated",
            "owner": "", "detail": detail };
    }

    function recoveryFallback(detail) {
        return { "status": "unavailable", "providerClass": "user-session",
            "owner": "", "detail": detail };
    }

    function stateFallback(detail) {
        return { "status": "unavailable", "value": "unknown", "detail": detail };
    }

    function validProviderStatus(value) {
        return value === "available" || value === "partial" || value === "restricted"
            || value === "unavailable" || value === "unsupported";
    }

    function validErrorCode(value) {
        return value === "network" || value === "repository" || value === "conflict"
            || value === "signature" || value === "package" || value === "unsupported"
            || value === "malformed" || value === "missing-provider"
            || value === "permission-denied" || value === "canceled"
            || value === "timeout" || value === "interrupted" || value === "internal";
    }

    function validSeverity(value) {
        return value === "critical" || value === "security" || value === "important"
            || value === "bugfix" || value === "enhancement" || value === "normal"
            || value === "low" || value === "unknown";
    }

    function validRestart(value) {
        return value === "none" || value === "application" || value === "session"
            || value === "system" || value === "security-session"
            || value === "security-system" || value === "unknown";
    }

    function validPlanAction(value) {
        return value === "install" || value === "update" || value === "remove"
            || value === "obsolete" || value === "reinstall" || value === "downgrade";
    }

    function validOperationState(value) {
        return value === "pending" || value === "authorizing" || value === "running"
            || value === "cancel-requested";
    }

    function validPercent(value) {
        return value === "unknown" || (/^(0|[1-9][0-9]?)$/.test(value)) || value === "100";
    }

    function validOperationId(value) {
        return /^op-[0-9a-f]{32}$/.test(value);
    }

    function validGeneration(value) {
        return /^[0-9a-f]{64}$/.test(value);
    }

    function utf8Bytes(value) {
        let count = 0;
        for (let index = 0; index < value.length; index++) {
            const code = value.charCodeAt(index);
            if (code < 0x80) count += 1;
            else if (code < 0x800) count += 2;
            else if (code >= 0xd800 && code <= 0xdbff && index + 1 < value.length
                    && value.charCodeAt(index + 1) >= 0xdc00
                    && value.charCodeAt(index + 1) <= 0xdfff) {
                count += 4;
                index++;
            } else count += 3;
        }
        return count;
    }

    function fieldsFit(fields, count) {
        if (fields.length < count) return false;
        for (let index = 1; index < count; index++) {
            if (root.utf8Bytes(fields[index]) > 512) return false;
        }
        return true;
    }

    function updateActionKind(actionId) {
        if (actionId === "updates-refresh") return "refresh";
        if (actionId === "updates-install-all") return "update";
        return "";
    }

    function operationActionKind(actionId) {
        const updateKind = root.updateActionKind(actionId);
        if (updateKind.length > 0) return updateKind;
        if (actionId === "timezone-set") return "timezone";
        if (actionId === "ntp-set") return "ntp";
        if (actionId === "locale-set") return "locale";
        if (actionId === "accounts-open" || actionId === "password-open"
                || actionId === "printers-open" || actionId === "sources-open") return "delegate";
        return "";
    }

    function clearState(detail) {
        root.snapshotState = "failure";
        root.message = detail;
        root.generation = "";
        root.updateProvider = root.providerFallback(detail);
        root.recoveryProvider = root.recoveryFallback(detail);
        root.updateSummary = root.stateFallback(detail);
        root.updateLastRefresh = root.stateFallback(detail);
        root.updateRestart = root.stateFallback(detail);
        root.actions = [];
        root.updates = [];
        root.packageChanges = [];
        root.errors = [];
        root.activeOperation = null;
        root.terminalHandoff = null;
    }

    function parseSnapshot(text, responseGeneration) {
        if (responseGeneration !== root.requestGeneration || !root.settingsVisible) return;
        if (root.utf8Bytes(text) > 8 * 1024 * 1024) {
            root.clearState("System management provider returned an oversized response");
            return;
        }

        let headerSeen = false;
        let completeSeen = false;
        let parsedGeneration = "";
        let fatal = "";
        let updatesInvalid = false;
        let planInvalid = false;
        let planUnsupported = false;
        let recoveryInvalid = false;
        let parsedUpdateProvider = null;
        let parsedRecoveryProvider = null;
        const states = {};
        const parsedActions = {};
        const parsedUpdates = [];
        const parsedChanges = [];
        const parsedErrors = [];
        let parsedActive = null;
        let parsedHandoff = null;
        let updateBytes = 0;
        let changeBytes = 0;
        let errorBytes = 0;
        let updateRecordCount = 0;
        let changeRecordCount = 0;
        let errorRecordCount = 0;
        let recordIndex = 0;
        const seenProviders = {};
        const seenStates = {};
        const seenActions = {};
        const seenUpdates = {};
        const seenChanges = {};

        for (const rawLine of text.split("\n")) {
            if (rawLine.length === 0) continue;
            const fields = rawLine.split("\t");
            const type = fields[0];
            if (completeSeen) {
                fatal = "System management provider emitted records after completion";
                break;
            }
            if (recordIndex === 0 && type !== "system-management-protocol") {
                fatal = "System management provider response has no leading protocol header";
                break;
            }
            recordIndex++;

            if (type === "system-management-protocol") {
                if (headerSeen || fields.length < 3 || fields[1] !== "1" || fields[2] !== "0") {
                    fatal = "System management provider returned an unsupported protocol";
                    break;
                }
                headerSeen = true;
            } else if (type === "snapshot-generation") {
                if (parsedGeneration.length > 0 || fields.length < 2
                        || !root.validGeneration(fields[1])) {
                    fatal = "System management provider returned an invalid generation";
                    break;
                }
                parsedGeneration = fields[1];
            } else if (type === "provider") {
                if (fields.length < 2 || (fields[1] !== "updates" && fields[1] !== "recovery")) {
                    fatal = "System management provider returned an unknown provider owner";
                    break;
                }
                if (seenProviders["$" + fields[1]] !== undefined) {
                    fatal = "System management provider repeated a provider record";
                    break;
                }
                seenProviders["$" + fields[1]] = true;
                if (!root.fieldsFit(fields, 6) || !root.validProviderStatus(fields[2])) {
                    if (fields[1] === "updates") updatesInvalid = true;
                    else recoveryInvalid = true;
                    continue;
                }
                if ((fields[1] === "updates" && fields[3] !== "delegated")
                        || (fields[1] === "recovery" && fields[3] !== "user-session")) {
                    if (fields[1] === "updates") updatesInvalid = true;
                    else recoveryInvalid = true;
                    continue;
                }
                const provider = { "status": fields[2], "providerClass": fields[3],
                    "owner": fields[4], "detail": fields[5] };
                if (fields[1] === "updates") {
                    parsedUpdateProvider = provider;
                } else {
                    parsedRecoveryProvider = provider;
                }
            } else if (type === "state") {
                if (fields.length < 2 || (fields[1] !== "update-summary"
                        && fields[1] !== "update-last-refresh"
                        && fields[1] !== "update-restart")) {
                    fatal = "System management provider returned an unknown state owner";
                    break;
                }
                if (seenStates["$" + fields[1]] !== undefined) {
                    fatal = "System management provider repeated a state record";
                    break;
                }
                seenStates["$" + fields[1]] = true;
                if (!root.fieldsFit(fields, 5) || !root.validProviderStatus(fields[2])) {
                    updatesInvalid = true;
                    continue;
                }
                const available = fields[2] === "available";
                let valueValid = true;
                if (fields[1] === "update-summary") {
                    valueValid = available ? /^(0|[1-9][0-9]*)$/.test(fields[3])
                        && Number(fields[3]) <= 4096 : fields[3] === "unknown";
                } else if (fields[1] === "update-last-refresh") {
                    valueValid = available ? /^(0|[1-9][0-9]*)$/.test(fields[3])
                        && Number(fields[3]) <= 4294967294 : fields[3] === "unknown";
                } else {
                    valueValid = root.validRestart(fields[3])
                        && (available || fields[2] === "partial" || fields[3] === "unknown");
                }
                if (!valueValid) {
                    updatesInvalid = true;
                    continue;
                }
                states["$" + fields[1]] = { "status": fields[2], "value": fields[3],
                    "detail": fields[4] };
            } else if (type === "action") {
                if (fields.length < 2 || (fields[1] !== "updates-refresh"
                        && fields[1] !== "updates-install-all"
                        && fields[1] !== "updates-cancel")) {
                    fatal = "System management provider returned an unknown action owner";
                    break;
                }
                if (seenActions["$" + fields[1]] !== undefined) {
                    fatal = "System management provider repeated an action record";
                    break;
                }
                seenActions["$" + fields[1]] = true;
                if (!root.fieldsFit(fields, 7)
                        || (fields[2] !== "available" && fields[2] !== "unavailable")
                        || fields[3] !== "delegated" || fields[4] !== "updates") {
                    updatesInvalid = true;
                    continue;
                }
                parsedActions["$" + fields[1]] = { "id": fields[1],
                    "availability": fields[2], "actionClass": fields[3],
                    "owner": fields[4], "label": fields[5], "detail": fields[6] };
            } else if (type === "update") {
                updateRecordCount++;
                if (updateRecordCount > 4096) {
                    updatesInvalid = true;
                    continue;
                }
                if (fields.length >= 2 && fields[1].length > 0) {
                    if (seenUpdates["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated an update identity";
                        break;
                    }
                    seenUpdates["$" + fields[1]] = true;
                }
                if (!root.fieldsFit(fields, 7) || fields[1].length === 0
                        || !root.validSeverity(fields[2])
                        || (fields[3] !== "installable" && fields[3] !== "blocked")
                        || fields[4].length === 0 || fields[5].length === 0) {
                    updatesInvalid = true;
                    continue;
                }
                const recordBytes = root.utf8Bytes(rawLine) + 1;
                if (updatesInvalid || updateBytes + recordBytes > 3 * 1024 * 1024) {
                    updatesInvalid = true;
                    continue;
                }
                parsedUpdates.push({ "packageId": fields[1], "severity": fields[2],
                    "installability": fields[3], "name": fields[4],
                    "version": fields[5], "summary": fields[6] });
                updateBytes += recordBytes;
            } else if (type === "package-change") {
                changeRecordCount++;
                if (changeRecordCount > 4096) {
                    planInvalid = true;
                    continue;
                }
                if (fields.length >= 2 && fields[1].length > 0) {
                    if (seenChanges["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated a plan identity";
                        break;
                    }
                    seenChanges["$" + fields[1]] = true;
                }
                if (!root.fieldsFit(fields, 6) || fields[1].length === 0
                        || !root.validPlanAction(fields[2]) || fields[3].length === 0
                        || fields[4].length === 0) {
                    planInvalid = true;
                    continue;
                }
                const recordBytes = root.utf8Bytes(rawLine) + 1;
                if (planInvalid || changeBytes + recordBytes > 3 * 1024 * 1024) {
                    planInvalid = true;
                    continue;
                }
                parsedChanges.push({ "packageId": fields[1], "action": fields[2],
                    "name": fields[3], "version": fields[4], "summary": fields[5] });
                changeBytes += recordBytes;
            } else if (type === "error") {
                errorRecordCount++;
                const recordBytes = root.utf8Bytes(rawLine) + 1;
                if (errorRecordCount > 4096 || errorBytes + recordBytes > 1024 * 1024) {
                    fatal = "System management provider exceeded the error record budget";
                    break;
                }
                errorBytes += recordBytes;
                if (fields.length < 2 || (fields[1] !== "updates" && fields[1] !== "recovery")) {
                    fatal = "System management provider returned an unknown error owner";
                    break;
                }
                if (!root.fieldsFit(fields, 4) || !root.validErrorCode(fields[2])) {
                    if (fields[1] === "updates") updatesInvalid = true;
                    else recoveryInvalid = true;
                    continue;
                }
                parsedErrors.push({ "provider": fields[1], "code": fields[2],
                    "detail": fields[3] });
            } else if (type === "active-operation") {
                if (parsedActive !== null || parsedHandoff !== null) {
                    fatal = "System management provider repeated snapshot operation state";
                    break;
                }
                if (!root.fieldsFit(fields, 8) || !root.validOperationId(fields[1])
                        || root.updateActionKind(fields[2]).length === 0
                        || root.updateActionKind(fields[2]) !== fields[3]
                        || !root.validOperationState(fields[4])
                        || !root.validPercent(fields[5])
                        || (fields[6] !== "yes" && fields[6] !== "no")) {
                    fatal = "System management provider returned an invalid active operation";
                    break;
                }
                parsedActive = { "id": fields[1], "actionId": fields[2],
                    "kind": fields[3], "state": fields[4], "percent": fields[5],
                    "cancelable": fields[6] === "yes", "detail": fields[7] };
            } else if (type === "terminal-handoff") {
                if (parsedActive !== null || parsedHandoff !== null) {
                    fatal = "System management provider repeated snapshot operation state";
                    break;
                }
                if (!root.fieldsFit(fields, 4) || !root.validOperationId(fields[1])
                        || root.operationActionKind(fields[2]).length === 0
                        || root.operationActionKind(fields[2]) !== fields[3]) {
                    fatal = "System management provider returned an invalid terminal handoff";
                    break;
                }
                parsedHandoff = { "id": fields[1], "actionId": fields[2],
                    "kind": fields[3] };
            } else if (type === "complete") {
                if (fields.length < 2 || fields[1] !== "snapshot") {
                    fatal = "System management provider returned an invalid completion";
                    break;
                }
                completeSeen = true;
            }
        }

        if (fatal.length > 0 || !headerSeen || !completeSeen || parsedGeneration.length === 0) {
            root.clearState(fatal.length > 0 ? fatal
                : "System management provider returned an incomplete response");
            return;
        }
        if (parsedUpdateProvider === null || states["$update-summary"] === undefined
                || states["$update-last-refresh"] === undefined
                || states["$update-restart"] === undefined
                || parsedActions["$updates-refresh"] === undefined
                || parsedActions["$updates-install-all"] === undefined
                || parsedActions["$updates-cancel"] === undefined) updatesInvalid = true;
        if (parsedRecoveryProvider === null) recoveryInvalid = true;
        if (!updatesInvalid) {
            const cancelAvailable = parsedActions["$updates-cancel"].availability === "available";
            const canCancelActive = parsedActive !== null && parsedActive.cancelable;
            if (cancelAvailable !== canCancelActive) updatesInvalid = true;
        }
        if (!updatesInvalid) {
            const summaryAvailable = states["$update-summary"].status === "available";
            if ((summaryAvailable
                    && Number(states["$update-summary"].value) !== parsedUpdates.length)
                    || (!summaryAvailable && parsedUpdates.length > 0))
                updatesInvalid = true;
        }
        if (!updatesInvalid && !planInvalid) {
            const requestedUpdates = {};
            let requestedCount = 0;
            let planRequiresUnsupportedFlags = false;
            for (const update of parsedUpdates) {
                if (update.installability === "installable") {
                    requestedUpdates["$" + update.packageId] = false;
                    requestedCount++;
                }
            }
            if (parsedChanges.length > 0) {
                for (const change of parsedChanges) {
                    if (change.action === "reinstall" || change.action === "downgrade")
                        planRequiresUnsupportedFlags = true;
                    const key = "$" + change.packageId;
                    if (requestedUpdates[key] !== undefined) {
                        if (change.action !== "update" && change.action !== "install") {
                            planInvalid = true;
                            break;
                        }
                        requestedUpdates[key] = true;
                    } else if (change.action === "update") planInvalid = true;
                }
                if (!planInvalid && requestedCount > 0) {
                    for (const key in requestedUpdates) {
                        if (!requestedUpdates[key]) {
                            planInvalid = true;
                            break;
                        }
                    }
                }
            }
            planUnsupported = planRequiresUnsupportedFlags;
            if (!planInvalid && ((requestedCount === 0 && parsedChanges.length > 0)
                    || (requestedCount > 0 && parsedChanges.length === 0
                        && parsedActions["$updates-install-all"].availability === "available")
                    || (parsedActions["$updates-install-all"].availability === "available"
                        && requestedCount === 0)))
                planInvalid = true;
        }

        root.generation = parsedGeneration;
        root.activeOperation = parsedActive;
        root.terminalHandoff = parsedHandoff;
        if (updatesInvalid) {
            const detail = "System management provider returned malformed update state";
            root.updateProvider = { "status": "partial", "providerClass": "delegated",
                "owner": "PackageKit", "detail": detail };
            root.updateSummary = { "status": "partial", "value": "unknown", "detail": detail };
            root.updateLastRefresh = { "status": "partial", "value": "unknown", "detail": detail };
            root.updateRestart = { "status": "partial", "value": "unknown", "detail": detail };
            root.actions = [];
            root.updates = [];
            root.packageChanges = [];
        } else if (planInvalid) {
            const detail = "System management provider returned a malformed update plan";
            const installAction = parsedActions["$updates-install-all"];
            root.updateProvider = { "status": "partial", "providerClass": "delegated",
                "owner": parsedUpdateProvider.owner, "detail": detail };
            root.updateSummary = states["$update-summary"];
            root.updateLastRefresh = states["$update-last-refresh"];
            root.updateRestart = states["$update-restart"];
            root.actions = [parsedActions["$updates-refresh"], {
                "id": installAction.id, "availability": "unavailable",
                "actionClass": installAction.actionClass, "owner": installAction.owner,
                "label": installAction.label, "detail": detail
            }, parsedActions["$updates-cancel"]];
            root.updates = parsedUpdates;
            root.packageChanges = [];
            parsedErrors.push({ "provider": "updates", "code": "malformed",
                "detail": detail });
        } else {
            let installAction = parsedActions["$updates-install-all"];
            if (planUnsupported) {
                const detail = "This update plan requires unsupported reinstall or downgrade flags";
                installAction = { "id": installAction.id, "availability": "unavailable",
                    "actionClass": installAction.actionClass, "owner": installAction.owner,
                    "label": installAction.label, "detail": detail };
                let unsupportedErrorSeen = false;
                for (const error of parsedErrors) {
                    if (error.provider === "updates" && error.code === "unsupported") {
                        unsupportedErrorSeen = true;
                        break;
                    }
                }
                if (!unsupportedErrorSeen)
                    parsedErrors.push({ "provider": "updates", "code": "unsupported",
                        "detail": detail });
            }
            root.updateProvider = parsedUpdateProvider;
            root.updateSummary = states["$update-summary"];
            root.updateLastRefresh = states["$update-last-refresh"];
            root.updateRestart = states["$update-restart"];
            root.actions = [parsedActions["$updates-refresh"], installAction,
                parsedActions["$updates-cancel"]];
            root.updates = parsedUpdates;
            root.packageChanges = parsedChanges;
        }
        root.recoveryProvider = recoveryInvalid
            ? { "status": "partial", "providerClass": "user-session",
                "owner": "dwm-system-management",
                "detail": "System management provider returned malformed recovery state" }
            : parsedRecoveryProvider;
        root.errors = parsedErrors;
        root.snapshotState = updatesInvalid || planInvalid || planUnsupported || recoveryInvalid
            ? "partial" : "ready";
        root.message = root.snapshotState === "ready"
            ? parsedUpdates.length + " updates reported"
            : "System management state is incomplete";
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh();
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.requestGeneration++;
        root.snapshotPending = false;
        snapshotProcess.running = false;
    }

    function refresh() {
        if (!root.settingsVisible) return;
        if (snapshotProcess.running) {
            root.snapshotPending = true;
            return;
        }
        root.snapshotPending = false;
        root.requestGeneration++;
        snapshotProcess.generation = root.requestGeneration;
        root.snapshotState = "loading";
        root.message = "Reading system update status...";
        snapshotProcess.running = true;
    }

    Process {
        id: snapshotProcess
        property int generation: 0
        command: Commands.terminatingCheckedCommand(
            Commands.systemManagementCommand("snapshot", []))
        running: false
        stdout: StdioCollector {
            id: snapshotOutput
        }
        stderr: StdioCollector {
            id: snapshotError
        }
        onRunningChanged: {
            if (!running && snapshotProcess.generation === root.requestGeneration
                    && root.settingsVisible) {
                root.parseSnapshot(snapshotOutput.text, snapshotProcess.generation);
                const rawError = snapshotError.text.replace(/\s+/g, " ").trim();
                const detail = root.utf8Bytes(rawError) <= 512 ? rawError
                    : "Provider error detail exceeded the protocol limit";
                if (root.snapshotState === "failure" && detail.length > 0)
                    root.message = "System management snapshot process failed: " + detail;
            }
            if (!running && root.snapshotPending && root.settingsVisible) {
                root.snapshotPending = false;
                Qt.callLater(root.refresh);
            }
        }
    }
}
