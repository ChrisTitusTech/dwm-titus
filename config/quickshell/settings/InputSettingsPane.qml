import QtQuick
import QtQuick.Layouts
import qs.core
import "InputOptions.js" as InputOptions

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var settingsModel
    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    clip: true

    ColumnLayout {
        id: contentColumn
        width: root.width
        spacing: Theme.sectionSpacing

        RowLayout {
            Layout.fillWidth: true
            Text { Layout.fillWidth: true; text: root.settingsModel.inputMessage; color: root.settingsModel.inputState === "failure" ? Theme.danger : Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.smallFontSize }
            ShellButton { label: "Refresh"; enabled: root.settingsModel.inputState !== "loading"; onActivated: root.settingsModel.refreshInput() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.settingsModel.previewKind === "input" ? 48 : 0
            visible: root.settingsModel.previewKind === "input"
            color: Theme.controlHoverFill
            border.color: Theme.warning
            radius: Theme.largeSurfaceCardRadius
            RowLayout {
                anchors.fill: parent; anchors.margins: 7
				Text {
					Layout.fillWidth: true
					text: root.settingsModel.previewSeconds > 0
						? "Input preview reverts in " + root.settingsModel.previewSeconds + " seconds"
						: "Automatic rollback needs attention; retry Revert"
					elide: Text.ElideRight
					color: Theme.textStrong
					font.family: Theme.fontFamily
					font.pixelSize: Theme.bodyFontSize
				}
                ShellButton { label: "Keep"; onActivated: root.settingsModel.keepPreview() }
                ShellButton { label: "Revert"; danger: true; onActivated: root.settingsModel.revertPreview() }
            }
        }

        Repeater {
            model: root.settingsModel.inputDevices
            delegate: Rectangle {
                id: deviceCard
                required property var modelData
                property var settings: root.settingsModel.inputSettings.filter(function(setting) { return setting.device === deviceCard.modelData.key; })
                property var unsupported: root.settingsModel.inputUnsupported.filter(function(setting) { return setting.device === deviceCard.modelData.key; })
                property var modifierOptions: deviceCard.settings.filter(function(setting) { return setting.id === "modifier-options"; })[0] || null

                Layout.fillWidth: true
                Layout.preferredHeight: deviceColumn.implicitHeight + 20
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                radius: Theme.largeSurfaceCardRadius

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    color: Theme.accentSecondary
                    radius: 2
                }

                ColumnLayout {
                    id: deviceColumn
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                    anchors.leftMargin: 16; anchors.rightMargin: 10; anchors.topMargin: 10
                    Text { text: deviceCard.modelData.name + " (" + deviceCard.modelData.kind + ")"; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize; font.bold: true }
                    Text {
                        Layout.fillWidth: true
                        visible: deviceCard.modelData.kind === "accessibility"
                        text: "Session-wide XKB controls use a 15-second preview. Keep the change to restore it at the next login."
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: deviceCard.settings
                        delegate: RowLayout {
                            id: settingRow
                            required property var modelData
                            Layout.fillWidth: true
                            property string editValue: modelData.value
                            onModelDataChanged: editValue = modelData.value

                            Text {
                                Layout.preferredWidth: 150
                                Layout.maximumWidth: 150
                                text: settingRow.modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                                wrapMode: Text.WordWrap
                            }
                            ShellButton {
                                visible: settingRow.modelData.type === "boolean"
                                label: settingRow.modelData.value === "1" ? "On" : "Off"
                                accessibleDescription: settingRow.modelData.label + ". Starts a timed preview."
                                enabled: !root.settingsModel.previewOperationLocked
                                onActivated: root.settingsModel.previewInput(deviceCard.modelData.key, settingRow.modelData.id, settingRow.modelData.value === "1" ? "0" : "1")
                            }
                            Rectangle {
                                visible: settingRow.modelData.type !== "boolean"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(Theme.controlRowHeight,
                                    settingInput.implicitHeight + 14)
                                color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                                TextInput { id: settingInput; anchors.fill: parent; anchors.margins: 7; text: settingRow.editValue; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.inputFontSize; onTextEdited: settingRow.editValue = text }
                            }
                            ShellButton { visible: settingRow.modelData.type !== "boolean"; label: "Preview"; accessibleDescription: settingRow.modelData.label; enabled: !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.previewInput(deviceCard.modelData.key, settingRow.modelData.id, settingRow.editValue) }
                            ShellButton { label: "Reset"; accessibleDescription: settingRow.modelData.label; enabled: !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.resetInput(deviceCard.modelData.key, settingRow.modelData.id) }
                        }
                    }
                    // Presets for the layout switch key and LED; each one previews a
                    // modifier-options value with only its grp: or grp_led: part changed.
                    Repeater {
                        model: deviceCard.modifierOptions === null ? [] : [
                            { label: "Switch layout with", prefix: InputOptions.switchPrefix, choices: InputOptions.switchChoices },
                            { label: "Layout LED", prefix: InputOptions.ledPrefix, choices: InputOptions.ledChoices }
                        ]
                        delegate: RowLayout {
                            id: presetRow
                            required property var modelData
                            readonly property string options: deviceCard.modifierOptions === null ? "" : deviceCard.modifierOptions.value
                            readonly property string selected: InputOptions.current(presetRow.options, presetRow.modelData.prefix)
                            Layout.fillWidth: true

                            Text {
                                Layout.preferredWidth: 150
                                Layout.maximumWidth: 150
                                Layout.alignment: Qt.AlignTop
                                text: presetRow.modelData.label
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                                wrapMode: Text.WordWrap
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: Theme.spacingSm
                                Repeater {
                                    model: presetRow.modelData.choices
                                    delegate: ShellButton {
                                        id: presetButton
                                        required property var modelData
                                        label: presetButton.modelData.label
                                        primary: presetButton.modelData.value === presetRow.selected
                                        accessibleDescription: presetRow.modelData.label + " " + presetButton.modelData.label + ". Starts a timed preview."
                                        enabled: !root.settingsModel.previewOperationLocked
                                        onActivated: root.settingsModel.previewInput(deviceCard.modelData.key, "modifier-options",
                                            InputOptions.withChoice(presetRow.options, presetRow.modelData.prefix, presetButton.modelData.value))
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: deviceCard.modifierOptions !== null && text.length > 0
                        text: deviceCard.modifierOptions === null ? "" : InputOptions.hint(deviceCard.modifierOptions.value)
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: deviceCard.unsupported
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.id + ": " + modelData.detail
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tinyFontSize
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.settingsModel.inputDevices.length === 0
            text: root.settingsModel.inputState === "loading" ? "Discovering input devices..." : "No supported XInput devices were found"
            color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize; wrapMode: Text.WordWrap
        }
    }
}
