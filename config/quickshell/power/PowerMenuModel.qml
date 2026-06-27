import Quickshell
import Quickshell.Io

Scope {
    id: root

    property bool visible: false
    property bool confirming: false
    property var pendingAction: null
    property string status: ""

    readonly property var sessionActions: [
        {
            "id": "lock",
            "label": "Lock",
            "detail": "Secure this session",
            "command": ["sh", "-c", "loginctl lock-session ${XDG_SESSION_ID:-} 2>/dev/null || dwm-lock 2>/dev/null || light-locker-command -l"],
            "confirm": false
        },
        {
            "id": "logout",
            "label": "Logout",
            "detail": "End the current session",
            "command": ["sh", "-c", "if [ -n \"${XDG_SESSION_ID:-}\" ]; then exec loginctl terminate-session \"$XDG_SESSION_ID\"; fi; exec pkill -TERM -x dwm"],
            "confirm": true
        },
        {
            "id": "reboot",
            "label": "Reboot",
            "detail": "Restart this system",
            "command": ["systemctl", "reboot"],
            "confirm": true
        },
        {
            "id": "shutdown",
            "label": "Shutdown",
            "detail": "Power off this system",
            "command": ["systemctl", "poweroff"],
            "confirm": true
        }
    ]

    readonly property var quickActions: [
        {
            "id": "screenshot",
            "label": "Screenshot",
            "detail": "Capture an area",
            "command": ["dwm-screenshot", "gui"],
            "confirm": false
        },
        {
            "id": "files",
            "label": "Files",
            "detail": "Open the home directory",
            "command": ["sh", "-c", "exec xdg-open \"$HOME\""],
            "confirm": false
        },
        {
            "id": "terminal",
            "label": "Terminal",
            "detail": "Open a terminal",
            "command": ["dwm-terminal"],
            "confirm": false
        },
        {
            "id": "browser",
            "label": "Browser",
            "detail": "Open the default browser",
            "command": ["dwm-default-apps", "open", "https://"],
            "confirm": false
        },
        {
            "id": "settings",
            "label": "Settings",
            "detail": "Open the control center",
            "command": ["sh", "-c", "exec quickshell ipc --path \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml\" call controlcenter toggle"],
            "confirm": false
        }
    ]

    function open() {
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

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
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
