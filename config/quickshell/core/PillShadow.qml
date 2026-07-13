import QtQuick
import qs.core

Rectangle {
    property real cornerRadius: Theme.pillRadius

    x: 1
    y: 2
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    radius: cornerRadius
    color: Theme.shadow
    opacity: 0.45
    z: -1
}
