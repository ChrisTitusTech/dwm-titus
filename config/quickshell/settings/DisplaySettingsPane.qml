import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var settingsModel
    property string profileName: ""
    property string confirmation: ""

	component DisplayComboBox: Controls.ComboBox {
		id: comboBox

		required property string accessibleLabel
		property string valueSuffix: ""

		implicitHeight: Theme.controlHeight
		activeFocusOnTab: enabled
		displayText: currentIndex >= 0 ? currentText + valueSuffix : ""
		font.family: Theme.fontFamily
		font.pixelSize: Theme.inputFontSize
		palette.button: Theme.controlNormalFill
		palette.buttonText: Theme.controlNormalText
		palette.base: Theme.popupBackground
		palette.window: Theme.popupBackground
		palette.text: Theme.popupText
		palette.highlight: Theme.controlSelectedFill
		palette.highlightedText: Theme.controlSelectedText
		Accessible.name: accessibleLabel

		delegate: Controls.ItemDelegate {
			required property var modelData
			required property int index

			width: comboBox.width
			text: modelData + comboBox.valueSuffix
			font: comboBox.font
			highlighted: comboBox.highlightedIndex === index
			hoverEnabled: comboBox.hoverEnabled
		}
	}

		onVisibleChanged: {
			if (!visible) root.confirmation = "";
		}

    contentWidth: width
    contentHeight: contentColumn.implicitHeight
    clip: true

    ColumnLayout {
        id: contentColumn
        width: root.width
        spacing: Theme.spacingLg

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
            ShellButton {
                label: "Apply changes"
                primary: true
                enabled: root.settingsModel.displayHasPendingChanges && !root.settingsModel.previewOperationLocked
                onActivated: root.settingsModel.previewDisplay()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.settingsModel.previewKind === "display" ? Math.max(48, previewRow.implicitHeight + 14) : 0
            visible: root.settingsModel.previewKind === "display"
            color: Theme.controlHoverFill
            border.color: Theme.warning
            radius: Theme.largeSurfaceCardRadius

            RowLayout {
                id: previewRow
                anchors.fill: parent
                anchors.margins: 7
				Text {
					Layout.fillWidth: true
					text: root.settingsModel.previewSeconds > 0
						? "Keep these display settings? Reverting in " + root.settingsModel.previewSeconds + " seconds."
						: "Could not restore the previous layout automatically. Revert retries it; Keep current accepts this layout."
					color: Theme.textStrong
					font.family: Theme.fontFamily
					font.pixelSize: Theme.bodyFontSize
					wrapMode: Text.WordWrap
				}
				ShellButton {
					label: root.settingsModel.previewRollbackFailed ? "Keep current" : "Keep changes"
					primary: true
					onActivated: root.settingsModel.keepPreview(root.profileName.trim())
				}
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
                Layout.preferredHeight: Math.max(88, outputContent.implicitHeight + 12)
                color: Theme.controlNormalFill
                border.color: outputCard.modelData.enabled ? Theme.controlSelectedBorder : Theme.controlNormalBorder
                border.width: 1
                radius: Theme.largeSurfaceCardRadius

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 4
                    color: outputCard.modelData.enabled ? Theme.accentSecondary : Theme.menuMutedText
                    radius: 2
                }

                ColumnLayout {
                    id: outputContent

                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    anchors.topMargin: 6
                    anchors.bottomMargin: 6
                    spacing: Theme.tightSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        Text { Layout.fillWidth: true; text: outputCard.modelData.name; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize; font.bold: true }
                        Text {
                            text: outputCard.modelData.fullCompositionPipeline === "available"
                                ? "NVIDIA anti-tearing available at next login"
                                : (outputCard.modelData.tearfree === "available" ? "TearFree available" : "Anti-tearing unsupported")
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.tinyFontSize
                        }
                        ShellButton { label: outputCard.modelData.enabled ? "Enabled" : "Disabled"; onActivated: root.settingsModel.updateDisplay(outputCard.index, "enabled", !outputCard.modelData.enabled) }
                        ShellButton { label: outputCard.modelData.primary ? "Primary" : "Make primary"; enabled: outputCard.modelData.enabled; onActivated: root.settingsModel.updateDisplay(outputCard.index, "primary", true) }
                    }

                    Flow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: Theme.tightSpacing

                        Row {
                            spacing: Theme.tightSpacing

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Resolution"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                            }
                            DisplayComboBox {
                                id: resolutionSelector

                                width: 180
                                accessibleLabel: "Resolution for " + outputCard.modelData.name
                                enabled: outputCard.modelData.enabled
                                model: root.settingsModel.displayResolutionChoices(outputCard.index)
                                currentIndex: root.settingsModel.displayResolutionIndex(outputCard.index)
                                onActivated: function(index) {
                                    root.settingsModel.setDisplayResolution(outputCard.index, model[index]);
                                }
                            }
                        }

                        Row {
                            spacing: Theme.tightSpacing

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Refresh rate"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                            }
                            DisplayComboBox {
                                id: refreshRateSelector

                                readonly property var rateChoices: root.settingsModel.displayRefreshRateChoices(outputCard.index)

                                width: 110
                                accessibleLabel: "Refresh rate for " + outputCard.modelData.name
                                enabled: outputCard.modelData.enabled
                                visible: rateChoices.length > 1
                                model: rateChoices
                                currentIndex: root.settingsModel.displayRefreshRateIndex(outputCard.index)
                                valueSuffix: " Hz"
                                onActivated: function(index) {
                                    root.settingsModel.setDisplayRefreshRate(outputCard.index, model[index]);
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: refreshRateSelector.rateChoices.length <= 1
                                text: outputCard.modelData.rate + " Hz"
                                color: outputCard.modelData.enabled ? Theme.textStrong : Theme.controlDisabledText
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.bodyFontSize
                            }
                        }
                        ShellButton { label: "Rotation: " + outputCard.modelData.rotation; enabled: outputCard.modelData.enabled; onActivated: root.settingsModel.cycleRotation(outputCard.index) }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "X"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize }
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: Math.max(Theme.controlHeight,
                                xPositionInput.implicitHeight + 10)
                            color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                            TextInput {
                                id: xPositionInput
                                anchors.fill: parent
                                anchors.margins: 5
                                color: Theme.textStrong
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.inputFontSize
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
                        Text { text: "Y"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize }
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: Math.max(Theme.controlHeight,
                                yPositionInput.implicitHeight + 10)
                            color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                            TextInput {
                                id: yPositionInput
                                anchors.fill: parent
                                anchors.margins: 5
                                color: Theme.textStrong
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.inputFontSize
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
            Text { text: "Layout name"; color: Theme.textMuted; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(Theme.controlHeight,
                    profileNameInput.implicitHeight + 12)
                color: Theme.controlNormalFill; border.color: Theme.controlNormalBorder; radius: Theme.controlRadius
                TextInput { id: profileNameInput; anchors.fill: parent; anchors.margins: 6; text: root.profileName; color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.inputFontSize; onTextChanged: root.profileName = text }
            }
			ShellButton { label: "Save layout"; enabled: root.profileName.trim().length > 0; onActivated: root.settingsModel.saveDisplay(root.profileName.trim()) }
			ShellButton {
				label: "Use at next login"
				enabled: root.settingsModel.displayPersistenceAvailable && root.settingsModel.displayProfiles.indexOf(root.profileName.trim()) >= 0
				onActivated: root.confirmation = "install"
			}
            ShellButton { label: "Restore login backup"; danger: true; enabled: root.settingsModel.displayPersistenceAvailable; onActivated: root.confirmation = "rollback" }
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
            Layout.preferredHeight: root.confirmation ? confirmationRow.implicitHeight + 16 : 0
            visible: root.confirmation !== ""
            color: Theme.controlHoverFill
            border.color: Theme.warning
            radius: Theme.largeSurfaceCardRadius
            RowLayout {
                id: confirmationRow
                anchors.fill: parent; anchors.margins: 8
                Text {
                    Layout.fillWidth: true
                    text: root.confirmation === "install"
                        ? "Use saved layout '" + root.profileName + "' automatically at the next login? Administrator approval is required; the previous dwm-titus next-login layout will be backed up."
                        : "Restore the previous dwm-titus next-login layout? Administrator approval is required. This changes the next login only."
                    color: Theme.textStrong; font.family: Theme.fontFamily; font.pixelSize: Theme.bodyFontSize; wrapMode: Text.WordWrap
                }
                ShellButton {
                    label: root.confirmation === "install" ? "Use at next login" : "Restore backup"
                    primary: root.confirmation === "install"
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
                delegate: ShellButton {
                    required property string modelData
                    label: "Try " + modelData
                    enabled: !root.settingsModel.previewOperationLocked
                    onActivated: root.settingsModel.previewDisplayProfile(modelData)
                }
            }
        }

        Repeater {
            model: root.settingsModel.displayUnsupportedProfiles
            delegate: Text {
                required property var modelData
                Layout.fillWidth: true
                text: "Saved layout " + modelData.name + ": " + modelData.detail
                color: Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                wrapMode: Text.WordWrap
            }
        }
    }
}
