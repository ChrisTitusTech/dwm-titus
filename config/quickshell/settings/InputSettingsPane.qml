import QtQuick
import QtQuick.Layouts
import qs.core

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
            color: Theme.surfaceHover
            border.color: Theme.warning
            radius: Theme.radius
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
				}
                ShellButton { label: "Keep"; onActivated: root.settingsModel.keepPreview("") }
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

                Layout.fillWidth: true
                Layout.preferredHeight: deviceColumn.implicitHeight + 20
                color: Theme.bg
                border.color: Theme.border
                radius: Theme.radius

                ColumnLayout {
                    id: deviceColumn
                    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                    Text { text: deviceCard.modelData.name + " (" + deviceCard.modelData.kind + ")"; color: Theme.textStrong; font.family: Theme.fontFamily; font.bold: true }
                    Repeater {
                        model: deviceCard.settings
                        delegate: RowLayout {
                            id: settingRow
                            required property var modelData
                            Layout.fillWidth: true
                            property string editValue: modelData.value
                            onModelDataChanged: editValue = modelData.value

                            Text { Layout.preferredWidth: 150; text: settingRow.modelData.label; color: Theme.text; font.family: Theme.fontFamily }
                            ShellButton {
                                visible: settingRow.modelData.type === "boolean"
                                label: settingRow.modelData.value === "1" ? "On" : "Off"
                                enabled: !root.settingsModel.previewOperationLocked
                                onActivated: root.settingsModel.previewInput(deviceCard.modelData.key, settingRow.modelData.id, settingRow.modelData.value === "1" ? "0" : "1")
                            }
                            Rectangle {
                                visible: settingRow.modelData.type !== "boolean"
                                Layout.fillWidth: true; Layout.preferredHeight: 32; color: Theme.surface; border.color: Theme.border; radius: Theme.radius
                                TextInput { anchors.fill: parent; anchors.margins: 7; text: settingRow.editValue; color: Theme.textStrong; font.family: Theme.fontFamily; onTextEdited: settingRow.editValue = text }
                            }
                            ShellButton { visible: settingRow.modelData.type !== "boolean"; label: "Preview"; enabled: !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.previewInput(deviceCard.modelData.key, settingRow.modelData.id, settingRow.editValue) }
                            ShellButton { label: "Reset"; enabled: !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.resetInput(deviceCard.modelData.key, settingRow.modelData.id) }
                        }
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
            color: Theme.textMuted; font.family: Theme.fontFamily; wrapMode: Text.WordWrap
        }
    }
}
