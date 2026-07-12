import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
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
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource

    function refreshAudioStatus() {
        const sink = root.audioSink;

        if (sink !== null && sink.ready && sink.audio !== null) {
            root.volumePercent = root.clampPercent(sink.audio.volume * 100);
            root.volumeMuted = sink.audio.muted;
            root.volumeText = (root.volumeMuted ? "VOL muted " : "VOL ") + root.volumePercent.toString() + "%";
            root.outputDeviceName = sink.name;
            root.outputDeviceDescription = sink.description.length > 0 ? sink.description : sink.name;
        } else {
            root.volumeText = "VOL unavailable";
            root.volumeMuted = false;
            root.outputDeviceName = "";
            root.outputDeviceDescription = "";
            if (!volumeStatusProcess.running) {
                volumeStatusProcess.running = true;
            }
        }

        const source = root.audioSource;
        if (source !== null && source.ready && source.audio !== null) {
            root.micText = source.audio.muted ? "MIC muted" : "MIC on";
        } else {
            root.micText = "MIC unavailable";
            if (!micStatusProcess.running) {
                micStatusProcess.running = true;
            }
        }
    }

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
        root.refreshAudioStatus();
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

    PwObjectTracker {
        objects: [root.audioSink, root.audioSource]
    }

    Connections {
        target: Pipewire

        function onDefaultAudioSinkChanged() {
            root.refreshAudioStatus();
            root.refreshOutputDevices();
        }

        function onDefaultAudioSourceChanged() {
            root.refreshAudioStatus();
        }

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: Pipewire.nodes

        function onObjectInsertedPost(object, index) {
            if (root.visible) {
                root.refreshOutputDevices();
            }
        }

        function onObjectRemovedPost(object, index) {
            if (root.visible) {
                root.refreshOutputDevices();
            }
        }
    }

    Connections {
        target: root.audioSink

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSink !== null ? root.audioSink.audio : null

        function onMutedChanged() {
            root.refreshAudioStatus();
        }

        function onVolumesChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSource

        function onReadyChanged() {
            root.refreshAudioStatus();
        }
    }

    Connections {
        target: root.audioSource !== null ? root.audioSource.audio : null

        function onMutedChanged() {
            root.refreshAudioStatus();
        }
    }

    Process {
        id: volumeStatusProcess

        command: Commands.controlsHelperCommand("volume-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const sink = root.audioSink;
                if (sink === null || !sink.ready || sink.audio === null) {
                    root.parseVolume(this.text.length > 0 ? this.text : "VOL unavailable");
                }
            }
        }
    }

    Process {
        id: micStatusProcess

        command: Commands.controlsHelperCommand("mic-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const source = root.audioSource;
                if (source === null || !source.ready || source.audio === null) {
                    const text = this.text.trim();
                    root.micText = text.length > 0 ? text : "MIC unavailable";
                }
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

    Component.onCompleted: root.refreshAudioStatus()
}
