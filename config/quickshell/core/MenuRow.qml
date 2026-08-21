import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property string detail: ""
    property bool active: false
    property bool navigates: false

    signal activated

    implicitHeight: Theme.controlRowHeight
    radius: Theme.controlRadius
    color: root.active ? Theme.menuSelectedBackground
        : rowMouse.containsMouse ? Theme.menuHoverBackground : Theme.transparent

    UiText {
        anchors.left: parent.left
        anchors.leftMargin: Theme.controlPaddingX
        anchors.right: rowDetail.left
        anchors.rightMargin: Theme.spacingLg
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.active ? Theme.menuSelectedText
            : rowMouse.containsMouse ? Theme.menuHoverText : Theme.menuText
        elide: Text.ElideRight
    }

    UiText {
        id: rowDetail

        anchors.right: parent.right
        anchors.rightMargin: Theme.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        text: root.detail.length > 0 ? root.detail : root.navigates ? ">" : ""
        color: root.active ? Theme.menuSelectedText : Theme.menuMutedText
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
