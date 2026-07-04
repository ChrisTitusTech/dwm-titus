import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.core

PanelWindow {
    id: root

    required property var state
    required property var clock
    required property var networkModel
    required property var controlsModel

    implicitHeight: Theme.panelHeight
    color: Theme.bg
    exclusiveZone: Theme.panelHeight
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
        spacing: Theme.rowSpacing

        Text {
            text: "dwm"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            font.bold: true
            verticalAlignment: Text.AlignVCenter
        }

        Repeater {
            model: root.state.workspaceNames

            delegate: WorkspaceButton {
                required property int index
                required property string modelData

                label: modelData
                selected: index === root.state.currentWorkspace
                onClicked: root.state.switchWorkspace(index)
            }
        }

        Text {
            Layout.maximumWidth: 360
            text: root.state.activeWindowTitle
            color: Theme.text
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            verticalAlignment: Text.AlignVCenter
        }

        Item {
            Layout.fillWidth: true
        }

        Repeater {
            model: root.state.statusSegments

            delegate: Text {
                required property string modelData

                text: modelData
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                verticalAlignment: Text.AlignVCenter
            }
        }

        Rectangle {
            Layout.preferredWidth: volumeLabel.implicitWidth + 18
            Layout.preferredHeight: Theme.pillHeight
            color: controlsMouse.containsMouse || root.controlsModel.visible ? Theme.surfaceHover : Theme.surface
            radius: Theme.radius

            Text {
                id: volumeLabel

                anchors.centerIn: parent
                text: root.controlsModel.volumeText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                id: controlsMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.controlsModel.toggle()
            }
        }

        Rectangle {
            Layout.preferredWidth: networkLabel.implicitWidth + 18
            Layout.preferredHeight: Theme.pillHeight
            color: networkMouse.containsMouse || root.networkModel.visible ? Theme.surfaceHover : Theme.surface
            radius: Theme.radius

            Text {
                id: networkLabel

                anchors.centerIn: parent
                text: root.networkModel.statusText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                verticalAlignment: Text.AlignVCenter
            }

            MouseArea {
                id: networkMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.networkModel.toggle()
            }
        }

        TrayArea {
        }

        Text {
            text: Qt.formatDateTime(root.clock.date, "ddd MMM dd  hh:mm")
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.panelFontSize
            verticalAlignment: Text.AlignVCenter
        }
    }
}
