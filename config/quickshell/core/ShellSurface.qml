import QtQuick
import qs.core

Rectangle {
    id: root

    default property alias content: body.data
    property alias contentItem: body
    property int margin: Theme.popupPadding

    opacity: 1.0
    color: Theme.popupBackground
    border.color: Theme.popupBorder
    border.width: Theme.controlBorderWidth
    radius: Theme.popupRadius

    PillShadow { cornerRadius: root.radius }

    Item {
        id: body

        anchors.fill: parent
        anchors.margins: root.margin
    }
}
