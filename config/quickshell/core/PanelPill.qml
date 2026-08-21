import QtQuick
import qs.core

Rectangle {
    id: root

    property bool active: false
    property bool hovered: false
    property bool outlined: false

    implicitHeight: Theme.pillHeight
    opacity: 1.0
    color: active ? Theme.controlSelectedFill
        : hovered ? Theme.controlHoverFill
        : outlined ? Theme.controlNormalFill : Theme.transparent
    border.color: active ? Theme.controlSelectedBorder
        : hovered ? Theme.controlHoverBorder
        : outlined ? Theme.controlNormalBorder : Theme.transparent
    border.width: Theme.pillBorderWidth
    radius: Theme.pillRadius

    Behavior on color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    Behavior on border.color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    PillShadow { cornerRadius: root.radius }
}
