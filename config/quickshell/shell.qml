import QtQuick
import QtQuick.Layouts
import Quickshell

ShellRoot {
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
                        text: "Quickshell"
                        color: "#81a1c1"
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
