import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var launcherModel

    title: "dwm launcher"
    visible: launcherModel.visible
    screen: launcherModel.targetScreen
    implicitWidth: 820
    implicitHeight: 600
    color: Theme.transparent

    function focusSearch() {
        launcherSearch.forceActiveFocus();
        launcherSearch.cursorPosition = launcherSearch.text.length;
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(root.focusSearch);
        }
    }

    ShellSurface {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.popupSpacing

            LargeSurfaceHeader {
                Layout.fillWidth: true
                eyebrow: "Application index"
                title: "Applications"
                subtitle: "Type to filter / Enter to launch / Esc to close"
                status: root.launcherModel.status
                statusColor: Theme.accent
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.largeSurfaceSearchHeight
                color: launcherSearch.activeFocus ? Theme.controlFocusFill : Theme.controlNormalFill
                border.color: launcherSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                border.width: launcherSearch.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                radius: Theme.largeSurfaceCardRadius

                UiText {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "/"
                    color: launcherSearch.activeFocus ? Theme.menuActionText : Theme.menuMutedText
                    font.bold: true
                }

                TextInput {
                    id: launcherSearch

                    anchors.fill: parent
                    anchors.leftMargin: 38
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.controlFocusText
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    text: root.launcherModel.query
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    clip: true

                    onTextChanged: root.launcherModel.setQuery(text)

                    Keys.onPressed: function(event) {
                        const ctrl = event.modifiers & Qt.ControlModifier;

                        if (event.key === Qt.Key_Down || (event.key === Qt.Key_N && ctrl)) {
                            root.launcherModel.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_P && ctrl)) {
                            root.launcherModel.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageDown) {
                            root.launcherModel.selectRelative(8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_PageUp) {
                            root.launcherModel.selectRelative(-8);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Home) {
                            root.launcherModel.selectAbsolute(0);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_End) {
                            root.launcherModel.selectAbsolute(root.launcherModel.filteredApps.length - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.launcherModel.launchSelectedApp();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape || (event.key === Qt.Key_C && ctrl)) {
                            root.launcherModel.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 38
                    anchors.verticalCenter: parent.verticalCenter
                    visible: launcherSearch.text.length === 0
                    text: "Search applications"
                    color: Theme.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true

                SectionLabel {
                    label: "Categories"
                }

                UiText {
                    text: root.launcherModel.filteredApps.length + " shown"
                    color: Theme.menuMutedText
                    font.pixelSize: Theme.fontCaptionSize
                    font.bold: true
                }
            }

            LauncherCategoryRow {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                launcherModel: root.launcherModel
            }

            ListView {
                id: launcherResults

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: Theme.listSpacing
                model: root.launcherModel.filteredApps

                onModelChanged: {
                    if (root.launcherModel.filteredApps.length > 0) {
                        positionViewAtIndex(root.launcherModel.selectedIndex, ListView.Contain);
                    }
                }

                Connections {
                    target: root.launcherModel

                    function onSelectedIndexChanged() {
                        if (root.launcherModel.filteredApps.length > 0) {
                            launcherResults.positionViewAtIndex(root.launcherModel.selectedIndex, ListView.Contain);
                        }
                    }
                }

                delegate: LauncherResultDelegate {
                    width: launcherResults.width
                    selected: index === root.launcherModel.selectedIndex
                    launcherModel: root.launcherModel
                }
            }
        }
    }
}
