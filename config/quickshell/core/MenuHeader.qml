import QtQuick
import QtQuick.Layouts
import qs.core

RowLayout {
    id: root

    required property string title
    property bool showBack: false
    property real titleLetterSpacing: 1

    signal backRequested
    signal closeRequested

    implicitHeight: 26
    spacing: 8

    UiText {
        visible: root.showBack
        text: "< Back"
        color: backMouse.containsMouse ? Theme.accent : Theme.textMuted

        MouseArea {
            id: backMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.backRequested()
        }
    }

    UiText {
        Layout.fillWidth: true
        text: root.title
        color: Theme.textStrong
        font.letterSpacing: root.titleLetterSpacing
        elide: Text.ElideRight
    }

    UiText {
        text: "x"
        color: closeMouse.containsMouse ? Theme.accent : Theme.textMuted

        MouseArea {
            id: closeMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
        }
    }
}
