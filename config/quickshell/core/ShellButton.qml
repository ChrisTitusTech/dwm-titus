import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property bool danger: false
    property bool compact: true
    property bool hovered: buttonMouse.containsMouse

    signal activated

    implicitWidth: buttonLabel.implicitWidth + 18
    implicitHeight: Theme.buttonHeight
	activeFocusOnTab: root.enabled
    color: !root.enabled ? Theme.barBackground : root.hovered ? Theme.surfaceHover : Theme.surface
	border.color: root.activeFocus ? Theme.accent : !root.enabled ? Theme.border : root.danger ? Theme.danger : root.hovered ? Theme.borderStrong : Theme.border
	border.width: root.activeFocus ? 2 : 1
    radius: Theme.radius

	Keys.onPressed: event => {
		if (root.enabled && !event.isAutoRepeat
				&& (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
			root.activated();
			event.accepted = true;
		}
	}

    Text {
        id: buttonLabel

        anchors.centerIn: parent
        text: root.label
        color: !root.enabled ? Theme.textMuted : root.danger ? Theme.textStrong : Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: root.compact ? Theme.smallFontSize : Theme.panelFontSize
        font.bold: true
        elide: Text.ElideRight
    }

    MouseArea {
        id: buttonMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
