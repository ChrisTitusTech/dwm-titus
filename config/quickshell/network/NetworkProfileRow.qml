import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property var profile
    property bool active: false
    signal connectRequested(var profile)
    signal disconnectRequested(string device)

    height: Theme.confirmButtonHeight
    color: rowMouse.containsMouse ? Theme.surfaceHover : Theme.surface
    radius: Theme.radius

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.rowSpacing
        anchors.rightMargin: Theme.rowSpacing
        spacing: Theme.rowSpacing

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.compactSpacing

            Text {
                Layout.fillWidth: true
                text: root.profile.name
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.active ? root.profile.type + " on " + root.profile.device : root.profile.type
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }
        }

        Rectangle {
            Layout.preferredWidth: actionText.implicitWidth + 18
            Layout.preferredHeight: Theme.chipHeight
            color: actionMouse.containsMouse ? Theme.accent : Theme.border
            radius: Theme.radius

            Text {
                id: actionText

                anchors.centerIn: parent
                text: root.active ? "Disconnect" : "Connect"
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            MouseArea {
                id: actionMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.active ? root.disconnectRequested(root.profile.device) : root.connectRequested(root.profile)
            }
        }
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }
}
