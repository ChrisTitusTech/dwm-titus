import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var launcherModel

    contentWidth: launcherCategoryRow.width
    contentHeight: height
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    RowLayout {
        id: launcherCategoryRow

        height: parent.height
        spacing: Theme.listSpacing + Theme.compactSpacing

        Repeater {
            model: root.launcherModel.categories

            delegate: Rectangle {
                id: categoryDelegate

                required property var modelData

                Layout.preferredHeight: Theme.chipHeight
                Layout.preferredWidth: launcherCategoryLabel.width + 22
                radius: Theme.radius
                color: root.launcherModel.category === categoryDelegate.modelData.id ? Theme.accent : launcherCategoryMouse.containsMouse ? Theme.surfaceHover : Theme.surface

                Text {
                    id: launcherCategoryLabel

                    anchors.centerIn: parent
                    text: categoryDelegate.modelData.label + " " + categoryDelegate.modelData.count
                    color: root.launcherModel.category === categoryDelegate.modelData.id ? Theme.accentText : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    font.bold: root.launcherModel.category === categoryDelegate.modelData.id
                }

                MouseArea {
                    id: launcherCategoryMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launcherModel.setCategory(categoryDelegate.modelData.id)
                }
            }
        }
    }
}
