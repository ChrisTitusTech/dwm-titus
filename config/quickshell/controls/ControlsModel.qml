import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.core

Scope {
    id: root

    property bool visible: false
    property bool settingsVisible: false
    property bool busy: false
    property string volumeText: "VOL unavailable"
    property int volumePercent: 0
    property bool volumeMuted: false
    property string volumeIconState: root.volumeIconStateFor(root.volumePercent, root.volumeMuted)
    property string volumeDisplayText: volumeText + (outputDeviceDescription.length > 0 ? " - " + outputDeviceDescription : "")
    property var outputDevices: []
    property var inputDevices: []
    property var audioStreams: []
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
    property string audioProviderState: "idle"
    property string audioProviderDetail: ""
    property string audioSourceKind: "none"
    property int audioSourceGeneration: 0
    property int fallbackProcessGeneration: 0
    property int mutationGeneration: 0
    property int appliedMutationGeneration: 0
    property int actionProcessGeneration: 0
    property string mutationOrigin: ""
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var audioSource: Pipewire.defaultAudioSource

    function nativeAudioReady() {
        return root.audioSink !== null && root.audioSink.ready && root.audioSink.audio !== null;
    }

    function selectAudioSource() {
        if (root.nativeAudioReady()) {
            nativeGraceTimer.stop();
            if (fallbackWatchProcess.running) fallbackWatchProcess.running = false;
            if (root.audioSourceKind !== "native") {
                root.audioSourceGeneration++;
                root.audioSourceKind = "native";
            }
        } else if ((root.visible || root.settingsVisible) && !nativeGraceTimer.running
                && root.audioSourceKind !== "fallback") {
            nativeGraceTimer.restart();
        }
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refresh();
        root.selectAudioSource();
    }

    function closeSettings() {
        root.settingsVisible = false;
        if (!root.visible && fallbackWatchProcess.running) fallbackWatchProcess.running = false;
        if (!root.visible) nativeGraceTimer.stop();
    }

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
        root.selectAudioSource();

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
        root.selectAudioSource();
    }

    function close() {
        root.visible = false;
        root.message = "";
        if (!root.settingsVisible && fallbackWatchProcess.running) fallbackWatchProcess.running = false;
        if (!root.settingsVisible) nativeGraceTimer.stop();
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
        root.refreshAudioInventory();
        if (!mediaStatusProcess.running) {
            mediaStatusProcess.running = true;
        }
        if (!bluetoothStatusProcess.running) {
            bluetoothStatusProcess.running = true;
        }
    }

    function refreshAudioInventory() {
        if (!audioSnapshotProcess.running) audioSnapshotProcess.running = true;
    }

    function parseAudioSnapshot(text) {
        const outputs = [];
        const inputs = [];
        const streams = [];
        let protocolValid = false;
        let providerSeen = false;
        let malformed = false;
        let defaultOutput = null;
        let defaultInput = null;
        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "audio-protocol") {
                protocolValid = fields.length >= 3 && fields[1] === "1";
            } else if (fields[0] === "provider") {
                if (fields.length < 5 || fields[1] !== "audio") { malformed = true; continue; }
                providerSeen = true;
                root.audioProviderState = fields[2];
                root.audioProviderDetail = fields[4];
            } else if (fields[0] === "audio-output" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[3] !== "yes" && fields[3] !== "no")
                        || (fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                const item = { "name": fields[1], "description": fields[2], "isDefault": fields[3] === "yes",
                    "muted": fields[4] === "yes", "volume": Math.round(percent) };
                outputs.push(item);
                if (item.isDefault) defaultOutput = item;
            } else if (fields[0] === "audio-input" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[3] !== "yes" && fields[3] !== "no")
                        || (fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                const item = { "name": fields[1], "description": fields[2], "isDefault": fields[3] === "yes",
                    "muted": fields[4] === "yes", "volume": Math.round(percent) };
                inputs.push(item);
                if (item.isDefault) defaultInput = item;
            } else if (fields[0] === "audio-stream" && fields.length >= 6) {
                const percent = Number(fields[5]);
                if ((fields[4] !== "yes" && fields[4] !== "no")
                        || !isFinite(percent) || percent < 0 || percent > 100) {
                    malformed = true;
                    continue;
                }
                streams.push({ "index": fields[1], "application": fields[2], "description": fields[3],
                    "muted": fields[4] === "yes", "volume": Math.round(percent) });
            }
        }
        if (!protocolValid || !providerSeen || malformed) {
            root.outputDevices = [];
            root.inputDevices = [];
            root.audioStreams = [];
            root.audioProviderState = "failure";
            root.audioProviderDetail = !protocolValid ? "Unsupported audio protocol" : "Malformed audio provider record";
            return;
        }
        root.outputDevices = outputs;
        root.inputDevices = inputs;
        root.audioStreams = streams;
        if (defaultOutput !== null && root.audioSourceKind === "fallback") {
            root.volumePercent = defaultOutput.volume;
            root.volumeMuted = defaultOutput.muted;
            root.volumeText = (defaultOutput.muted ? "VOL muted " : "VOL ") + defaultOutput.volume + "%";
            root.outputDeviceName = defaultOutput.name;
            root.outputDeviceDescription = defaultOutput.description;
        }
        if (defaultInput !== null && root.audioSourceKind === "fallback") {
            root.micText = defaultInput.muted ? "MIC muted" : "MIC on";
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

    function runAction(action, args, origin) {
        if (root.busy) {
            return;
        }

        root.busy = true;
        root.mutationGeneration++;
        root.actionProcessGeneration = root.mutationGeneration;
        root.mutationOrigin = origin || "panel";
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

    function outputSetDefault(name, origin) {
        if (name.length === 0 || name === root.outputDeviceName) {
            return;
        }

        root.runAction("output-set-default", [name], origin);
    }

    function inputSetDefault(name, origin) { root.runAction("input-set-default", [name], origin); }
    function inputVolumeSet(name, percent, origin) {
        root.runAction("input-volume-set", [name, root.clampPercent(percent).toString() + "%"], origin);
    }
    function inputToggleMute(name, origin) { root.runAction("input-toggle-mute", [name], origin); }
    function streamVolumeSet(index, percent, origin) {
        root.runAction("stream-volume-set", [index, root.clampPercent(percent).toString() + "%"], origin);
    }
    function streamToggleMute(index, origin) { root.runAction("stream-toggle-mute", [index], origin); }

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
            root.refreshAudioInventory();
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
            if (root.visible || root.settingsVisible) {
                root.refreshAudioInventory();
            }
        }

        function onObjectRemovedPost(object, index) {
            if (root.visible || root.settingsVisible) {
                root.refreshAudioInventory();
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

    Timer {
        id: nativeGraceTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!root.nativeAudioReady() && (root.visible || root.settingsVisible)) {
                root.audioSourceGeneration++;
                root.audioSourceKind = "fallback";
                root.fallbackProcessGeneration = root.audioSourceGeneration;
                root.refreshAudioInventory();
                fallbackWatchProcess.running = true;
            }
        }
    }

    Process {
        id: audioSnapshotProcess
        command: Commands.controlsHelperCommand("audio-snapshot")
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseAudioSnapshot(this.text) }
    }

    Process {
        id: fallbackWatchProcess
        command: Commands.controlsHelperCommand("audio-watch")
        running: false
        stdout: SplitParser {
            onRead: function(data) {
                if (root.audioSourceKind === "fallback"
                        && root.fallbackProcessGeneration === root.audioSourceGeneration) {
                    root.refreshAudioInventory();
                }
            }
        }
        onRunningChanged: {
            if (!running && root.audioSourceKind === "fallback"
                    && (root.visible || root.settingsVisible)) fallbackRestartTimer.restart();
        }
    }

    Timer {
        id: fallbackRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.audioSourceKind === "fallback" && !fallbackWatchProcess.running
                    && (root.visible || root.settingsVisible)) {
                root.fallbackProcessGeneration = root.audioSourceGeneration;
                fallbackWatchProcess.running = true;
            }
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
        id: mediaStatusProcess

        command: Commands.controlsHelperCommand("media-status")
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseMedia(this.text)
        }
    }

    Process {
        id: mediaWatchProcess
        command: Commands.controlsHelperCommand("media-watch")
        running: true

        stdout: SplitParser {
            onRead: function(data) {
                root.parseMedia(data);
            }
        }
        onRunningChanged: {
            if (!running) mediaWatchRestartTimer.restart();
        }
    }

    Timer {
        id: mediaWatchRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (!mediaWatchProcess.running) mediaWatchProcess.running = true;
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
                if (root.actionProcessGeneration !== root.mutationGeneration) return;
                root.busy = false;
                root.appliedMutationGeneration = root.mutationGeneration;
                root.refresh();
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const error = this.text.trim();
                if (error.length > 0 && root.actionProcessGeneration === root.mutationGeneration) {
                    root.message = error;
                }
            }
        }
    }

    Component.onCompleted: root.refreshAudioStatus()
}
