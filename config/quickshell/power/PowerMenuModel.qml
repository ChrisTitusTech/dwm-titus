import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property var powerModel: null
    property bool visible: false
    property bool confirming: false
    property var pendingAction: null
    property string confirmationOrigin: ""
    property string anchorSource: "panel"

    property bool busy: false
    property string activeActionId: ""
    property string actionOrigin: ""
    property string status: ""
    property bool actionSucceeded: false
    property string actionError: ""
    property int actionGeneration: 0
    property string rejectionOrigin: ""
    property string rejectionMessage: ""

    readonly property var sessionActions: [
        {
            "id": "reboot",
            "label": "Reboot",
            "detail": "Restart this system",
            "confirm": true,
            "available": true
        },
        {
            "id": "logout",
            "label": "Log Out",
            "detail": "End the current session",
            "confirm": true,
            "available": true
        },
        {
            "id": "lock",
            "label": "Lock",
            "detail": "Secure this session",
            "confirm": false,
            "available": true
        },
        {
            "id": "suspend",
            "label": "Suspend",
            "detail": root.powerModel
                && typeof root.powerModel.suspendDetail === "string"
                && root.powerModel.suspendDetail.length > 0
                ? root.powerModel.suspendDetail : "Suspend this system",
            "confirm": true,
            "available": root.powerModel !== null && root.powerModel.suspendState === "available"
        },
        {
            "id": "shutdown",
            "label": "Shutdown",
            "detail": "Power off this system",
            "confirm": true,
            "available": true
        }
    ]

    function actionForId(actionId) {
        for (let index = 0; index < root.sessionActions.length; index++) {
            if (root.sessionActions[index].id === actionId) return root.sessionActions[index];
        }
        return null;
    }

    function canonicalAction(action) {
        if (typeof action === "string") return root.actionForId(action);
        if (action && typeof action.id === "string") return root.actionForId(action.id);
        return null;
    }

    function originOrDefault(origin) {
        return origin || root.anchorSource || "panel";
    }

    function rejectOverlap(origin) {
        root.rejectionOrigin = root.originOrDefault(origin);
        root.rejectionMessage = "Another session action is already in progress";
    }

    function clearOverlapRejection() {
        if (root.rejectionMessage !== "Another session action is already in progress") return;
        root.rejectionOrigin = "";
        root.rejectionMessage = "";
    }

    function clearRejectionFor(origin) {
        const source = root.originOrDefault(origin);
        if (root.rejectionOrigin !== source) return;
        root.rejectionOrigin = "";
        root.rejectionMessage = "";
    }

    function messageFor(origin) {
        const source = root.originOrDefault(origin);
        if (root.rejectionOrigin === source && root.rejectionMessage.length > 0)
            return root.rejectionMessage;
        return root.actionOrigin === source ? root.status : "";
    }

    function busyFor(origin) {
        return root.busy && root.actionOrigin === root.originOrDefault(origin);
    }

    function messageSeverityFor(origin) {
        const source = root.originOrDefault(origin);
        if (root.rejectionOrigin === source && root.rejectionMessage.length > 0)
            return "warning";
        if (root.busyFor(source)) return "warning";
        if (root.actionOrigin === source && root.status.length > 0 && root.actionSucceeded)
            return "success";
        return "danger";
    }

    function open(source) {
        const requestedOrigin = source || "panel";
        if (root.confirming && root.confirmationOrigin !== requestedOrigin) {
            root.rejectOverlap(requestedOrigin);
            return;
        }
        root.anchorSource = requestedOrigin;
        root.visible = true;
        if (root.powerModel) root.powerModel.openSessionMenu();
        if (!root.busy) {
            root.confirming = false;
            root.pendingAction = null;
            root.confirmationOrigin = "";
        }
    }

    function close(origin) {
        const source = root.originOrDefault(origin);
        const canceledConfirmation = !root.busy && root.confirmationOrigin === source;
        root.visible = false;
        if (root.powerModel) root.powerModel.closeSessionMenu();
        if (canceledConfirmation) {
            root.confirming = false;
            root.pendingAction = null;
            root.confirmationOrigin = "";
            root.clearOverlapRejection();
        }
        root.clearRejectionFor(source);
    }

    function toggle(source) {
        if (root.visible) {
            root.close(source);
        } else {
            root.open(source);
        }
    }

    function requestAction(action, origin) {
        const requestedAction = root.canonicalAction(action);
        const source = root.originOrDefault(origin);
        if (!requestedAction) return;
        if (root.confirming && root.confirmationOrigin !== source) {
            root.rejectOverlap(source);
            return;
        }
        if (root.busy || actionProcess.running) {
            root.rejectOverlap(source);
            return;
        }
        if (!requestedAction.available) {
            root.rejectionOrigin = source;
            root.rejectionMessage = requestedAction.id === "suspend" && root.powerModel
                    && typeof root.powerModel.suspendDetail === "string"
                    && root.powerModel.suspendDetail.length > 0
                ? root.powerModel.suspendDetail
                : requestedAction.label + " is unavailable on this system";
            return;
        }

        if (root.rejectionOrigin === source) {
            root.rejectionOrigin = "";
            root.rejectionMessage = "";
        }
        if (requestedAction.confirm) {
            root.pendingAction = requestedAction;
            root.confirmationOrigin = source;
            root.confirming = true;
            return;
        }

        root.runAction(requestedAction, source);
    }

    function cancelConfirmation(origin) {
        if (root.busy) return;
        const source = root.originOrDefault(origin);
        if (root.confirmationOrigin.length > 0 && root.confirmationOrigin !== source) return;
        root.confirming = false;
        root.pendingAction = null;
        root.confirmationOrigin = "";
        root.clearOverlapRejection();
        root.clearRejectionFor(source);
    }

    function confirmAction(origin) {
        const source = root.originOrDefault(origin);
        if (root.busy || actionProcess.running) {
            root.rejectOverlap(source);
            return;
        }
        if (!root.pendingAction || root.confirmationOrigin !== source) return;
        root.runAction(root.pendingAction, source);
    }

    function runAction(action, origin) {
        const requestedAction = root.canonicalAction(action);
        const source = root.originOrDefault(origin);
        if (!requestedAction) return;
        if (root.busy || actionProcess.running) {
            root.rejectOverlap(source);
            return;
        }

        root.actionGeneration++;
        root.activeActionId = requestedAction.id;
        root.actionOrigin = source;
        root.status = "Requesting " + requestedAction.label.toLowerCase() + "...";
        root.actionSucceeded = false;
        root.actionError = "";
        root.confirming = false;
        root.pendingAction = null;
        root.confirmationOrigin = "";
        root.busy = true;

        actionProcess.generation = root.actionGeneration;
        actionProcess.expectedResult = "session-action\t" + requestedAction.id + "\taccepted";
        actionProcess.command = Commands.checkedCommand(
            Commands.sessionActionCommand(requestedAction.id));
        actionProcess.running = true;
    }

    Process {
        id: actionProcess

        property int generation: 0
        property string expectedResult: ""

        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (actionProcess.generation !== root.actionGeneration) return;
                root.actionSucceeded = this.text.trim() === actionProcess.expectedResult;
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (actionProcess.generation !== root.actionGeneration) return;
                root.actionError = this.text.trim();
            }
        }
        onRunningChanged: {
            if (running || generation !== root.actionGeneration) return;
            root.busy = false;
            if (root.actionSucceeded) {
                root.status = "Session action accepted";
                if (root.visible && root.anchorSource === root.actionOrigin) root.close(root.actionOrigin);
            } else {
                root.status = root.actionError.length > 0
                    ? root.actionError : "Session helper did not confirm the requested action";
            }
            root.activeActionId = "";
            root.clearOverlapRejection();
        }
    }
}
