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
    anchor.rect.x: root.anchorX
    anchor.rect.y: root.anchorY
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom

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
