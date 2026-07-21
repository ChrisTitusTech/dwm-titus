import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool confirming: false
    property var pendingAction: null
    property string status: ""
    property string anchorSource: "panel"

    readonly property var sessionActions: [
        {
            "id": "reboot",
            "label": "Reboot",
            "detail": "Restart this system",
            "command": ["systemctl", "reboot"],
            "confirm": true
        },
        {
            "id": "logout",
            "label": "Log Out",
            "detail": "End the current session",
            "command": ["sh", "-c", "if [ -n \"${XDG_SESSION_ID:-}\" ]; then exec loginctl terminate-session \"$XDG_SESSION_ID\"; fi; exec pkill -TERM -x dwm"],
            "confirm": true
        },
        {
            "id": "lock",
            "label": "Lock",
            "detail": "Secure this session",
            "command": Commands.lockHelperCommand(),
            "confirm": false
        },
        {
            "id": "shutdown",
            "label": "Shutdown",
            "detail": "Power off this system",
            "command": ["systemctl", "poweroff"],
            "confirm": true
        }
    ]

    function open(source) {
        root.anchorSource = source || "panel";
        root.visible = true;
        root.confirming = false;
        root.pendingAction = null;
        root.status = "";
    }

    function close() {
        root.visible = false;
        root.confirming = false;
        root.pendingAction = null;
        root.status = "";
    }

    function toggle(source) {
        if (root.visible) {
            root.close();
        } else {
            root.open(source);
        }
    }

    function requestAction(action) {
        if (!action) {
            return;
        }

        if (action.confirm) {
            root.pendingAction = action;
            root.confirming = true;
            root.status = "";
            return;
        }

        root.runAction(action);
    }

    function cancelConfirmation() {
        root.confirming = false;
        root.pendingAction = null;
        root.status = "";
    }

    function confirmAction() {
        if (!root.pendingAction) {
            root.cancelConfirmation();
            return;
        }

        root.runAction(root.pendingAction);
    }

    function runAction(action) {
        if (!action || !action.command || action.command.length === 0) {
            return;
        }

        actionProcess.command = action.command;
        actionProcess.running = true;
        root.close();
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false
    }
}
