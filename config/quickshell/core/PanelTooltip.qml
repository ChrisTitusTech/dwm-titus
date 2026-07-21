import QtQuick
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var anchorWindow
    property string label: ""
    property real anchorX: 0
    property real anchorY: 0

    implicitWidth: tooltipLabel.implicitWidth + Theme.pillHorizontalPadding * 2
    implicitHeight: Theme.pillHeight
    color: Theme.transparent

    anchor.window: root.anchorWindow
    anchor.rect.x: Math.max(0, Math.min(root.anchorWindow.width - root.implicitWidth,
                                       root.anchorX - root.implicitWidth / 2))
    anchor.rect.y: root.anchorY

    PanelPill {
        anchors.fill: parent

        UiText {
            id: tooltipLabel

            anchors.centerIn: parent
            text: root.label
            color: Theme.textStrong
            font.pixelSize: Theme.smallFontSize
        }
    }
}
