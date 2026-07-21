import QtQuick
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var anchorWindow
    property string label: ""
    property real anchorX: 0
    property real anchorY: 0
    property bool rightAligned: false
    readonly property real tooltipWidth: tooltipLabel.implicitWidth + Theme.pillHorizontalPadding * 2

    implicitWidth: root.anchorWindow ? root.anchorWindow.width : root.tooltipWidth
    implicitHeight: Theme.pillHeight
    color: Theme.transparent
    mask: Region {}

    anchor.window: root.anchorWindow
    anchor.rect.x: 0
    anchor.rect.y: root.anchorY
    anchor.edges: Edges.Left | Edges.Bottom
    anchor.gravity: Edges.Right | Edges.Bottom

    PanelPill {
        x: Math.max(0, Math.min(root.width - width,
                               root.rightAligned ? root.anchorX - width : root.anchorX))
        width: root.tooltipWidth
        height: parent.height

        UiText {
            id: tooltipLabel

            anchors.centerIn: parent
            text: root.label
            color: Theme.textStrong
            font.pixelSize: Theme.smallFontSize
        }
    }
}
