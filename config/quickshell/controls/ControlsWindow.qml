import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

ClickAwayPopup {
    id: root

    required property var controlsModel
    required property var panelWindow

    readonly property int cardWidth: 360
    readonly property int cardHeight: 560
    readonly property int edgeMargin: Theme.rowSpacing
    readonly property int contentSpacing: Theme.popupSpacing
    readonly property int rowSpacing: Theme.rowSpacing
    readonly property int actionButtonHeight: Theme.compactButtonHeight
    readonly property int volumeControlHeight: 46
    readonly property int volumePercentWidth: 42
    readonly property int muteButtonWidth: 84
    readonly property int outputDeviceRowHeight: 34

    visible: panelWindow !== null && panelWindow.screen !== null && controlsModel.visible
    targetWindow: panelWindow
    popupWidth: cardWidth
    popupHeight: cardHeight
    popupX: panelWindow ? Math.max(edgeMargin, panelWindow.width - cardWidth - edgeMargin) : edgeMargin
    popupY: Theme.panelHeight
    onDismissed: controlsModel.close()

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                content.forceActiveFocus();
            });
        } else {
            root.controlsModel.close();
        }
    }

    ShellSurface {
        id: content

        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
                root.controlsModel.close();
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: root.contentSpacing

            PanelHero {
                Layout.fillWidth: true
                iconText: root.controlsModel.volumeMuted ? "󰝟" : "󰕾"
                title: "Audio"
                subtitle: root.controlsModel.volumeDisplayText

                ShellButton {
                    label: "Refresh"
                    onActivated: root.controlsModel.refresh()
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.controlsModel.message.length > 0
                text: root.controlsModel.message
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.smallFontSize
                elide: Text.ElideRight
            }

            PanelSeparator {}

            SectionLabel {
                label: "Volume"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.rowSpacing

                PanelSlider {
                    id: volumeSlider

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.volumeControlHeight
                    value: root.controlsModel.volumePercent
                    muted: root.controlsModel.volumeMuted
                    enabled: !root.controlsModel.busy
                    onValueCommitted: value => root.controlsModel.volumeSet(Math.round(value))
                }

                Text {
                    Layout.preferredWidth: root.volumePercentWidth
                    text: Math.round(volumeSlider.dragging ? volumeSlider.liveValue : root.controlsModel.volumePercent) + "%"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.panelFontSize
                    font.bold: true
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }

                ControlsActionButton {
                    Layout.preferredWidth: root.muteButtonWidth
                    Layout.preferredHeight: root.volumeControlHeight
                    label: root.controlsModel.volumeMuted ? "Unmute" : "Mute"
                    enabled: !root.controlsModel.busy
                    onActivated: root.controlsModel.volumeToggleMute()
                }
            }

            SectionLabel {
                label: "Output"
            }

            Text {
                Layout.fillWidth: true
                visible: root.controlsModel.outputDevices.length === 0
                text: "OUTPUT unavailable"
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.panelFontSize
                font.bold: true
                elide: Text.ElideRight
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.compactSpacing
                visible: root.controlsModel.outputDevices.length > 0

                Repeater {
                    model: root.controlsModel.outputDevices

                    Rectangle {
                        id: outputDeviceRow

                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: root.outputDeviceRowHeight
                        radius: Theme.radius
                        color: outputDeviceRow.modelData.isDefault ? Theme.controlSelectedFill
                            : outputMouse.containsMouse && !root.controlsModel.busy ? Theme.controlHoverFill : Theme.controlNormalFill
                        border.color: outputDeviceRow.modelData.isDefault ? Theme.controlSelectedBorder
                            : outputMouse.containsMouse ? Theme.controlHoverBorder : Theme.controlNormalBorder
                        border.width: Theme.controlBorderWidth

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: root.rowSpacing

                            Text {
                                Layout.fillWidth: true
                                text: outputDeviceRow.modelData.description
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.panelFontSize
                                font.bold: outputDeviceRow.modelData.isDefault
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }

                            Text {
                                Layout.preferredWidth: 58
                                text: outputDeviceRow.modelData.isDefault ? "Default" : "Set"
                                color: outputDeviceRow.modelData.isDefault ? Theme.controlSelectedText : Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.smallFontSize
                                font.bold: true
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: outputMouse

                            anchors.fill: parent
                            enabled: !root.controlsModel.busy && !outputDeviceRow.modelData.isDefault
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.controlsModel.outputSetDefault(outputDeviceRow.modelData.name)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.rowSpacing

                SectionLabel {
                    label: "Microphone"
                }

                Text {
                    text: root.controlsModel.micText
                    color: root.controlsModel.micText === "MIC muted" ? Theme.danger : Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.panelFontSize
                    font.bold: true
                }
            }

            PanelSeparator {}

            SectionLabel {
                label: "Media"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                color: Theme.controlNormalFill
                radius: Theme.radius
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: Theme.compactSpacing

                    Text {
                        width: parent.width
                        text: root.controlsModel.mediaText
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.panelFontSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: root.controlsModel.mediaPlayer.length > 0
                        text: root.controlsModel.mediaPlayer
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.smallFontSize
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.listSpacing * 2

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.actionButtonHeight
                    label: "Previous"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaPrevious()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.actionButtonHeight
                    label: "Play/Pause"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaPlayPause()
                }

                ControlsActionButton {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.actionButtonHeight
                    label: "Next"
                    enabled: !root.controlsModel.busy && root.controlsModel.mediaPlayer.length > 0
                    onActivated: root.controlsModel.mediaNext()
                }
            }
        }
    }
}
