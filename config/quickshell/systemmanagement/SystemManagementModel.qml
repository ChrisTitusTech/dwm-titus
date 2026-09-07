import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    signal confirmationInvalidated()
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
    property var nativeProviders: ({})
    property var nativeStates: ({})
    property var accounts: []
    property var repositories: []
    property var errors: []
    property var activeOperation: null
    property var terminalHandoff: null
    property bool snapshotPending: false
    property bool requiredPending: false
    property bool snapshotOwned: false
    property bool snapshotRequired: false
    property bool snapshotHasOutput: false
    property bool discoveryBatch: false
    property string snapshotErrorDetail: ""
    property int requestGeneration: 0
    property var updateConfirmation: null
    property string confirmationMessage: ""
    property bool dispatchingUpdate: false
    property var nativeConfirmation: null
    property string nativeConfirmationMessage: ""
    property bool dispatchingNative: false
    readonly property alias operation: operationModel
    readonly property alias discovery: discoveryModel
    readonly property alias timeDiscovery: timeDiscoveryModel
    readonly property alias localeDiscovery: localeDiscoveryModel
    readonly property alias accountDiscovery: accountDiscoveryModel
    readonly property alias printerDiscovery: printerDiscoveryModel
    readonly property alias regional: regionalModel

    readonly property bool busy: snapshotOwned
    readonly property string providerState: root.settingsVisible
        && (discoveryModel.unresolved || discoveryModel.failed) && root.updateProvider.status === "available"
        ? "partial" : root.updateProvider.status
    readonly property string providerDetail: root.updateProvider.detail
    readonly property string discoveryDetail: discoveryModel.detail

    function discoveryModels() {
        return [discoveryModel, timeDiscoveryModel, localeDiscoveryModel,
            accountDiscoveryModel, printerDiscoveryModel];
    }

    function discoveryReady() {
        return root.settingsVisible && root.discoveryModels().every(model => model.visible && (model.ready || model.failed));
    }

    function invalidateActionDiscovery(action) {
        if (action === "timezone-set" || action === "ntp-set") timeDiscoveryModel.invalidate();
        else if (action === "locale-set") localeDiscoveryModel.invalidate();
        else if (action === "accounts-open" || action === "password-open") accountDiscoveryModel.invalidate();
        else if (action === "printers-open") printerDiscoveryModel.invalidate();
        else if (action === "sources-open" || action === "updates-refresh" || action === "updates-install-all")
            discoveryModel.invalidate();
    }

    function stateDiscovery(identifier) {
        if (identifier === "timezone" || identifier === "ntp-enabled" || identifier === "ntp-synchronized") return timeDiscoveryModel;
        if (identifier === "locale") return localeDiscoveryModel;
        if (identifier === "accounts-count") return accountDiscoveryModel;
        if (identifier === "cups-service") return printerDiscoveryModel;
        return null;
    }

    function nativeStateView(identifier) {
        const state = root.nativeStates[identifier] || root.stateFallback("This state is unavailable");
        const monitor = root.stateDiscovery(identifier);
        if (!root.settingsVisible || monitor === null) return state;
        return { status: state.status === "available" && (monitor.failed || monitor.unresolved) ? "partial" : state.status,
            value: state.value, detail: [state.detail, monitor.detail].filter(value => value.length > 0).join(" ") };
    }

    function nativeProviderView(owner) {
        const provider = root.nativeProviders[owner] || root.providerFallback("This provider is unavailable");
        const monitors = owner === "regional" ? [timeDiscoveryModel, localeDiscoveryModel]
            : owner === "accounts" ? [accountDiscoveryModel] : owner === "printers" ? [printerDiscoveryModel]
            : owner === "sources" ? [discoveryModel] : [];
        if (!root.settingsVisible) return provider;
        return { status: provider.status === "available" && monitors.some(model => model.failed || model.unresolved)
                ? "partial" : provider.status,
            providerClass: provider.providerClass, owner: provider.owner,
            detail: [provider.detail].concat(monitors.map(model => model.detail)).filter(value => value.length > 0).join(" ") };
    }

    function updateActionReason(actionId) {
        if (actionId !== "updates-refresh" && actionId !== "updates-install-all")
            return "This update action is not supported.";
        if (!root.settingsVisible)
            return "Open System Settings to prepare an update action.";
        if (root.dispatchingUpdate || root.dispatchingNative || root.nativeConfirmation !== null
                || regionalModel.ownsPreparation() || regionalModel.confirmation !== null)
            return "Finish or dismiss the current confirmation first.";
        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || !discoveryModel.fresh)
            return "Wait for fresh update discovery, or reload status to retry.";
        if (!root.validGeneration(root.generation) || root.recoveryProvider.status !== "available")
            return "Complete recovery evidence is required. Reload status to retry.";
        if (!operationModel.canStart)
            return "An operation or its recovery still owns the update workflow.";
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.availability !== "available")
            return action && action.detail.length > 0 ? action.detail : "The provider did not offer this action.";
        if (actionId === "updates-install-all" && root.packageChanges.length === 0)
            return "No complete installable package-change preview is available.";
        return "";
    }

    function prepareUpdate(actionId) {
        const reason = root.updateActionReason(actionId);
        if (reason.length > 0) {
            root.confirmationMessage = reason;
            return false;
        }
        root.confirmationMessage = "";
        root.updateConfirmation = {
            actionId: actionId, generation: root.generation,
            requestGeneration: root.requestGeneration, epoch: discoveryModel.cycle.epoch,
            changes: actionId === "updates-install-all"
                ? JSON.parse(JSON.stringify(root.packageChanges)) : []
        };
        return true;
    }

    function discardUpdate() {
        root.updateConfirmation = null;
        root.confirmationMessage = "";
    }

    function confirmUpdate() {
        const pending = root.updateConfirmation;
        if (pending === null || root.dispatchingUpdate) return false;
        const reason = root.updateActionReason(pending.actionId);
        if (reason.length > 0 || pending.generation !== root.generation
                || pending.requestGeneration !== root.requestGeneration
                || pending.epoch !== discoveryModel.cycle.epoch) {
            root.confirmationInvalidated();
            return false;
        }
        // Capture the fixed arguments and claim dispatch before clearing the
        // prompt: reentrant UI callbacks must not dispatch another origin.
        root.dispatchingUpdate = true;
        root.updateConfirmation = null;
        const started = operationModel.startUpdate(pending.actionId,
            pending.actionId === "updates-install-all" ? pending.generation : "");
        root.confirmationMessage = started ? "" : "Update state changed. Reload status and confirm again.";
        root.dispatchingUpdate = false;
        return started;
    }

    onConfirmationInvalidated: {
        if (root.updateConfirmation !== null)
            root.confirmationMessage = "Update state changed. Review a fresh preview and confirm again.";
        root.updateConfirmation = null;
        root.invalidateNativeConfirmation("");
        regionalModel.invalidate("");
    }

    function delegateDiscovery(actionId) {
        if (actionId === "accounts-open" || actionId === "password-open") return accountDiscoveryModel;
        if (actionId === "printers-open") return printerDiscoveryModel;
        if (actionId === "sources-open") return discoveryModel;
        return null;
    }

    function delegateContextReason(actionId) {
        const monitor = root.delegateDiscovery(actionId);
        if (monitor === null) return "This delegated action is not supported.";
        if (!root.settingsVisible) return "Open System Settings to prepare this action.";
        if (root.snapshotOwned || root.snapshotPending || root.requiredPending || root.discoveryBatch
                || !monitor.visible || !monitor.ready || monitor.failed || !monitor.cycle.enabled
                || monitor.cycle.phase !== "idle" || monitor.cycle.unresolved)
            return "Wait for fresh provider status, or reload status to retry.";
        if (!root.validGeneration(root.generation) || !operationModel.canStart)
            return "An operation or its recovery still owns the system workflow.";
        const action = root.actions.find(item => item.id === actionId);
        if (!action || action.availability !== "available")
            return action && action.detail.length > 0 ? action.detail : "The provider did not offer this action.";
        return "";
    }

    function delegateActionReason(actionId) {
        if (root.dispatchingUpdate || root.dispatchingNative || root.updateConfirmation !== null
                || regionalModel.ownsPreparation() || regionalModel.confirmation !== null)
            return "Finish or dismiss the current confirmation first.";
        return root.delegateContextReason(actionId);
    }

    function prepareDelegate(actionId) {
        if (root.nativeConfirmation !== null) return false;
        const reason = root.delegateActionReason(actionId);
        if (reason.length > 0) {
            root.nativeConfirmationMessage = reason;
            return false;
        }
        const pending = { actionId: actionId, generation: root.generation,
            requestGeneration: root.requestGeneration, epoch: root.delegateDiscovery(actionId).cycle.epoch };
        root.dispatchingNative = true;
        root.nativeConfirmationMessage = "";
        // Reentrant closure or discovery callbacks may retire this preparation.
        if (root.delegateContextReason(actionId) === "" && pending.generation === root.generation
                && pending.requestGeneration === root.requestGeneration
                && pending.epoch === root.delegateDiscovery(actionId).cycle.epoch)
            root.nativeConfirmation = pending;
        root.dispatchingNative = false;
        return root.nativeConfirmation === pending;
    }

    function discardDelegate() {
        root.nativeConfirmation = null;
        root.nativeConfirmationMessage = "";
    }

    function invalidateNativeConfirmation(domain) {
        const pending = root.nativeConfirmation;
        if (pending === null) return;
        const monitor = root.delegateDiscovery(pending.actionId);
        if (domain !== "" && (monitor === null || monitor.domain !== domain)) return;
        root.nativeConfirmationMessage = "Provider state changed. Reload status and confirm again.";
        root.nativeConfirmation = null;
    }

    function confirmDelegate() {
        const pending = root.nativeConfirmation;
        if (pending === null || root.dispatchingUpdate || root.dispatchingNative) return false;
        if (root.delegateActionReason(pending.actionId) !== "") {
            root.invalidateNativeConfirmation("");
            return false;
        }
        root.dispatchingNative = true;
        root.nativeConfirmation = null;
        // Recheck after prompt callbacks; the operation owner checks its own
        // source ownership again before constructing the fixed empty argv.
        const monitor = root.delegateDiscovery(pending.actionId);
        const current = root.delegateContextReason(pending.actionId) === ""
            && pending.generation === root.generation && pending.requestGeneration === root.requestGeneration
            && monitor !== null && pending.epoch === monitor.cycle.epoch;
        const started = current && operationModel.startNative(pending.actionId, "", "");
        root.nativeConfirmationMessage = started ? "" : "Provider state changed. Reload status and confirm again.";
        root.dispatchingNative = false;
        return started;
    }

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

    function nativeStateOwner(identifier) {
        if (identifier === "timezone" || identifier === "ntp-enabled"
                || identifier === "ntp-synchronized" || identifier === "locale") return "regional";
        if (identifier === "accounts-count") return "accounts";
        if (identifier === "cups-service") return "printers";
        return "";
    }

    function nativeActionOwner(identifier) {
        if (identifier === "timezone-set" || identifier === "ntp-set" || identifier === "locale-set") return "regional";
        if (identifier === "accounts-open" || identifier === "password-open") return "accounts";
        if (identifier === "printers-open") return "printers";
        if (identifier === "sources-open") return "sources";
        return "";
    }

    function validNativeValue(identifier, status, value) {
        if (identifier === "accounts-count")
            return status === "available" ? /^(0|[1-9][0-9]*)$/.test(value)
                && Number(value) <= 256 : value === "unknown";
        if (identifier === "cups-service")
            return status === "available" ? (value === "running" || value === "socket-ready" || value === "stopped")
                : value === "unknown";
        if (identifier === "ntp-enabled" || identifier === "ntp-synchronized")
            return status === "available" ? (value === "yes" || value === "no") : value === "unknown";
        // An explicit LANG= is readable unset configuration, not a malformed
        // regional provider. A replacement still requires its own fresh preview.
        if (identifier === "locale") return status === "available" || value === "unknown";
        return value.length > 0 && (status === "available" || value === "unknown");
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
        root.nativeProviders = {};
        root.nativeStates = {};
        root.accounts = [];
        root.repositories = [];
        root.errors = [];
        root.activeOperation = null;
        root.terminalHandoff = null;
    }

    function parseSnapshot(text, responseGeneration) {
        if (responseGeneration !== root.requestGeneration) return false;
        if (root.utf8Bytes(text) > 8 * 1024 * 1024) {
            root.clearState("System management provider returned an oversized response");
            return;
        }

        let headerSeen = false;
        let minor = 0;
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
        const nativeOwners = ["regional", "accounts", "printers", "sources"];
        const nativeStateIds = ["timezone", "ntp-enabled", "ntp-synchronized", "locale", "accounts-count", "cups-service"];
        const nativeActionIds = ["timezone-set", "ntp-set", "locale-set", "accounts-open", "password-open", "printers-open", "sources-open"];
        const nativeInvalid = {};
        const parsedNativeProviders = {};
        const nativeLists = { account: [], repository: [] };
        const nativeListCounts = { account: 0, repository: 0 };
        const nativeListBytes = { account: 0, repository: 0 };
        const nativeSeen = { account: {}, repository: {} };
        let nonListBytes = 0;
        let listRecordCount = 0;

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
            if (type === "update" || type === "package-change" || type === "account" || type === "repository") {
                // Keep duplicate tracking through a provider-local overflow,
                // while the complete protocol reservation bounds its memory.
                if (++listRecordCount > 9216) {
                    fatal = "System management provider exceeded the overall list reservation";
                    break;
                }
            } else {
                nonListBytes += root.utf8Bytes(rawLine) + 1;
                if (nonListBytes > 1024 * 1024) {
                    fatal = "System management provider exceeded the non-list byte reservation";
                    break;
                }
            }

            if (type === "system-management-protocol") {
                if (headerSeen || fields.length < 3 || fields[1] !== "1" || (fields[2] !== "0" && fields[2] !== "1")) {
                    fatal = "System management provider returned an unsupported protocol";
                    break;
                }
                headerSeen = true;
                minor = Number(fields[2]);
            } else if (type === "snapshot-generation") {
                if (parsedGeneration.length > 0 || fields.length < 2
                        || !root.validGeneration(fields[1])) {
                    fatal = "System management provider returned an invalid generation";
                    break;
                }
                parsedGeneration = fields[1];
            } else if (type === "provider") {
                if (minor === 1 && fields.length >= 2 && nativeOwners.indexOf(fields[1]) !== -1) {
                    const owner = fields[1];
                    if (seenProviders["$" + owner] !== undefined) {
                        fatal = "System management provider repeated a provider record";
                        break;
                    }
                    seenProviders["$" + owner] = true;
                    if (!root.fieldsFit(fields, 6) || !root.validProviderStatus(fields[2]) || fields[3] !== "delegated") {
                        nativeInvalid[owner] = true;
                    } else parsedNativeProviders[owner] = { status: fields[2], providerClass: fields[3], owner: fields[4], detail: fields[5] };
                    continue;
                }
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
                const owner = fields.length >= 2 ? root.nativeStateOwner(fields[1]) : "";
                if (minor === 1 && owner.length > 0) {
                    if (seenStates["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated a state record";
                        break;
                    }
                    seenStates["$" + fields[1]] = true;
                    if (!root.fieldsFit(fields, 5) || !root.validProviderStatus(fields[2])
                            || !root.validNativeValue(fields[1], fields[2], fields[3])) nativeInvalid[owner] = true;
                    else states["$" + fields[1]] = { status: fields[2], value: fields[3], detail: fields[4] };
                    continue;
                }
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
                const owner = fields.length >= 2 ? root.nativeActionOwner(fields[1]) : "";
                if (minor === 1 && owner.length > 0) {
                    if (seenActions["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated an action record";
                        break;
                    }
                    seenActions["$" + fields[1]] = true;
                    if (!root.fieldsFit(fields, 7) || (fields[2] !== "available" && fields[2] !== "unavailable")
                            || fields[3] !== "delegated" || fields[4] !== owner) nativeInvalid[owner] = true;
                    else parsedActions["$" + fields[1]] = { id: fields[1], availability: fields[2], actionClass: fields[3],
                        owner: fields[4], label: fields[5], detail: fields[6] };
                    continue;
                }
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
                if (fields.length >= 2 && fields[1].length > 0) {
                    if (seenUpdates["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated an update identity";
                        break;
                    }
                    seenUpdates["$" + fields[1]] = true;
                }
                if (updateRecordCount > 4096) {
                    updatesInvalid = true;
                    continue;
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
                if (fields.length >= 2 && fields[1].length > 0) {
                    if (seenChanges["$" + fields[1]] !== undefined) {
                        fatal = "System management provider repeated a plan identity";
                        break;
                    }
                    seenChanges["$" + fields[1]] = true;
                }
                if (changeRecordCount > 4096) {
                    planInvalid = true;
                    continue;
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
            } else if (type === "account" || type === "repository") {
                if (minor !== 1) {
                    fatal = "System management provider returned an inactive list owner";
                    break;
                }
                const owner = type === "account" ? "accounts" : "sources";
                if (fields.length < 2 || fields[1].length === 0) {
                    fatal = "System management provider returned a list without an identity";
                    break;
                }
                if (nativeSeen[type]["$" + fields[1]] !== undefined) {
                    fatal = "System management provider repeated a list identity";
                    break;
                }
                nativeSeen[type]["$" + fields[1]] = true;
                nativeListCounts[type]++;
                nativeListBytes[type] += root.utf8Bytes(rawLine) + 1;
                const account = type === "account";
                if (nativeListCounts[type] > (account ? 256 : 512)
                        || nativeListBytes[type] > (account ? 256 : 384) * 1024) {
                    nativeInvalid[owner] = true;
                    continue;
                }
                if (!root.fieldsFit(fields, account ? 5 : 4)
                        || (account ? (fields[2] !== "current" && fields[2] !== "other")
                            : (fields[2] !== "enabled" && fields[2] !== "disabled"))
                        || (account && fields[4].length === 0)) {
                    nativeInvalid[owner] = true;
                    continue;
                }
                if (!nativeInvalid[owner]) nativeLists[type].push(account
                    ? { id: fields[1], scope: fields[2], displayName: fields[3], loginName: fields[4] }
                    : { id: fields[1], state: fields[2], description: fields[3] });
            } else if (type === "error") {
                errorRecordCount++;
                const recordBytes = root.utf8Bytes(rawLine) + 1;
                if (errorRecordCount > 4096 || errorBytes + recordBytes > 1024 * 1024) {
                    fatal = "System management provider exceeded the error record budget";
                    break;
                }
                errorBytes += recordBytes;
                if (minor === 1 && fields.length >= 2 && nativeOwners.indexOf(fields[1]) !== -1) {
                    if (!root.fieldsFit(fields, 4) || !root.validErrorCode(fields[2])) nativeInvalid[fields[1]] = true;
                    else parsedErrors.push({ provider: fields[1], code: fields[2], detail: fields[3] });
                    continue;
                }
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
                        || root.operationActionKind(fields[2]).length === 0
                        || root.operationActionKind(fields[2]) !== fields[3]
                        || !root.validOperationState(fields[4])
                        || !root.validPercent(fields[5])
                        || (fields[6] !== "yes" && fields[6] !== "no")
                        || (root.updateActionKind(fields[2]).length === 0
                            && (fields[6] !== "no" || fields[4] === "cancel-requested"))) {
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
        if (minor === 1) {
            for (const owner of nativeOwners) {
                if (parsedNativeProviders[owner] === undefined) nativeInvalid[owner] = true;
            }
            for (const identifier of nativeStateIds) {
                if (states["$" + identifier] === undefined) nativeInvalid[root.nativeStateOwner(identifier)] = true;
            }
            for (const identifier of nativeActionIds) {
                if (parsedActions["$" + identifier] === undefined) nativeInvalid[root.nativeActionOwner(identifier)] = true;
            }
            if (!nativeInvalid.accounts) {
                const count = states["$accounts-count"];
                if ((count.status === "available" && Number(count.value) !== nativeLists.account.length)
                        || (count.status !== "available" && count.status !== "partial" && nativeLists.account.length > 0)
                        || nativeLists.account.filter(item => item.scope === "current").length > 1) nativeInvalid.accounts = true;
            }
            if (!nativeInvalid.sources && nativeLists.repository.length > 0
                    && parsedNativeProviders.sources.status !== "available"
                    && parsedNativeProviders.sources.status !== "partial") nativeInvalid.sources = true;
        }
        const nativeAdmission = minor === 1 && nativeActionIds.some(identifier =>
            !nativeInvalid[root.nativeActionOwner(identifier)]
                && parsedActions["$" + identifier].availability === "available");
        const journalAdmitted = !recoveryInvalid && (parsedActive !== null || parsedHandoff !== null
            || parsedRecoveryProvider.status === "available" || nativeAdmission);
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
        root.activeOperation = parsedActive !== null && operationModel.wasAcknowledged(parsedActive.id)
            ? null : parsedActive;
        root.terminalHandoff = parsedHandoff !== null && operationModel.wasAcknowledged(parsedHandoff.id)
            ? null : parsedHandoff;
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
        const publishedProviders = {};
        const publishedStates = {};
        let nativeMalformed = false;
        if (minor === 1) {
            for (const owner of nativeOwners) {
                if (nativeInvalid[owner]) {
                    nativeMalformed = true;
                    const detail = "System management provider returned malformed " + owner + " state";
                    publishedProviders[owner] = { status: "partial", providerClass: "delegated", owner: "", detail: detail };
                    parsedErrors.push({ provider: owner, code: "malformed", detail: detail });
                } else publishedProviders[owner] = parsedNativeProviders[owner];
            }
            for (const identifier of nativeStateIds) {
                const owner = root.nativeStateOwner(identifier);
                publishedStates[identifier] = nativeInvalid[owner]
                    ? { status: "partial", value: "unknown", detail: publishedProviders[owner].detail }
                    : states["$" + identifier];
            }
            const nativeActions = [];
            for (const identifier of nativeActionIds) {
                if (journalAdmitted && !nativeInvalid[root.nativeActionOwner(identifier)])
                    nativeActions.push(parsedActions["$" + identifier]);
            }
            root.actions = root.actions.concat(nativeActions);
        }
        root.nativeProviders = publishedProviders;
        root.nativeStates = publishedStates;
        root.accounts = minor === 1 && !nativeInvalid.accounts ? nativeLists.account : [];
        root.repositories = minor === 1 && !nativeInvalid.sources ? nativeLists.repository : [];
        root.errors = parsedErrors;
        root.snapshotState = updatesInvalid || planInvalid || planUnsupported || recoveryInvalid || nativeMalformed
            ? "partial" : "ready";
        root.message = root.snapshotState === "ready"
            ? parsedUpdates.length + " updates reported"
            : "System management state is incomplete";
        // Valid native offers independently prove journal admission even when
        // update-specific recovery (for example logind) is unavailable.
        return journalAdmitted;
    }

    function openSettings() {
        root.settingsVisible = true;
        root.discoveryBatch = true;
        for (const model of root.discoveryModels()) model.open();
        root.refreshRecovery();
        root.discoveryBatch = false;
        root.requestSnapshot(root.requiredPending);
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.confirmationInvalidated();
        for (const model of root.discoveryModels()) model.close();
        root.snapshotPending = false;
        if (!root.snapshotRequired) {
            root.requestGeneration++;
            snapshotProcess.running = false;
        }
    }

    function refresh() {
        if (!root.settingsVisible) return;
        root.discoveryBatch = true;
        for (const model of root.discoveryModels()) model.refresh();
        root.refreshRecovery();
        root.discoveryBatch = false;
        root.requestSnapshot(root.requiredPending);
    }

    function refreshRecovery() {
        const requiredRecovery = operationModel.waitingSnapshot || operationModel.blocked
            || operationModel.state === "recovering";
        operationModel.resetRecovery();
        if (requiredRecovery) operationModel.requestSnapshot();
    }

    function requestSnapshot(required) {
        if (!required && !root.settingsVisible) return;
        if (regionalModel.ownsPreparation()) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || required;
            regionalModel.invalidate("");
            // Optional preflight cancellation must be reaped before recovery
            // or discovery can claim the shared snapshot owner.
            if (regionalModel.ownsPreparation()) return;
        }
        if (root.snapshotOwned || root.discoveryBatch) {
            root.snapshotPending = root.snapshotPending || !required;
            root.requiredPending = root.requiredPending || required;
            return;
        }
        required = required || root.requiredPending;
        const ready = root.discoveryReady();
        if (!required && (!ready || !root.discoveryModels().some(model => model.canTake()))) return;
        root.snapshotPending = false;
        root.requiredPending = false;
        // Claim the owner before any QML signal from discovery.take/publication.
        root.snapshotOwned = true;
        root.requestGeneration++;
        snapshotProcess.generation = root.requestGeneration;
        root.snapshotRequired = required;
        root.snapshotHasOutput = false;
        root.snapshotErrorDetail = "";
        snapshotProcess.cycleTokens = [];
        // Required recovery can bypass subscription setup, but cannot certify
        // optional freshness until every domain has a handshake or fallback.
        if (ready) {
            for (const model of root.discoveryModels()) {
                const token = model.take();
                if (token !== null) snapshotProcess.cycleTokens.push({ model: model, token: token });
                if (snapshotProcess.generation !== root.requestGeneration) break;
            }
        }
        root.confirmationInvalidated();
        if (snapshotProcess.generation !== root.requestGeneration) {
            root.finishSnapshot(-1, false);
            return;
        }
        root.snapshotState = "loading";
        root.message = "Reading system management status...";
        if (snapshotProcess.generation !== root.requestGeneration) {
            root.finishSnapshot(-1, false);
            return;
        }
        snapshotProcess.running = true;
    }

    function finishSnapshot(exitCode, normalExit) {
        if (!root.snapshotOwned) return;
        const current = snapshotProcess.generation === root.requestGeneration;
        const tokens = snapshotProcess.cycleTokens;
        for (const item of tokens) item.model.beforePublish(item.token);
        if (current) {
            if (normalExit && exitCode === 0 && root.snapshotHasOutput) {
                if (root.parseSnapshot(snapshotOutput.text, snapshotProcess.generation))
                    operationModel.acceptSnapshot(root.activeOperation, root.terminalHandoff);
                else operationModel.snapshotFailed();
            } else {
                root.clearState("System management snapshot process failed"
                    + (root.snapshotErrorDetail ? ": " + root.snapshotErrorDetail : ""));
                operationModel.snapshotFailed();
            }
        }
        // Reentrant invalidations during parse/acceptSnapshot still belong to
        // this completion handoff. Reserve the settling read before idle.
        for (const item of tokens) item.model.complete(item.token, current && root.snapshotState !== "failure");
        root.snapshotRequired = false;
        root.snapshotOwned = false;
        // The old process emits runningChanged after exited. Queue the next
        // launch so that signal cannot finalize a new run's ownership.
        Qt.callLater(function() {
            if (root.requiredPending) root.requestSnapshot(true);
            else if (root.snapshotPending && root.settingsVisible) root.requestSnapshot(false);
        });
    }

    Component.onCompleted: Qt.callLater(function() { operationModel.requestSnapshot(); })

    SystemUpdateDiscovery {
        id: discoveryModel
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: root.confirmationInvalidated()
    }

    SystemProviderDiscovery {
        id: timeDiscoveryModel
        domain: "time"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: regionalModel.invalidate("time")
    }
    SystemProviderDiscovery {
        id: localeDiscoveryModel
        domain: "locale"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: regionalModel.invalidate("locale")
    }
    SystemProviderDiscovery {
        id: accountDiscoveryModel
        domain: "accounts"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: root.invalidateNativeConfirmation("accounts")
    }
    SystemProviderDiscovery {
        id: printerDiscoveryModel
        domain: "printers"
        onSnapshotRequested: root.requestSnapshot(false)
        onInvalidated: root.invalidateNativeConfirmation("printers")
    }

    SystemRegionalSettingsModel {
        id: regionalModel
        model: root
        onReleased: Qt.callLater(function() {
            if (root.requiredPending) root.requestSnapshot(true);
            else if (root.snapshotPending && root.settingsVisible) root.requestSnapshot(false);
        })
    }

    SystemOperationModel {
        id: operationModel
        onDiscoveryInvalidated: actionId => root.invalidateActionDiscovery(actionId)
        onSnapshotRequested: root.requestSnapshot(true)
        onAcknowledged: operationId => {
            if (root.terminalHandoff !== null && root.terminalHandoff.id === operationId)
                root.terminalHandoff = null;
            if (root.activeOperation !== null && root.activeOperation.id === operationId)
                root.activeOperation = null;
        }
    }

    Process {
        id: snapshotProcess
        property int generation: 0
        property var cycleTokens: []
        command: Commands.terminatingCheckedCommand(
            Commands.systemManagementCommand("snapshot", []))
        running: false
        stdout: StdioCollector {
            id: snapshotOutput
            onStreamFinished: { if (root.snapshotOwned) root.snapshotHasOutput = true; }
        }
        stderr: StdioCollector {
            id: snapshotError
            onStreamFinished: {
                if (root.snapshotOwned) {
                    const rawError = text.replace(/\s+/g, " ").trim();
                    root.snapshotErrorDetail = root.utf8Bytes(rawError) <= 512 ? rawError
                        : "Provider error detail exceeded the protocol limit";
                }
            }
        }
        onExited: (exitCode, exitStatus) => root.finishSnapshot(exitCode, exitStatus === 0)
        onRunningChanged: {
            if (!running && root.snapshotOwned) root.finishSnapshot(-1, false);
        }
    }
}
