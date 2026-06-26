import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property string clockText: ""
    property string networkText: ""
    property string powerText: ""
    property string systemText: ""
    property string volumeText: ""
    property string activeWindowTitle: "Desktop"
    property int currentWorkspace: 0
    property bool launcherVisible: false
    property var workspaceNames: ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    function closeLauncher() {
        root.launcherVisible = false;
    }

    function openLauncher() {
        root.launcherVisible = true;
    }

    function toggleLauncher() {
        root.launcherVisible = !root.launcherVisible;
    }

    function updateWorkspaceState(text) {
        const lines = text.trim().split("\n");

        for (const line of lines) {
            const separator = line.indexOf("=");

            if (separator < 0) {
                continue;
            }

            const key = line.slice(0, separator);
            const value = line.slice(separator + 1);

            if (key === "current") {
                const parsed = parseInt(value, 10);

                root.currentWorkspace = isNaN(parsed) ? 0 : parsed;
            } else if (key === "names") {
                root.workspaceNames = value.length > 0 ? value.split("|") : [];
            } else if (key === "title") {
                root.activeWindowTitle = value.length > 0 ? value : "Desktop";
            }
        }
    }

    function switchWorkspace(index) {
        switchWorkspaceProcess.command = ["dwm-quickshell-state", "switch", index.toString()];
        switchWorkspaceProcess.running = true;
    }

    IpcHandler {
        target: "launcher"

        function close(): void {
            root.closeLauncher();
        }

        function open(): void {
            root.openLauncher();
        }

        function toggle(): void {
            root.toggleLauncher();
        }
    }

    Process {
        id: dateProcess

        command: ["date", "+%a %b %d  %H:%M"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.clockText = this.text.trim()
        }
    }

    Process {
        id: systemProcess

        command: ["sh", "-c", "load=$(cut -d ' ' -f1 /proc/loadavg); mem=$(awk '/MemTotal/ { total = $2 } /MemAvailable/ { available = $2 } END { printf \"%d\", (total - available) * 100 / total }' /proc/meminfo); printf 'CPU %s  RAM %s%%' \"$load\" \"$mem\""]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.systemText = this.text.trim()
        }
    }

    Process {
        id: networkProcess

        command: ["sh", "-c", "iface=$(ip route show default 2>/dev/null | awk 'NR == 1 { print $5 }'); if [ -n \"$iface\" ]; then state=$(cat \"/sys/class/net/$iface/operstate\" 2>/dev/null || printf unknown); printf 'NET %s %s' \"$iface\" \"$state\"; else printf 'NET offline'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.networkText = this.text.trim()
        }
    }

    Process {
        id: volumeProcess

        command: ["sh", "-c", "if command -v pactl >/dev/null 2>&1; then mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{ print $2 }'); volume=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | awk 'match($0, /[0-9]+%/) { print substr($0, RSTART, RLENGTH); exit }'); if [ \"$mute\" = yes ]; then printf 'VOL muted'; else printf 'VOL %s' \"${volume:-n/a}\"; fi; else printf 'VOL n/a'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.volumeText = this.text.trim()
        }
    }

    Process {
        id: powerProcess

        command: ["sh", "-c", "battery=; for path in /sys/class/power_supply/BAT*; do [ -e \"$path\" ] || continue; battery=$path; break; done; if [ -n \"$battery\" ]; then capacity=$(cat \"$battery/capacity\" 2>/dev/null || printf n/a); status=$(cat \"$battery/status\" 2>/dev/null || printf unknown); printf 'BAT %s%% %s' \"$capacity\" \"$status\"; else printf 'AC'; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.powerText = this.text.trim()
        }
    }

    Process {
        id: workspaceProcess

        command: ["dwm-quickshell-state", "watch"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: function(data) {
                root.updateWorkspaceState(data);
            }
        }
    }

    Process {
        id: switchWorkspaceProcess

        command: ["dwm-quickshell-state", "switch", root.currentWorkspace.toString()]
        running: false
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: dateProcess.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: systemProcess.running = true
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: networkProcess.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: volumeProcess.running = true
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: powerProcess.running = true
    }

    FloatingWindow {
        id: launcherWindow

        title: "dwm launcher"
        visible: root.launcherVisible
        implicitWidth: 620
        implicitHeight: 430
        color: "#00000000"

        Rectangle {
            anchors.fill: parent
            color: "#2e3440"
            border.color: "#4c566a"
            border.width: 1
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    text: "Applications"
                    color: "#d8dee9"
                    font.pixelSize: 18
                    font.bold: true
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    color: "#3b4252"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: "Launcher UI ready"
                        color: "#d8dee9"
                        font.pixelSize: 14
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "Desktop application indexing will be added in the next task."
                    color: "#aeb7c4"
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }

                Item {
                    Layout.fillHeight: true
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                required property var modelData

                screen: modelData
                implicitHeight: 30
                color: "#2e3440"
                exclusiveZone: 30
                aboveWindows: true

                anchors {
                    top: true
                    left: true
                    right: true
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    Text {
                        text: "dwm"
                        color: "#d8dee9"
                        font.pixelSize: 13
                        font.bold: true
                        verticalAlignment: Text.AlignVCenter
                    }

                    Repeater {
                        model: root.workspaceNames

                        delegate: Rectangle {
                            required property int index
                            required property string modelData

                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            radius: 3
                            color: index === root.currentWorkspace ? "#3b4252" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: parent.modelData
                                color: parent.index === root.currentWorkspace ? "#81a1c1" : "#d8dee9"
                                font.pixelSize: 13
                                font.bold: parent.index === root.currentWorkspace
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.switchWorkspace(parent.index)
                            }
                        }
                    }

                    Text {
                        Layout.maximumWidth: 360
                        text: root.activeWindowTitle
                        color: "#d8dee9"
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.powerText
                        color: "#d8dee9"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: root.volumeText
                        color: "#d8dee9"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: root.networkText
                        color: "#d8dee9"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: root.systemText
                        color: "#d8dee9"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        text: root.clockText
                        color: "#81a1c1"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
