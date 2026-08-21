import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs.core

Rectangle {
    id: root

    required property int index
    required property var modelData
    required property bool selected
    required property var commandMenuModel

    height: Theme.controlRowHeight + Theme.spacingHuge
    radius: Theme.controlRadius
    color: root.selected
        ? Theme.menuSelectedBackground
        : mouseArea.containsMouse ? Theme.menuHoverBackground : Theme.transparent
    opacity: root.modelData.enabled === false ? 0.55 : 1.0

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.modelData.enabled === false ? Qt.ArrowCursor : Qt.PointingHandCursor
        onEntered: {
            if (root.modelData.enabled !== false) root.commandMenuModel.selectAbsolute(root.index);
        }
        onClicked: root.commandMenuModel.activate(root.modelData)
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.controlPaddingX + Theme.spacingSm
        anchors.rightMargin: Theme.controlPaddingX + Theme.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.rowSpacing

        Item {
            Layout.preferredWidth: Theme.iconSize
            Layout.preferredHeight: Theme.iconSize
            Layout.alignment: Qt.AlignVCenter

            IconImage {
                anchors.fill: parent
                source: root.modelData.kind === "application"
                    ? Icons.launcherIcon(root.modelData.app.icon) : ""
                visible: root.modelData.kind === "application"
            }

            Text {
                anchors.centerIn: parent
                text: root.modelData.kind === "submenu" ? ">" : root.modelData.current ? "*" : "-"
                visible: root.modelData.kind !== "application"
                color: root.selected ? Theme.menuSelectedText : Theme.menuActionText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
                font.bold: true
            }
        }

        Column {
            Layout.fillWidth: true
            spacing: Theme.tightSpacing

            Text {
                width: parent.width
                text: root.modelData.label
                color: root.selected ? Theme.menuSelectedText : Theme.menuText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodyFontSize
                font.bold: root.selected || root.modelData.current
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.modelData.detail || ""
                color: root.selected ? Theme.menuSelectedText : Theme.menuMutedText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.modelData.kind === "submenu" ? ">" : root.modelData.current ? "Current" : ""
            color: root.selected ? Theme.menuSelectedText : Theme.menuMutedText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
        }
    }
}
