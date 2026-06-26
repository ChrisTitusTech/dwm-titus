import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    property string clockText: ""
    property string systemText: ""

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

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                required property var modelData

                screen: modelData
                implicitHeight: 30
                color: "#2e3440"
                exclusiveZone: 30

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
