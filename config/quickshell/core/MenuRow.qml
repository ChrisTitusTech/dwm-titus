import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property string detail: ""
    property bool active: false
    property bool navigates: false

    signal activated

    implicitHeight: 32
    radius: Theme.smallRadius
    color: rowMouse.containsMouse ? Theme.surfaceHover : Theme.transparent

    UiText {
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.right: rowDetail.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.active ? Theme.accentSecondary : rowMouse.containsMouse ? Theme.textStrong : Theme.text
        elide: Text.ElideRight
    }

    UiText {
        id: rowDetail

        anchors.right: parent.right
        anchors.rightMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail.length > 0 ? root.detail : root.navigates ? ">" : ""
        color: root.active ? Theme.accentSecondary : Theme.textMuted
    }

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }
}
