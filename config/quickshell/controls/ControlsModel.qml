import Quickshell
import Quickshell.Io
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool busy: false
    property string volumeText: "VOL unavailable"
    property int volumePercent: 0
    property bool volumeMuted: false
    property string volumeDisplayText: volumeText + (outputDeviceDescription.length > 0 ? " - " + outputDeviceDescription : "")
    property var outputDevices: []
    property string outputDeviceName: ""
    property string outputDeviceDescription: ""
    property string micText: "MIC unavailable"
    property string mediaText: "MEDIA none"
    property string mediaPlayer: ""
    property string mediaState: ""
    property string mediaArtist: ""
    property string mediaTitle: ""
    property string bluetoothText: "BT unavailable"
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
        root.refreshOutputDevices();
        if (!mediaStatusProcess.running) {
            mediaStatusProcess.running = true;
        }
        if (!bluetoothStatusProcess.running) {
            bluetoothStatusProcess.running = true;
        }
    }

    function refreshOutputDevices() {
        if (!outputDevicesProcess.running) {
            outputDevicesProcess.running = true;
        }
    }

    function parseMedia(text) {
        const trimmed = text.trim();

        if (trimmed.length === 0 || trimmed.indexOf("MEDIA ") === 0) {
            root.mediaText = trimmed.length > 0 ? trimmed : "MEDIA none";
            root.mediaPlayer = "";
            root.mediaState = "";
            root.mediaArtist = "";
            root.mediaTitle = "";
            return;
        }

        const fields = trimmed.split("\t");

        root.mediaPlayer = fields.length > 0 ? fields[0] : "";
        root.mediaState = fields.length > 1 ? fields[1] : "";
        root.mediaArtist = fields.length > 2 ? fields[2] : "";
        root.mediaTitle = fields.length > 3 ? fields.slice(3).join("\t") : "";

        const labelParts = [];
        if (root.mediaPlayer.length > 0) {
            labelParts.push(root.mediaPlayer);
        }
        if (root.mediaState.length > 0) {
            labelParts.push(root.mediaState);
        }

        const titleParts = [];
        if (root.mediaArtist.length > 0) {
            titleParts.push(root.mediaArtist);
        }
        if (root.mediaTitle.length > 0) {
            titleParts.push(root.mediaTitle);
        }

        root.mediaText = (labelParts.length > 0 ? labelParts.join(" ") : "MEDIA") + (titleParts.length > 0 ? ": " + titleParts.join(" - ") : "");
    }

    function parseVolume(text) {
        const trimmed = text.trim();

        if (trimmed.length > 0) {
            root.volumeText = trimmed;
        }

        const match = trimmed.match(/([0-9]+)%/);
        if (match !== null) {
            root.volumePercent = root.clampPercent(parseInt(match[1], 10));
        }
        root.volumeMuted = trimmed.indexOf("VOL muted") === 0;
    }

    function parseOutputDevices(text) {
        const devices = [];
        const lines = text.trim().split("\n");
        let defaultName = "";
        let defaultDescription = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();

            if (line.length === 0 || line === "OUTPUT unavailable") {
                continue;
            }

            const fields = line.split("\t");
            const name = fields.length > 0 ? fields[0] : "";

            if (name.length === 0) {
                continue;
            }

            const description = fields.length > 1 && fields[1].length > 0 ? fields[1] : name;
            const isDefault = fields.length > 2 && fields[2] === "1";

            devices.push({ "name": name, "description": description, "isDefault": isDefault });
            if (isDefault) {
                defaultName = name;
                defaultDescription = description;
            }
        }

        root.outputDevices = devices;
        root.outputDeviceName = defaultName;
        root.outputDeviceDescription = defaultDescription;
    }

    function clampPercent(value) {
        const number = Math.round(Number(value));

        if (isNaN(number)) {
            return root.volumePercent;
        }

        return Math.max(0, Math.min(100, number));
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

    function volumeSet(percent) {
        root.runAction("volume-set", [root.clampPercent(percent).toString() + "%"]);
    }

    function outputSetDefault(name) {
        if (name.length === 0 || name === root.outputDeviceName) {
            return;
        }

        root.runAction("output-set-default", [name]);
    }

    function mediaPlayPause() {
        root.runAction("media-play-pause");
    }

    function mediaNext() {
        root.runAction("media-next");
    }

    function mediaPrevious() {
        root.runAction("media-previous");
    }

    Process {
        id: volumeStatusProcess

        command: Commands.controlsHelperCommand("volume-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseVolume(this.text.length > 0 ? this.text : "VOL unavailable")
        }
    }

    Process {
        command: Commands.controlsHelperCommand("volume-watch")
        running: true

        stdout: SplitParser {
            onRead: function(data) {
                root.parseVolume(data);
                root.refreshOutputDevices();
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
        id: outputDevicesProcess

        command: Commands.controlsHelperCommand("output-devices")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseOutputDevices(this.text)
        }
    }

    Process {
        id: mediaStatusProcess

        command: Commands.controlsHelperCommand("media-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseMedia(this.text)
        }
    }

    Process {
        command: Commands.controlsHelperCommand("media-watch")
        running: true

        stdout: SplitParser {
            onRead: function(data) {
                root.parseMedia(data);
            }
        }
    }

    Process {
        id: bluetoothStatusProcess

        command: Commands.controlsHelperCommand("bluetooth-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const text = this.text.trim();

                root.bluetoothText = text.length > 0 ? text : "BT unavailable";
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
