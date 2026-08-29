import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

FloatingWindow {
    id: root

    required property var settingsModel
    required property var networkModel
    required property var bluetoothModel
    required property var controlsModel
    required property var powerModel
    required property var powerMenuModel
    required property var defaultsModel
    required property var autostartModel
    required property var appearanceModel
    required property var panelSettingsModel

    title: "dwm settings"
    visible: settingsModel.visible
    screen: settingsModel.targetScreen
    implicitWidth: Math.min(1180, root.screen ? Math.max(1, root.screen.width - 32) : 1180)
    implicitHeight: Math.min(760, root.screen ? Math.max(1, root.screen.height - 32) : 760)
    color: Theme.transparent

    function statusColor(status) {
        if (status === "available") return Theme.success;
        if (status === "partial" || status === "restricted") return Theme.warning;
        if (status === "unavailable") return Theme.danger;
        return Theme.menuMutedText;
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

    ShellSurface {
        anchors.fill: parent
        margin: Theme.largeSurfaceMargin

        Item {
            anchors.fill: parent
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.settingsModel.close();
                    event.accepted = true;
                }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacingXl

                LargeSurfaceHeader {
                    Layout.fillWidth: true
                    eyebrow: "Desktop configuration"
                    title: "Settings"
                    subtitle: root.settingsModel.platformName + " / common desktop controls"
                    status: root.settingsModel.busy ? "discovering" : root.settingsModel.discoveryState
                    statusColor: root.settingsModel.discoveryState === "failure" ? Theme.danger : Theme.accent

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
                    Layout.preferredHeight: Theme.largeSurfaceSearchHeight
                    color: settingsSearch.activeFocus ? Theme.controlFocusFill : Theme.controlNormalFill
                    border.color: settingsSearch.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
                    border.width: settingsSearch.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
                    radius: Theme.largeSurfaceCardRadius

                    UiText {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "/"
                        color: settingsSearch.activeFocus ? Theme.menuActionText : Theme.menuMutedText
                        font.bold: true
                    }

                    TextInput {
                        id: settingsSearch

                        anchors.fill: parent
                        anchors.leftMargin: 38
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.controlFocusText
                        selectionColor: Theme.accent
                        selectedTextColor: Theme.accentText
                        text: root.settingsModel.searchQuery
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.inputFontSize
                        clip: true

                        onTextChanged: root.settingsModel.setSearch(text)

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Down) {
                                root.settingsModel.selectRelative(1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up) {
                                root.settingsModel.selectRelative(-1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (root.settingsModel.filteredSections.length > 0) {
                                    root.settingsModel.selectSection(root.settingsModel.filteredSections[root.settingsModel.selectedIndex].id);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                root.settingsModel.close();
                                event.accepted = true;
                            }
                        }
                    }

                    UiText {
                        anchors.left: parent.left
                        anchors.leftMargin: 38
                        anchors.verticalCenter: parent.verticalCenter
                        visible: settingsSearch.text.length === 0
                        text: "Search settings sections"
                        color: Theme.placeholder
                        font.pixelSize: Theme.inputFontSize
                    }

                    UiText {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        visible: settingsSearch.text.length === 0
                        text: "UP/DOWN NAVIGATE  ENTER SELECT"
                        color: Theme.menuMutedText
                        font.pixelSize: Theme.fontCaptionSize
                        font.bold: true
                        font.letterSpacing: 0.8
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Theme.spacingXl

                    Rectangle {
                        Layout.preferredWidth: 232
                        Layout.fillHeight: true
                        color: Theme.menuBackground
                        border.color: Theme.popupBorder
                        border.width: Theme.controlBorderWidth
                        radius: Theme.largeSurfaceCardRadius

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingLg
                            spacing: Theme.spacingMd

                            SectionLabel {
                                label: "Sections"
                            }

                            ListView {
                                id: sectionList

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: Theme.spacingXxs
                                model: root.settingsModel.filteredSections

                                delegate: Rectangle {
                                    id: sectionButton

                                    required property int index
                                    required property var modelData
                                    readonly property bool selected: root.settingsModel.selectedSectionId === modelData.id

                                    width: sectionList.width
                                    height: 44
                                    color: selected ? Theme.menuSelectedBackground
                                        : sectionMouse.containsMouse ? Theme.menuHoverBackground : Theme.transparent
                                    border.color: selected ? Theme.controlSelectedBorder : Theme.transparent
                                    border.width: Theme.controlBorderWidth
                                    radius: Theme.controlRadius

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        height: parent.height - 14
                                        visible: sectionButton.selected
                                        color: Theme.accentSecondary
                                        radius: 2
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 8
                                        spacing: Theme.spacingMd

                                        UiText {
                                            text: String(sectionButton.index + 1).padStart(2, "0")
                                            color: sectionButton.selected ? Theme.menuActionText : Theme.menuMutedText
                                            font.pixelSize: Theme.fontCaptionSize
                                            font.bold: true
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.spacingXxs

                                            UiText {
                                                Layout.fillWidth: true
                                                text: sectionButton.modelData.label
                                                color: sectionButton.selected ? Theme.menuSelectedText : Theme.menuText
                                                font.pixelSize: Theme.fontBodySize
                                                font.bold: sectionButton.selected
                                                elide: Text.ElideRight
                                            }

                                            UiText {
                                                Layout.fillWidth: true
                                                text: sectionButton.modelData.description
                                                color: Theme.menuMutedText
                                                font.pixelSize: Theme.fontCaptionSize
                                                elide: Text.ElideRight
                                            }
                                        }

                                        UiText {
                                            visible: sectionButton.selected
                                            text: ">"
                                            color: Theme.menuActionText
                                            font.bold: true
                                        }
                                    }

                                    MouseArea {
                                        id: sectionMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.settingsModel.selectSection(sectionButton.modelData.id)
                                    }
                                }

                                UiText {
                                    parent: sectionList
                                    anchors.centerIn: parent
                                    visible: sectionList.count === 0
                                    text: "No matching sections"
                                    color: Theme.menuMutedText
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Theme.menuBackground
                        border.color: Theme.popupBorder
                        border.width: Theme.controlBorderWidth
                        radius: Theme.largeSurfaceCardRadius

                        ColumnLayout {
                            id: sectionContent

                            anchors.fill: parent
                            anchors.margins: Theme.spacingLg
                            spacing: Theme.spacingMd

                            RowLayout {
                                id: sectionHeader

                                Layout.fillWidth: true
                                spacing: Theme.spacingLg

                                UiText {
                                    text: root.settingsModel.selectedSection().label
                                    color: Theme.popupText
                                    font.pixelSize: Theme.fontTitleSize
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                UiText {
                                    Layout.fillWidth: true
                                    text: root.settingsModel.selectedSection().description
                                    color: Theme.menuMutedText
                                    font.pixelSize: Theme.fontBodySmallSize
                                    elide: Text.ElideRight
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1
                                color: Theme.popupBorder
                            }

                            DisplaySettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "displays"
                                settingsModel: root.settingsModel
                            }

                            InputSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "input"
                                settingsModel: root.settingsModel
                            }

                            NetworkSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "network"
                                networkModel: root.networkModel
                            }

                            BluetoothSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "bluetooth"
                                bluetoothModel: root.bluetoothModel
                            }

                            AudioSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "audio"
                                controlsModel: root.controlsModel
                            }

                            PowerSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "power"
                                powerModel: root.powerModel
                                powerMenuModel: root.powerMenuModel
                            }

                            DefaultsSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "defaults"
                                defaultsModel: root.defaultsModel
                                autostartModel: root.autostartModel
                            }

                            AppearanceSettingsPane {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId === "appearance"
                                appearanceModel: root.appearanceModel
                                panelSettingsModel: root.panelSettingsModel
                                capabilities: root.settingsModel.capabilitiesForSection("appearance")
                                    .filter(function(capability) {
                                        return capability.id !== "themes" && capability.id !== "wallpaper";
                                    })
                            }

                            ListView {
                                id: capabilityList

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                visible: root.settingsModel.selectedSectionId !== "displays"
                                    && root.settingsModel.selectedSectionId !== "input"
                                    && root.settingsModel.selectedSectionId !== "network"
                                    && root.settingsModel.selectedSectionId !== "bluetooth"
                                    && root.settingsModel.selectedSectionId !== "audio"
                                    && root.settingsModel.selectedSectionId !== "power"
                                    && root.settingsModel.selectedSectionId !== "defaults"
                                    && root.settingsModel.selectedSectionId !== "appearance"
                                clip: true
                                spacing: Theme.spacingSm
                                model: root.settingsModel.capabilitiesForSection(root.settingsModel.selectedSectionId)

                                delegate: Rectangle {
                                    id: capabilityCard

                                    required property var modelData
                                    readonly property color stateColor: root.statusColor(modelData.status)

                                    width: capabilityList.width
                                    height: Math.max(68, cardColumn.implicitHeight + 12)
                                    color: Theme.controlNormalFill
                                    border.color: Theme.controlNormalBorder
                                    border.width: Theme.controlBorderWidth
                                    radius: Theme.largeSurfaceCardRadius

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 4
                                        color: capabilityCard.stateColor
                                        radius: 2
                                    }

                                    ColumnLayout {
                                        id: cardColumn

                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: Theme.spacingXs

                                        RowLayout {
                                            Layout.fillWidth: true

                                            UiText {
                                                Layout.fillWidth: true
                                                text: capabilityCard.modelData.label
                                                color: Theme.controlNormalText
                                                font.pixelSize: Theme.fontBodySize
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                implicitWidth: capabilityStatus.implicitWidth + (Theme.controlPaddingX * 2)
                                                implicitHeight: Theme.pillHeight
                                                color: Theme.transparent
                                                border.color: capabilityCard.stateColor
                                                border.width: Theme.controlBorderWidth
                                                radius: Theme.pillRadius

                                                UiText {
                                                    id: capabilityStatus
                                                    anchors.centerIn: parent
                                                    text: capabilityCard.modelData.status.toUpperCase()
                                                    color: capabilityCard.stateColor
                                                    font.pixelSize: Theme.fontCaptionSize
                                                    font.bold: true
                                                }
                                            }
                                        }

                                        UiText {
                                            Layout.fillWidth: true
                                            text: capabilityCard.modelData.detail
                                            color: Theme.menuText
                                            font.pixelSize: Theme.fontBodySmallSize
                                            wrapMode: Text.WordWrap
                                        }

                                        UiText {
                                            Layout.fillWidth: true
                                            text: capabilityCard.modelData.capabilityClass.toUpperCase()
                                                + " / " + capabilityCard.modelData.provider
                                            color: Theme.menuMutedText
                                            font.pixelSize: Theme.fontCaptionSize
                                            font.letterSpacing: 0.5
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                UiText {
                                    parent: capabilityList
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: capabilityList.count === 0
                                    text: root.settingsModel.discoveryState === "loading"
                                        ? "Discovering capabilities..."
                                        : root.settingsModel.discoveryState === "failure"
                                            ? root.settingsModel.message
                                            : "No capabilities reported for this section"
                                    color: root.settingsModel.discoveryState === "failure" ? Theme.danger : Theme.menuMutedText
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                }
                            }

                            UiText {
                                Layout.fillWidth: true
                                text: root.settingsModel.message
                                color: root.settingsModel.discoveryState === "failure" ? Theme.danger : Theme.menuMutedText
                                font.pixelSize: Theme.fontBodySmallSize
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                UiText {
                    Layout.fillWidth: true
                    text: "PREVIEWS REVERT AUTOMATICALLY UNLESS EXPLICITLY KEPT"
                    color: Theme.menuMutedText
                    font.pixelSize: Theme.fontCaptionSize
                    font.bold: true
                    font.letterSpacing: 0.7
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
