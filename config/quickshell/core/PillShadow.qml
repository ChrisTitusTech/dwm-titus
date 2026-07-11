import QtQuick
import qs.core

Rectangle {
    x: 1
    y: 2
    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    radius: parent && parent.radius !== undefined ? parent.radius : Theme.pillRadius
    color: Theme.shadow
    opacity: 0.45
    z: -1
}
