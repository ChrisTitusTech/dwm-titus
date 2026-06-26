import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string volumeText: "VOL unavailable"
    property string micText: "MIC unavailable"
    property string message: ""

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
        root.message = "";
    }

    function toggle() {
        if (root.visible) {
            root.close();
        } else {
            root.open();
        }
    }

    function refresh() {
        if (!volumeStatusProcess.running) {
            volumeStatusProcess.running = true;
        }
        if (!micStatusProcess.running) {
            micStatusProcess.running = true;
        }
    }

    function runAction(action, args) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.message = "";
        actionProcess.command = Commands.controlsHelperCommand(action, args || []);
        actionProcess.running = true;
    }

    function volumeUp() {
        root.runAction("volume-up", ["5%"]);
    }

    function volumeDown() {
        root.runAction("volume-down", ["5%"]);
    }

    function volumeToggleMute() {
        root.runAction("volume-toggle-mute");
    }

    Process {
        id: volumeStatusProcess

        command: Commands.controlsHelperCommand("volume-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();

                root.volumeText = text.length > 0 ? text : "VOL unavailable";
            }
        }
    }

    Process {
        id: micStatusProcess

        command: Commands.controlsHelperCommand("mic-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();

                root.micText = text.length > 0 ? text : "MIC unavailable";
            }
        }
    }

    Process {
        id: actionProcess

        command: ["sh", "-c", "exit 0"]
        running: false

        onRunningChanged: {
            if (!running) {
                root.busy = false;
                root.refresh();
            }
        }
    }
}
