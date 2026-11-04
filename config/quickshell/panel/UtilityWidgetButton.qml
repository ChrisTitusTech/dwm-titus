import QtQuick
import QtQuick.Layouts
import qs.core

PanelPill {
    id: root
    required property string kind
    required property string label
    signal activated
    Layout.preferredWidth: Theme.pillHeight
    Layout.preferredHeight: Theme.pillHeight
    activeFocusOnTab: true
    outlined: root.activeFocus
    hovered: pointer.containsMouse
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: root.activated()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activated(); event.accepted = true;
        }
    }
    // Small native vector controls do not depend on a particular icon font.
    Canvas {
        id: icon
        anchors.centerIn: parent
        width: Theme.scaledSize(18)
        height: width
        property color ink: Theme.textStrong
        onInkChanged: requestPaint()
        onPaint: {
            const context = getContext("2d");
            context.clearRect(0, 0, width, height);
            const scale = width / 18;
            context.save();
            context.scale(scale, scale);
            context.strokeStyle = icon.ink;
            context.lineWidth = 1.5;
            context.beginPath();
            if (root.kind === "calendar") {
                context.rect(2, 4, 14, 12);
                context.moveTo(2, 8); context.lineTo(16, 8);
                context.moveTo(5, 1); context.lineTo(5, 6);
                context.moveTo(13, 1); context.lineTo(13, 6);
                context.moveTo(6, 10); context.lineTo(6, 14);
                context.moveTo(11, 10); context.lineTo(11, 14);
            } else {
                context.arc(9, 9, 3.5, 0, Math.PI * 2);
                for (let ray = 0; ray < 8; ray++) {
                    const angle = ray * Math.PI / 4;
                    context.moveTo(9 + Math.cos(angle) * 5.5, 9 + Math.sin(angle) * 5.5);
                    context.lineTo(9 + Math.cos(angle) * 8.5, 9 + Math.sin(angle) * 8.5);
                }
            }
            context.stroke();
            context.restore();
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
