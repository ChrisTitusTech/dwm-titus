import QtQuick
import qs.core

Item {
    id: root

    property bool checked: false
    property bool busy: false
    required property string accessibleName
    property string accessibleDescription: ""
    signal toggled

    readonly property bool hot: toggleMouse.containsMouse || activeFocus

    implicitWidth: Theme.panelToggleWidth
    implicitHeight: Theme.panelToggleHeight
    activeFocusOnTab: root.enabled && !root.busy
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.description: root.accessibleDescription
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onPressAction: root.requestToggle()
    Accessible.onToggleAction: root.requestToggle()

    function requestToggle() {
        if (root.enabled && !root.busy) root.toggled();
    }

    Keys.onPressed: function(event) {
        if (!root.enabled || root.busy || event.isAutoRepeat) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.requestToggle();
            event.accepted = true;
        }
    }

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.controlSelectedFill : Theme.controlNormalFill
        border.color: root.activeFocus ? Theme.controlFocusBorder
            : root.hot ? Theme.controlHoverBorder
            : root.checked ? Theme.controlSelectedBorder : Theme.controlNormalBorder
        border.width: root.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth

        Behavior on color { ColorAnimation { duration: Theme.animationFast } }

        Rectangle {
            width: Theme.panelToggleKnobSize
            height: width
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - Theme.panelToggleInset : Theme.panelToggleInset
            color: root.checked ? Theme.controlSelectedText : Theme.controlDisabledText

            Behavior on x {
                NumberAnimation { duration: Theme.animationFast; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        id: toggleMouse

        anchors.fill: parent
        enabled: root.enabled && !root.busy
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.forceActiveFocus();
            root.requestToggle();
        }
    }
}
