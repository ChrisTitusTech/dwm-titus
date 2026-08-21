import QtQuick
import qs.core

Item {
    id: root

    property real value: 0
    property real minimum: 0
    property real maximum: 100
    property real step: 5
    property bool muted: false
    property real liveValue: value
    property bool dragging: sliderMouse.pressed

    signal valueMoved(real value)
    signal valueCommitted(real value)

    readonly property real valueRange: Math.max(0.0001, maximum - minimum)
    readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / valueRange))

    function bounded(value) {
        return Math.max(root.minimum, Math.min(root.maximum, value));
    }

    function valueFromX(x) {
        return root.bounded(root.minimum + (Math.max(0, Math.min(width, x)) / Math.max(1, width)) * root.valueRange);
    }

    function moveTo(value) {
        root.liveValue = root.bounded(value);
        root.valueMoved(root.liveValue);
    }

    onValueChanged: if (!dragging) liveValue = value
    onEnabledChanged: if (enabled && !dragging) liveValue = value

    implicitHeight: Theme.panelSliderHeight
    activeFocusOnTab: root.enabled

    Keys.onPressed: function(event) {
        if (!root.enabled || (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)) return;
        const direction = event.key === Qt.Key_Right ? 1 : -1;
        root.moveTo(root.liveValue + direction * root.step);
        root.valueCommitted(root.liveValue);
        event.accepted = true;
    }

    Rectangle {
        id: sliderTrack

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.panelSliderTrackHeight
        radius: height / 2
        color: Theme.controlNormalFill
        border.color: root.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
        border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.round(parent.width * root.progress)
            height: parent.height
            radius: parent.radius
            color: root.muted ? Theme.controlDisabledText : Theme.accent

            Behavior on width {
                enabled: !root.dragging
                NumberAnimation { duration: Theme.animationFast; easing.type: Easing.OutCubic }
            }
        }
    }

    Rectangle {
        anchors.verticalCenter: sliderTrack.verticalCenter
        x: Math.max(0, Math.min(root.width - width, Math.round(sliderTrack.width * root.progress) - width / 2))
        width: Theme.panelSliderKnobSize
        height: width
        radius: width / 2
        color: root.enabled ? Theme.popupText : Theme.controlDisabledText
        border.color: Theme.popupBackground
        border.width: Theme.controlFocusBorderWidth
        scale: sliderMouse.containsMouse || root.dragging || root.activeFocus ? 1.12 : 1

        Behavior on x {
            enabled: !root.dragging
            NumberAnimation { duration: Theme.animationFast; easing.type: Easing.OutCubic }
        }

        Behavior on scale {
            NumberAnimation { duration: Theme.animationFast; easing.type: Easing.OutCubic }
        }
    }

    MouseArea {
        id: sliderMouse

        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        onPressed: function(mouse) {
            root.forceActiveFocus();
            root.moveTo(root.valueFromX(mouse.x));
        }
        onPositionChanged: function(mouse) {
            if (pressed) root.moveTo(root.valueFromX(mouse.x));
        }
        onReleased: function(mouse) {
            root.moveTo(root.valueFromX(mouse.x));
            root.valueCommitted(root.liveValue);
        }
        onWheel: function(wheel) {
            if (wheel.angleDelta.y === 0) {
                wheel.accepted = false;
                return;
            }
            const direction = wheel.angleDelta.y > 0 ? 1 : -1;
            root.moveTo(root.liveValue + direction * root.step);
            root.valueCommitted(root.liveValue);
            wheel.accepted = true;
        }
    }
}
