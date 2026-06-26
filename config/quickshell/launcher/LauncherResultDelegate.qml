import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property int index
    required property var modelData
    required property bool selected
    required property var launcherModel

    height: 54
    radius: Theme.radius
    color: selected ? Theme.surface : "transparent"

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.launcherModel.launchApp(root.modelData)
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        IconImage {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 28
            Layout.alignment: Qt.AlignVCenter
            source: Icons.launcherIcon(root.modelData.icon)
        }

        Column {
            Layout.fillWidth: true
            spacing: 3

            Text {
                width: parent.width
                text: root.modelData.name
                color: Theme.text
                font.pixelSize: 14
                font.bold: root.selected
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: {
                    const detail = root.modelData.generic.length > 0 ? root.modelData.generic : root.modelData.comment;
                    const category = root.launcherModel.categoryLabel(root.modelData.primaryCategory);

                    if (detail.length > 0) {
                        return detail + "  -  " + category;
                    }

                    return category;
                }
                color: Theme.textMuted
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }
}
