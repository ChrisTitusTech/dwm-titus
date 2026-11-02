import QtQuick
import QtQuick.Layouts
import qs.core

Rectangle {
    id: root

    required property int index
    required property var modelData
    required property bool selected
    required property var clipboardModel
    required property int timeTick
    // The delete button sits on top of the row area; once it takes the pointer,
    // rowMouse loses containsMouse, so hover must survive that handoff.
    property bool hovered: rowMouse.containsMouse || deleteMouse.containsMouse

    readonly property string preview: modelData.text.replace(/\r?\n/g, "  ⏎  ")
    // timeTick is referenced so the age string recomputes on the periodic refresh.
    readonly property string age: root.timeTick >= 0
        ? root.clipboardModel.relativeTime(root.modelData.timestamp) : ""

    height: Theme.scaledSize(48)
    radius: Theme.largeSurfaceCardRadius
    color: root.selected ? Theme.menuSelectedBackground : root.hovered ? Theme.menuHoverBackground : Theme.transparent
    border.color: root.selected ? Theme.controlSelectedBorder : Theme.transparent
    border.width: Theme.controlBorderWidth

    MouseArea {
        id: rowMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clipboardModel.select(root.index)
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingLg

        Rectangle {
            Layout.preferredWidth: 3
            Layout.preferredHeight: 30
            visible: root.selected
            color: Theme.accentSecondary
            radius: 2
        }

        Text {
            Layout.fillWidth: true
            text: root.preview
            color: root.selected ? Theme.menuSelectedText : root.hovered ? Theme.menuHoverText : Theme.menuText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodyFontSize
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        UiText {
            text: root.age
            color: Theme.menuMutedText
            font.pixelSize: Theme.fontCaptionSize
            font.bold: true
        }

        Rectangle {
            Layout.preferredWidth: Theme.scaledSize(24)
            Layout.preferredHeight: Theme.scaledSize(24)
            radius: Theme.controlRadius
            // Always occupy its slot so the timestamp never shifts when it appears;
            // fade instead of toggling visibility to avoid a hover reflow loop.
            opacity: root.hovered ? 1 : 0
            color: deleteMouse.containsMouse ? Theme.dangerSurface : Theme.transparent

            Behavior on opacity {
                NumberAnimation { duration: Theme.animationFast }
            }

            UiText {
                anchors.centerIn: parent
                text: "✕"
                color: deleteMouse.containsMouse ? Theme.danger : Theme.menuMutedText
                font.pixelSize: Theme.smallFontSize
            }

            MouseArea {
                id: deleteMouse

                anchors.fill: parent
                enabled: root.hovered
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clipboardModel.deleteAt(root.index)
            }
        }
    }
}
