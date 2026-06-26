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
