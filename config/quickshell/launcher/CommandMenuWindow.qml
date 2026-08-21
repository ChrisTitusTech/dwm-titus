import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var commandMenuModel

    title: "dwm menu"
    visible: commandMenuModel.visible
    screen: commandMenuModel.targetScreen
    implicitWidth: 720
    implicitHeight: 600
    color: Theme.transparent

    function focusSearch() {
        commandSearch.text = root.commandMenuModel.query;
        commandSearch.forceActiveFocus();
        commandSearch.cursorPosition = commandSearch.text.length;
        pointerWarpProcess.running = false;
        pointerWarpProcess.running = true;
    }

    onVisibleChanged: {
        if (visible) Qt.callLater(root.focusSearch);
    }

    Process {
        id: pointerWarpProcess

        command: Commands.pointerHelperCommand("command-menu")
    }

    ShellSurface {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            RowLayout {
                Layout.fillWidth: true

                Text {
                    Layout.fillWidth: true
                    text: root.commandMenuModel.breadcrumb
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    text: root.commandMenuModel.rows.length === 1
                        ? "1 item" : root.commandMenuModel.rows.length + " items"
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.smallFontSize
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                color: Theme.controlNormalFill
                border.color: commandSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                border.width: commandSearch.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                radius: Theme.controlRadius

                TextInput {
                    id: commandSearch

                    anchors.fill: parent
                    anchors.leftMargin: Theme.controlPaddingX + Theme.spacingSm
                    anchors.rightMargin: Theme.controlPaddingX + Theme.spacingSm
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textStrong
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    clip: true

                    onTextChanged: {
                        if (text !== root.commandMenuModel.query) root.commandMenuModel.setQuery(text);
                    }

                    Keys.onPressed: function(event) {
                        const ctrl = event.modifiers & Qt.ControlModifier;

                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                            root.commandMenuModel.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                            root.commandMenuModel.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            root.commandMenuModel.selectRelative(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.commandMenuModel.selectRelative(-8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.commandMenuModel.selectAbsolute(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.commandMenuModel.selectAbsolute(root.commandMenuModel.rows.length - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.commandMenuModel.activateSelected();
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Backspace) && text.length === 0) {
                            event.accepted = root.commandMenuModel.navigateBack();
                        } else if (event.key === Qt.Key_Escape) {
                            root.commandMenuModel.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.controlPaddingX + Theme.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    visible: commandSearch.text.length === 0
                    text: "Type to search commands and applications"
                    color: Theme.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                }
            }

            ListView {
                id: commandResults

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.commandMenuModel.rows

                Connections {
                    target: root.commandMenuModel

                    function onQueryChanged() {
                        if (commandSearch.text !== root.commandMenuModel.query) {
                            commandSearch.text = root.commandMenuModel.query;
                        }
                    }

                    function onSelectedIndexChanged() {
                        if (root.commandMenuModel.rows.length > 0) {
                            commandResults.positionViewAtIndex(root.commandMenuModel.selectedIndex, ListView.Contain);
                        }
                    }
                }

                delegate: CommandMenuRow {
                    width: commandResults.width
                    selected: index === root.commandMenuModel.selectedIndex
                    commandMenuModel: root.commandMenuModel
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Enter select  |  Left/Backspace back  |  Esc close"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
