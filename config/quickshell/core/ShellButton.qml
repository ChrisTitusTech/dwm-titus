import QtQuick
import qs.core

Rectangle {
    id: root

    required property string label
    property url leadingIcon: ""
    property real leadingIconSize: Theme.fontBodySmallSize
    property string leadingLabel: ""
    property real labelSpacing: 0
    property string accessibleDescription: ""
    property bool danger: false
    property bool primary: false
    property bool compact: true
    property bool hovered: buttonMouse.containsMouse

    signal activated

    implicitWidth: buttonContent.implicitWidth + (Theme.controlPaddingX * 2)
    implicitHeight: Theme.controlHeight
    activeFocusOnTab: root.enabled
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.accessibleDescription
    Accessible.onPressAction: root.requestActivation()
    color: !root.enabled ? Theme.controlDisabledFill
        : root.danger ? (root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill)
        : root.primary ? (root.hovered ? Theme.accentSecondary : Theme.accent)
        : root.hovered ? Theme.controlHoverFill : Theme.controlNormalFill
    border.color: root.activeFocus ? (root.primary ? Theme.textStrong : Theme.controlFocusBorder)
        : !root.enabled ? Theme.controlDisabledBorder
        : root.danger ? Theme.danger
        : root.primary ? Theme.accent
        : root.hovered ? Theme.controlHoverBorder : Theme.controlNormalBorder
    border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
    radius: Theme.controlRadius

    function requestActivation() {
        if (root.enabled) root.activated();
    }

    Keys.onPressed: event => {
        if (root.enabled && !event.isAutoRepeat
                && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
            root.requestActivation();
            event.accepted = true;
        }
    }

    Row {
        id: buttonContent

        anchors.centerIn: parent
        spacing: (root.leadingIcon.toString().length > 0 || root.leadingLabel.length > 0)
            && root.label.length > 0 ? root.labelSpacing : 0

        Image {
            visible: root.leadingIcon.toString().length > 0
            width: visible ? root.leadingIconSize : 0
            height: visible ? root.leadingIconSize : 0
            source: root.leadingIcon
            fillMode: Image.PreserveAspectFit
            smooth: true
        }

        Text {
            visible: root.leadingIcon.toString().length === 0 && root.leadingLabel.length > 0
            text: root.leadingLabel
            color: buttonLabel.color
            font: buttonLabel.font
        }

        Text {
            id: buttonLabel

            visible: root.label.length > 0
            text: root.label
            color: !root.enabled ? Theme.controlDisabledText
                : root.danger ? (root.hovered ? Theme.controlHoverText : Theme.readableText(Theme.textStrong, Theme.controlNormalFill))
                : root.primary ? (root.hovered ? Theme.accentHoverText : Theme.accentText)
                : root.hovered ? Theme.controlHoverText : Theme.controlNormalText
            font.family: Theme.fontFamily
            font.pixelSize: root.compact ? Theme.fontBodySmallSize : Theme.fontBodySize
            font.bold: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: buttonMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.requestActivation()
    }
}
