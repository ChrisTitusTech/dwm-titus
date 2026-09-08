import QtQuick
import Quickshell

// Settings-only preparation. The root operation model owns every sent change.
Scope {
    id: root
    required property var model
    property var request: null
    property var confirmation: null
    property var catalogs: ({})
    property string message: ""
    readonly property alias preflight: reader
    signal released()

    function discovery(action) {
        if (action === "timezone-set" || action === "ntp-set") return model.timeDiscovery;
        if (action === "locale-set") return model.localeDiscovery;
        return null;
    }

    function ownsPreparation() { return request !== null || reader.current !== null; }

    function awaitingTimeReconciliation() {
        return request !== null && reader.current === null && request.outcome !== null
            && discovery(request.action) === model.timeDiscovery && matches(request);
    }

    function retryTimePublication() {
        if (model.timeReconciliation.failure.length > 0 || model.timeReconciliation.unresolved) {
            invalidate("time");
            return;
        }
        if (awaitingTimeReconciliation() && !model.timeReconciliation.blocksAdmission()) publish(request);
    }

    function timePreviewMatches(preview, observed) {
        if (preview.actionId === "timezone-set") return preview.current === observed.timezone;
        if (preview.actionId === "ntp-set") return observed.canNtp
            && preview.current === (observed.ntpEnabled ? "enabled" : "disabled");
        return true;
    }

    function reconcileTimePreview(observed) {
        if (confirmation !== null && !timePreviewMatches(confirmation.preview, observed)) {
            confirmation = null;
            message = "Time no longer matches this preview. Review a fresh preview and confirm again.";
        }
        const pending = request;
        if (pending !== null && pending.command === "regional-preview" && pending.outcome !== null
                && pending.outcome.status === "available" && !timePreviewMatches(pending.outcome.preview, observed)) {
            request = null;
            message = "Time no longer matches this preview. Retry the read explicitly.";
            released();
        }
    }

    function contextReason(action, requireOffer) {
        const monitor = discovery(action);
        if (monitor === null) return "This regional action is not supported.";
        if (!model.settingsVisible) return "Open System Settings to prepare this action.";
        if (model.snapshotOwned || model.snapshotPending || model.requiredPending || model.discoveryBatch
                || model.timeReconciliation.ownsRead()
                || (monitor === model.timeDiscovery && model.timeReconciliation.blocksAdmission())
                || !monitor.fresh
                || !monitor.visible || !monitor.ready || monitor.failed || !monitor.cycle.enabled
                || monitor.cycle.phase !== "idle" || monitor.cycle.unresolved)
            return "Wait for fresh regional status, or reload status to retry.";
        if (!model.validGeneration(model.generation) || !model.operation.canStart)
            return "An operation or its recovery still owns the system workflow.";
        if (requireOffer) {
            const offer = model.actions.find(item => item.id === action);
            if (!offer || offer.availability !== "available")
                return offer && offer.detail.length > 0 ? offer.detail : "The provider did not offer this action.";
        }
        return "";
    }

    function actionReason(action) {
        if (ownsPreparation() || model.dispatchingUpdate || model.dispatchingNative
                || model.updateConfirmation !== null || model.nativeConfirmation !== null)
            return "Finish or dismiss the current preparation first.";
        return contextReason(action, true);
    }

    function identity(action) {
        return { action: action, generation: model.generation, requestGeneration: model.requestGeneration,
            epoch: discovery(action).cycle.epoch };
    }

    function matches(ticket) {
        const monitor = discovery(ticket.action);
        return monitor !== null && ticket.generation === model.generation
            && ticket.requestGeneration === model.requestGeneration && ticket.epoch === monitor.cycle.epoch;
    }

    function choices(kind) {
        const catalog = catalogs[kind];
        return catalog && matches(catalog.ticket) ? catalog.values : [];
    }

    function requestChoices(kind) {
        const action = kind === "timezone" ? "timezone-set" : kind === "locale" ? "locale-set" : "";
        return start("regional-choices", action, kind, "");
    }

    function prepare(action, argument) {
        if (reader.argumentsFor("regional-preview", action, argument) === null) return false;
        if ((action === "timezone-set" && choices("timezone").indexOf(argument) < 0)
                || (action === "locale-set" && choices("locale").indexOf(argument.slice(5)) < 0)) {
            message = "Load fresh choices and select an exact reported value.";
            return false;
        }
        return start("regional-preview", action, action, argument);
    }

    function start(command, action, selection, argument) {
        if (ownsPreparation() || confirmation !== null || model.dispatchingUpdate || model.dispatchingNative
                || model.updateConfirmation !== null || model.nativeConfirmation !== null) return false;
        const reason = contextReason(action, command === "regional-preview");
        if (reason !== "") { message = reason; return false; }
        const ticket = Object.assign(identity(action), { command: command, selection: selection,
            argument: argument, readerId: reader.serial + 1, outcome: null });
        // Claim before message/result publication can invoke a competing read.
        request = ticket;
        message = "";
        if (request !== ticket || !matches(ticket) || contextReason(action, command === "regional-preview") !== "") {
            if (request === ticket) invalidate("");
            return false;
        }
        const started = reader.start(command, selection, argument);
        if (!started && request === ticket) {
            request = null;
            message = "The regional read could not start. Retry explicitly.";
            released();
        }
        return started && request === ticket;
    }

    function publish(ticket) {
        if (request !== ticket || reader.current !== null || ticket.outcome === null) return;
        if (matches(ticket) && discovery(ticket.action) === model.timeDiscovery
                && model.timeReconciliation.blocksAdmission()
                && model.timeReconciliation.failure.length === 0 && !model.timeReconciliation.unresolved) {
            // The finite reader is reaped, but the request identity remains
            // reserved while a scoped read reconciles an owner arrival.
            model.timeReconciliation.requestPending();
            return;
        }
        try {
            if (!matches(ticket) || contextReason(ticket.action, ticket.command === "regional-preview") !== "") {
                invalidate("");
                return;
            }
            const outcome = ticket.outcome;
            if (outcome.status !== "available") {
                message = outcome.error.code + ": " + outcome.error.detail;
            } else if (ticket.command === "regional-choices") {
                const next = Object.assign({}, catalogs);
                next[ticket.selection] = { ticket: ticket, values: outcome.choices.slice() };
                catalogs = next;
            } else {
                // Keep the request owner through prompt publication. A callback
                // cannot confirm until the verified reader handoff is complete.
                confirmation = { ticket: ticket, preview: Object.assign({}, outcome.preview) };
            }
        } finally {
            if (request === ticket) request = null;
            released();
        }
    }

    function invalidate(domain) {
        const pending = request;
        if (domain === "" || (pending !== null && discovery(pending.action).domain === domain)) {
            request = null;
            reader.cancel();
        }
        if (confirmation !== null && (domain === "" || discovery(confirmation.ticket.action).domain === domain)) {
            confirmation = null;
            message = "Regional state changed. Review a fresh preview and confirm again.";
        } else if (pending !== null && request !== pending)
            message = "Regional state changed. Retry the read explicitly.";
        const next = Object.assign({}, catalogs);
        if (domain === "" || domain === "time") delete next.timezone;
        if (domain === "" || domain === "locale") delete next.locale;
        catalogs = next;
        if (!ownsPreparation()) released();
    }

    function discard() {
        invalidate("");
        message = "";
    }

    function confirm() {
        const pending = confirmation;
        if (pending === null || ownsPreparation() || model.dispatchingUpdate || model.dispatchingNative) return false;
        if (model.timeReconciliation.sampleClaim.ticket !== null || model.timeReconciliation.sampling) return false;
        if (matches(pending.ticket) && discovery(pending.ticket.action) === model.timeDiscovery
                && model.timeReconciliation.blocksAdmission()) return false;
        if (actionReason(pending.ticket.action) !== "" || !matches(pending.ticket)) {
            invalidate("");
            return false;
        }
        model.dispatchingNative = true;
        confirmation = null;
        // UI callbacks may close Settings or retire discovery while dismissing.
        const current = matches(pending.ticket) && contextReason(pending.ticket.action, true) === ""
            && model.updateConfirmation === null && model.nativeConfirmation === null && !ownsPreparation();
        const started = current && model.operation.startNative(pending.ticket.action,
            pending.ticket.argument, pending.preview.generation);
        message = started ? "" : "Regional state changed. Review a fresh preview and confirm again.";
        model.dispatchingNative = false;
        return started;
    }

    SystemRegionalPreflightModel {
        id: reader
        active: root.model.settingsVisible
        onCompleted: outcome => {
            const ticket = root.request;
            if (ticket === null || ticket.readerId !== outcome.id) return;
            ticket.outcome = outcome;
            Qt.callLater(function() { root.publish(ticket); });
        }
        onCurrentChanged: {
            if (current === null) Qt.callLater(function() { if (!root.ownsPreparation()) root.released(); });
        }
    }
}
