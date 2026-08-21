import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property var app
    required property bool active
    signal focusRequested(string windowId)

    Layout.preferredWidth: Theme.pillHeight
    Layout.preferredHeight: Theme.pillHeight
    radius: Theme.pillRadius
    color: active ? Theme.controlSelectedFill
        : appMouse.containsMouse ? Theme.controlHoverFill : Theme.transparent
    border.color: active ? Theme.controlSelectedBorder
        : appMouse.containsMouse ? Theme.controlHoverBorder : Theme.transparent
    border.width: active || appMouse.containsMouse ? Theme.pillBorderWidth : 0

    IconImage {
        anchors.centerIn: parent
        width: Theme.trayIconSize
        height: Theme.trayIconSize
        source: Icons.launcherIcon(root.app.appClass)
    }

    MouseArea {
        id: appMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.focusRequested(root.app.windowId)
    }
}
