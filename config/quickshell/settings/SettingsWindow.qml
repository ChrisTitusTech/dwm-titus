import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var settingsModel

    title: "dwm settings"
    visible: settingsModel.visible
    implicitWidth: 980
    implicitHeight: 620
    color: Theme.bg

    function statusColor(status) {
        if (status === "available") return Theme.success;
        if (status === "partial") return Theme.warning;
        if (status === "restricted") return Theme.warning;
        if (status === "unavailable") return Theme.danger;
        return Theme.textMuted;
    }

    function focusSearch() {
        settingsSearch.forceActiveFocus();
        settingsSearch.cursorPosition = settingsSearch.text.length;
    }

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(root.focusSearch);
        } else if (root.settingsModel.visible) {
            root.settingsModel.close();
        }
    }

    Item {
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.settingsModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: Theme.sectionSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.sectionSpacing

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.tightSpacing

                    Text {
                        text: "Settings"
                        color: Theme.textStrong
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.bold: true
                    }

                    Text {
                        text: root.settingsModel.platformName + " - Phase 1 capability overview"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                    }
                }

                ShellButton {
                    label: root.settingsModel.busy ? "Discovering..." : "Refresh"
                    enabled: !root.settingsModel.busy
                    onActivated: root.settingsModel.refresh()
                }

                ShellButton {
                    label: "Close"
                    onActivated: root.settingsModel.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                color: Theme.surface
                border.color: settingsSearch.activeFocus ? Theme.accent : Theme.border
                border.width: 1
                radius: Theme.radius

                TextInput {
                    id: settingsSearch

                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.textStrong
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.accentText
                    text: root.settingsModel.searchQuery
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                    clip: true

                    onTextChanged: root.settingsModel.setSearch(text)

                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Down) {
                            root.settingsModel.selectRelative(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up) {
                            root.settingsModel.selectRelative(-1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (root.settingsModel.filteredSections.length > 0) {
                                root.settingsModel.selectSection(
                                    root.settingsModel.filteredSections[root.settingsModel.selectedIndex].id
                                );
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            root.settingsModel.close();
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    visible: settingsSearch.text.length === 0
                    text: "Search settings sections"
                    color: Theme.placeholder
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.inputFontSize
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Theme.sectionSpacing

                Rectangle {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    radius: Theme.radius

                    ListView {
                        id: sectionList

                        anchors.fill: parent
                        anchors.margins: 8
                        clip: true
                        spacing: Theme.listSpacing
                        model: root.settingsModel.filteredSections

                        delegate: Rectangle {
                            id: sectionButton

                            required property var modelData

                            width: sectionList.width
                            height: 58
                            color: root.settingsModel.selectedSectionId === sectionButton.modelData.id
                                ? Theme.surfaceHover : Theme.transparent
                            border.color: root.settingsModel.selectedSectionId === sectionButton.modelData.id
                                ? Theme.accent : Theme.transparent
                            border.width: 1
                            radius: Theme.radius

                            Column {
                                anchors.fill: parent
                                anchors.margins: 9
                                spacing: 3

                                Text {
                                    text: sectionButton.modelData.label
                                    color: Theme.textStrong
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.panelFontSize
                                    font.bold: root.settingsModel.selectedSectionId === sectionButton.modelData.id
                                }

                                Text {
                                    width: parent.width
                                    text: sectionButton.modelData.description
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.tinyFontSize
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.settingsModel.selectSection(sectionButton.modelData.id)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: sectionList.count === 0
                            text: "No matching sections"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodyFontSize
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    radius: Theme.radius

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: Theme.sectionSpacing

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.tightSpacing

                            Text {
                                text: root.settingsModel.selectedSection().label
                                color: Theme.textStrong
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.titleFontSize
                                font.bold: true
                            }

                            Text {
                                Layout.fillWidth: true
                                text: root.settingsModel.selectedSection().description
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                            }
                        }

                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.border }

                        ListView {
                            id: capabilityList

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: Theme.listSpacing * 2
                            model: root.settingsModel.capabilitiesForSection(root.settingsModel.selectedSectionId)

                            delegate: Rectangle {
                                id: capabilityCard

                                required property var modelData

                                width: capabilityList.width
                                height: 92
                                color: Theme.bg
                                border.color: root.statusColor(capabilityCard.modelData.status)
                                border.width: 1
                                radius: Theme.radius

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    spacing: Theme.tightSpacing

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            Layout.fillWidth: true
                                            text: capabilityCard.modelData.label
                                            color: Theme.textStrong
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.panelFontSize
                                            font.bold: true
                                        }

                                        Text {
                                            text: capabilityCard.modelData.status.toUpperCase()
                                            color: root.statusColor(capabilityCard.modelData.status)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.tinyFontSize
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: capabilityCard.modelData.detail
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.smallFontSize
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: capabilityCard.modelData.capabilityClass + " - " + capabilityCard.modelData.provider
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.tinyFontSize
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: capabilityList.count === 0
                                text: root.settingsModel.discoveryState === "loading"
                                    ? "Discovering capabilities..."
                                    : root.settingsModel.discoveryState === "failure"
                                        ? root.settingsModel.message
                                        : "No capabilities reported for this section"
                                color: root.settingsModel.discoveryState === "failure" ? Theme.danger : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                                wrapMode: Text.WordWrap
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.settingsModel.message
                            color: root.settingsModel.discoveryState === "failure" ? Theme.danger : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.smallFontSize
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Phase 1 is read-only. Unsupported controls are explicit and no Settings action requests elevation."
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tinyFontSize
                horizontalAlignment: Text.AlignRight
            }
        }
    }
}
