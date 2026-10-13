import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var clipboardModel

    title: "dwm clipboard"
    visible: clipboardModel.visible
    screen: clipboardModel.targetScreen
    implicitWidth: 720
    implicitHeight: 600
    color: Theme.transparent

    function focusSearch() {
        clipboardSearch.forceActiveFocus();
        clipboardSearch.cursorPosition = clipboardSearch.text.length;
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(root.focusSearch);
        }
    }

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.clipboardModel.timeTick++
    }

    ShellSurface {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.clipboardModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            LargeSurfaceHeader {
                Layout.fillWidth: true
                eyebrow: "Clipboard"
                title: "Clipboard History"
                subtitle: "Type to filter / Enter to copy / Esc to close"
                status: root.clipboardModel.status
                statusColor: Theme.accent
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.largeSurfaceSearchHeight
                color: clipboardSearch.activeFocus ? Theme.controlFocusFill : Theme.controlNormalFill
                border.color: clipboardSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                border.width: clipboardSearch.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                radius: Theme.largeSurfaceCardRadius

                UiText {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "/"
                    color: clipboardSearch.activeFocus ? Theme.menuActionText : Theme.menuMutedText
                    font.bold: true
                }

                TextInput {
                    id: clipboardSearch

                    anchors.fill: parent
                    anchors.leftMargin: 38
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.controlFocusText
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    text: root.clipboardModel.query
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    clip: true

                    onTextChanged: root.clipboardModel.setQuery(text)

                    Keys.onPressed: function(event) {
                        const ctrl = event.modifiers & Qt.ControlModifier;

                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                            root.clipboardModel.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                            root.clipboardModel.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            root.clipboardModel.selectRelative(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.clipboardModel.selectRelative(-8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.clipboardModel.selectAbsolute(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.clipboardModel.selectAbsolute(root.clipboardModel.filteredEntries.length - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.clipboardModel.copySelected();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_D && ctrl) {
                            root.clipboardModel.deleteAt(root.clipboardModel.selectedIndex);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_C && ctrl)) {
                            root.clipboardModel.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.verticalCenter: parent.verticalCenter
                    visible: clipboardSearch.text.length === 0
                    text: "Search clipboard entries"
                    color: Theme.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true

                SectionLabel {
                    label: "Entries"
                }

                UiText {
                    text: root.clipboardModel.filteredEntries.length + " shown"
                    color: Theme.menuMutedText
                    font.pixelSize: Theme.fontCaptionSize
                    font.bold: true
                }

                Item {
                    Layout.fillWidth: true
                }

                ShellButton {
                    label: "Clear all"
                    danger: true
                    enabled: root.clipboardModel.entries.length > 0
                    accessibleDescription: "Delete every clipboard history entry"
                    onActivated: root.clipboardModel.clearAll()
                }
            }

            UiText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: root.clipboardModel.filteredEntries.length === 0
                text: root.clipboardModel.entries.length === 0
                    ? "Nothing copied yet — copy some text and it will appear here"
                    : "No entries match your search"
                color: Theme.menuMutedText
            }

            ListView {
                id: clipboardResults

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.clipboardModel.filteredEntries

                onModelChanged: {
                    if (root.clipboardModel.filteredEntries.length > 0) {
                        positionViewAtIndex(root.clipboardModel.selectedIndex, ListView.Contain);
                    }
                }

                Connections {
                    target: root.clipboardModel

                    function onSelectedIndexChanged() {
                        if (root.clipboardModel.filteredEntries.length > 0) {
                            clipboardResults.positionViewAtIndex(root.clipboardModel.selectedIndex, ListView.Contain);
                        }
                    }
                }

                delegate: ClipboardEntryRow {
                    width: clipboardResults.width
                    selected: index === root.clipboardModel.selectedIndex
                    clipboardModel: root.clipboardModel
                    timeTick: root.clipboardModel.timeTick
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Enter copy  |  Ctrl+D delete  |  Esc close"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
