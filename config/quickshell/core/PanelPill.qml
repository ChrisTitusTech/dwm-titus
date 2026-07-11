import QtQuick
import qs.core

Rectangle {
    id: root

    property bool active: false
    property bool hovered: false

    implicitHeight: Theme.pillHeight
    color: active ? Theme.surfaceActive : (hovered ? Theme.surfaceHover : Theme.surface)
    border.color: active ? Theme.accent : Theme.border
    border.width: Theme.pillBorderWidth
    radius: Theme.pillRadius

    Behavior on color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    Behavior on border.color {
        ColorAnimation { duration: Theme.animationNormal }
    }

    PillShadow {}
}
