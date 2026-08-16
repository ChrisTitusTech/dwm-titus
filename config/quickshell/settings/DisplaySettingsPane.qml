import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var settingsModel
    property string profileName: ""
    property string confirmation: ""

		onVisibleChanged: {
			if (!visible) root.confirmation = "";
		}

    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    clip: true

    ColumnLayout {
        id: contentColumn
        width: root.width
        spacing: Theme.sectionSpacing

        RowLayout {
            Layout.fillWidth: true

            Text {
                Layout.fillWidth: true
                text: root.settingsModel.displayMessage
                color: root.settingsModel.displayState === "failure" ? Theme.danger : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
            }

            ShellButton { label: "Refresh"; enabled: root.settingsModel.displayState !== "loading"; onActivated: root.settingsModel.refreshDisplays() }
            ShellButton { label: "Preview"; enabled: root.settingsModel.displayOutputs.length > 0 && !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.previewDisplay() }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.settingsModel.previewKind === "display" ? Math.max(48, previewRow.implicitHeight + 14) : 0
            visible: root.settingsModel.previewKind === "display"
            color: Theme.surfaceHover
            border.color: Theme.warning
            radius: Theme.radius

            RowLayout {
                id: previewRow
                anchors.fill: parent
                anchors.margins: 7
				Text {
					Layout.fillWidth: true
					text: root.settingsModel.previewSeconds > 0
						? "Preview reverts in " + root.settingsModel.previewSeconds + " seconds"
						: "Automatic rollback failed. Revert retries the captured layout; Keep accepts the current layout."
					color: Theme.textStrong
					font.family: Theme.fontFamily
					wrapMode: Text.WordWrap
				}
				ShellButton { label: root.settingsModel.previewRollbackFailed ? "Accept current" : "Keep"; onActivated: root.settingsModel.keepPreview(root.profileName.trim()) }
                ShellButton { label: "Revert"; danger: true; onActivated: root.settingsModel.revertPreview() }
            }
        }

        Repeater {
            model: root.settingsModel.displayOutputs

            delegate: Rectangle {
                id: outputCard
                required property int index
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 126
                color: Theme.bg
                border.color: outputCard.modelData.enabled ? Theme.accent : Theme.border
                border.width: 1
                radius: Theme.radius

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: Theme.tightSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: outputCard.modelData.name; color: Theme.textStrong; font.family: Theme.fontFamily; font.bold: true }
                        Text {
                            text: outputCard.modelData.fullCompositionPipeline === "available"
                                ? "NVIDIA full composition on persistent install"
                                : (outputCard.modelData.tearfree === "available" ? "TearFree available" : "Anti-tearing unsupported")
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tinyFontSize
                        }
                        ShellButton { label: outputCard.modelData.enabled ? "Enabled" : "Disabled"; onActivated: root.settingsModel.updateDisplay(outputCard.index, "enabled", !outputCard.modelData.enabled) }
                        ShellButton { label: outputCard.modelData.primary ? "Primary" : "Make primary"; enabled: outputCard.modelData.enabled; onActivated: root.settingsModel.updateDisplay(outputCard.index, "primary", true) }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        ShellButton { label: outputCard.modelData.mode + " @ " + outputCard.modelData.rate + " Hz"; enabled: outputCard.modelData.enabled; onActivated: root.settingsModel.cycleDisplayMode(outputCard.index) }
                        ShellButton { label: "Rotation: " + outputCard.modelData.rotation; enabled: outputCard.modelData.enabled; onActivated: root.settingsModel.cycleRotation(outputCard.index) }
                        Text { text: "X"; color: Theme.textMuted; font.family: Theme.fontFamily }
                        Rectangle {
                            Layout.preferredWidth: 72; Layout.preferredHeight: 32; color: Theme.surface; border.color: Theme.border; radius: Theme.radius
                            TextInput {
                                id: xPositionInput
                                anchors.fill: parent
                                anchors.margins: 7
                                color: Theme.textStrong
                                font.family: Theme.fontFamily
                                validator: IntValidator {}
                                onEditingFinished: root.settingsModel.updateDisplay(outputCard.index, "x", Number(text))
                            }
                            Binding {
                                target: xPositionInput
                                property: "text"
                                value: String(outputCard.modelData.x)
                                when: !xPositionInput.activeFocus
                                restoreMode: Binding.RestoreNone
                            }
                        }
                        Text { text: "Y"; color: Theme.textMuted; font.family: Theme.fontFamily }
                        Rectangle {
                            Layout.preferredWidth: 72; Layout.preferredHeight: 32; color: Theme.surface; border.color: Theme.border; radius: Theme.radius
                            TextInput {
                                id: yPositionInput
                                anchors.fill: parent
                                anchors.margins: 7
                                color: Theme.textStrong
                                font.family: Theme.fontFamily
                                validator: IntValidator {}
                                onEditingFinished: root.settingsModel.updateDisplay(outputCard.index, "y", Number(text))
                            }
                            Binding {
                                target: yPositionInput
                                property: "text"
                                value: String(outputCard.modelData.y)
                                when: !yPositionInput.activeFocus
                                restoreMode: Binding.RestoreNone
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Text { text: "Profile"; color: Theme.textMuted; font.family: Theme.fontFamily }
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 36; color: Theme.surface; border.color: Theme.border; radius: Theme.radius
                TextInput { anchors.fill: parent; anchors.margins: 8; text: root.profileName; color: Theme.textStrong; font.family: Theme.fontFamily; onTextChanged: root.profileName = text }
            }
			ShellButton { label: "Save profile"; enabled: root.profileName.trim().length > 0; onActivated: root.settingsModel.saveDisplay(root.profileName.trim()) }
			ShellButton {
				label: "Install persistent"
				enabled: root.settingsModel.displayPersistenceAvailable && root.settingsModel.displayProfiles.indexOf(root.profileName.trim()) >= 0
				onActivated: root.confirmation = "install"
			}
            ShellButton { label: "Rollback system"; danger: true; enabled: root.settingsModel.displayPersistenceAvailable; onActivated: root.confirmation = "rollback" }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.settingsModel.displayPersistenceAvailable
            text: root.settingsModel.displayPersistenceCapability.detail
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.smallFontSize
            wrapMode: Text.WordWrap
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.confirmation ? 66 : 0
            visible: root.confirmation !== ""
            color: Theme.surfaceHover
            border.color: Theme.warning
            radius: Theme.radius
            RowLayout {
                anchors.fill: parent; anchors.margins: 8
                Text {
                    Layout.fillWidth: true
                    text: root.confirmation === "install"
                        ? "Authorize installation of profile '" + root.profileName + "' to the managed Xorg fragment. A backup will be created."
                        : "Authorize restoring the newest managed Xorg backup. This affects the next X11 login."
                    color: Theme.textStrong; font.family: Theme.fontFamily; wrapMode: Text.WordWrap
                }
                ShellButton {
                    label: "Authorize"
                    onActivated: {
						if (root.confirmation === "install") root.settingsModel.installDisplayProfile(root.profileName.trim());
                        else root.settingsModel.rollbackDisplaySystem();
                        root.confirmation = "";
                    }
                }
                ShellButton { label: "Cancel"; onActivated: root.confirmation = "" }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.tightSpacing
            Repeater {
                model: root.settingsModel.displayProfiles
                delegate: ShellButton { required property string modelData; label: "Preview " + modelData; enabled: !root.settingsModel.previewOperationLocked; onActivated: root.settingsModel.previewDisplayProfile(modelData) }
            }
        }

        Repeater {
            model: root.settingsModel.displayUnsupportedProfiles
            delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: "Profile " + modelData.name + ": " + modelData.detail
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }
        }
    }
}
