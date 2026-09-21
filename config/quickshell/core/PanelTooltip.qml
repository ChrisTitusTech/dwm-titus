import QtQuick
import Quickshell
import qs.core

PopupWindow {
    id: root

    required property var anchorWindow
    required property var anchorItem
    property string label: ""
    property real anchorX: 0
    property real anchorY: 0
    property bool rightAligned: false
    readonly property real tooltipWidth: tooltipLabel.implicitWidth + Theme.pillHorizontalPadding * 2

    implicitWidth: root.tooltipWidth
    implicitHeight: Theme.pillHeight
    color: Theme.transparent
    mask: Region {}

    anchor.window: root.anchorWindow
    anchor.rect.x: Math.round(Math.max(0, Math.min(root.anchorWindow.width - root.width,
                                                 root.rightAligned ? root.anchorX - root.width : root.anchorX))) | 0
    anchor.rect.y: root.anchorY
    // Fedora Quickshell qmltypes omit Edges::Flags. Keep these valid runtime flags.
    anchor.edges: Edges.Left | Edges.Top // qmllint disable missing-type
    anchor.gravity: Edges.Right | Edges.Bottom // qmllint disable missing-type
    anchor.onAnchoring: {
        const edge = root.rightAligned ? root.anchorItem.width : root.anchorItem.width / 2;
        const point = root.anchorItem.mapToGlobal(edge, 0);
        const screenX = root.anchorWindow.screen && root.anchorWindow.screen.x !== undefined
            ? root.anchorWindow.screen.x : 0;
        root.anchorX = point.x - screenX;
    }

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
