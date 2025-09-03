import Quickshell 1.0
import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15

PanelWindow {
    id: bar
    width: Screen.width
    height: 28
    color: "#1a1a1a"
    anchors.top: parent.top
    visible: true

    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 20

        // Left: Workspace indicator (fake for dwm, but you can hook to xprop/xdotool)
        Text {
            text: "WS: 1"
            color: "white"
            font.bold: true
            Layout.alignment: Qt.AlignVCenter | Qt.AlignLeft
        }

        // Center: Clock
        Item {
            Layout.alignment: Qt.AlignCenter
            Text {
                id: clock
                text: Qt.formatDateTime(new Date(), "HH:mm:ss")
                color: "white"
                font.pixelSize: 14
                Timer {
                    interval: 1000; running: true; repeat: true
                    onTriggered: clock.text = Qt.formatDateTime(new Date(), "HH:mm:ss")
                }
            }
        }

        // Right: Volume indicator (pamixer required)
        Text {
            id: vol
            text: "Vol: ?"
            color: "white"
            font.pixelSize: 14
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight

            Timer {
                interval: 2000; running: true; repeat: true
                onTriggered: {
                    var proc = Qt.createQmlObject('import QtQuick 2.0; Process { }', vol)
                    proc.command = ["pamixer", "--get-volume"]
                    proc.onReadyReadStandardOutput.connect(function() {
                        vol.text = "Vol: " + proc.readAllStandardOutput().trim()
                    })
                    proc.start()
                }
            }
        }
    }
}
