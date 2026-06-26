import QtQuick
import QtQuick.Layouts
import qs.core

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
                required property var modelData

                Layout.preferredHeight: Theme.chipHeight
                Layout.preferredWidth: launcherCategoryLabel.width + 22
                radius: Theme.radius
                color: root.launcherModel.category === modelData.id ? Theme.accent : launcherCategoryMouse.containsMouse ? Theme.surfaceHover : Theme.surface

                Text {
                    id: launcherCategoryLabel

                    anchors.centerIn: parent
                    text: modelData.label + " " + modelData.count
                    color: root.launcherModel.category === parent.modelData.id ? Theme.accentText : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                    font.bold: root.launcherModel.category === parent.modelData.id
                }

                MouseArea {
                    id: launcherCategoryMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launcherModel.setCategory(parent.modelData.id)
                }
            }
        }
    }
}
