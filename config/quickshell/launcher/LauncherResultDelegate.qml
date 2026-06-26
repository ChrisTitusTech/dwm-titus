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
        spacing: Theme.rowSpacing

        IconImage {
            Layout.preferredWidth: Theme.iconSize
            Layout.preferredHeight: Theme.iconSize
            Layout.alignment: Qt.AlignVCenter
            source: Icons.launcherIcon(root.modelData.icon)
        }

        Column {
            Layout.fillWidth: true
            spacing: Theme.tightSpacing

            Text {
                width: parent.width
                text: root.modelData.name
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
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
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }
    }
}
