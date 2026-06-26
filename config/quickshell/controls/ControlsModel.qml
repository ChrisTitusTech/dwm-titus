import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property string volumeText: "VOL unavailable"

    function open() {
        root.visible = true;
        root.refresh();
    }

    function close() {
        root.visible = false;
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
}
