import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core

pragma ComponentBehavior: Bound

PopupWindow {
    id: root

    required property var controlsModel
    required property var panelWindow

    readonly property int popupWidth: 360
    readonly property int popupHeight: 560
    readonly property int edgeMargin: Theme.rowSpacing
    readonly property int contentSpacing: Theme.popupSpacing
    readonly property int rowSpacing: Theme.rowSpacing
    readonly property int actionButtonHeight: Theme.compactButtonHeight
    readonly property int volumeControlHeight: 46
    readonly property int volumePercentWidth: 42
    readonly property int muteButtonWidth: 84
    readonly property int outputDeviceRowHeight: 34

    visible: controlsModel.visible
    implicitWidth: popupWidth
    implicitHeight: popupHeight
    anchor.window: panelWindow
    anchor.rect.x: Math.max(edgeMargin, panelWindow.width - popupWidth - edgeMargin)
    anchor.rect.y: Theme.panelHeight
    grabFocus: true
    color: Theme.transparent

    onVisibleChanged: {
        if (visible) {
            Qt.callLater(function() {
                content.forceActiveFocus();
            });
        } else {
            root.controlsModel.close();
        }
    }

    function setVolumePendingFromX(x) {
        volumeSlider.pendingPercent = volumeSlider.percentFromX(x);
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

            RowLayout {
                Layout.fillWidth: true
                spacing: root.rowSpacing

                Text {
                    Layout.fillWidth: true
                    text: root.controlsModel.volumeDisplayText
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleFontSize
                    font.bold: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }

                ShellButton {
                    Layout.preferredWidth: implicitWidth
                    Layout.preferredHeight: Theme.buttonHeight
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

            SectionLabel {
                label: "Volume"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: root.rowSpacing

                Item {
                    id: volumeSlider

                    property int pendingPercent: root.controlsModel.volumePercent
                    property int displayPercent: volumeMouse.pressed ? pendingPercent : root.controlsModel.volumePercent

                    Layout.fillWidth: true
                    Layout.preferredHeight: root.volumeControlHeight

                    function percentFromX(x) {
                        return Math.max(0, Math.min(100, Math.round((x / Math.max(1, width)) * 100)));
                    }

                    Rectangle {
                        id: sliderTrack

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 8
                        color: Theme.surface
                        radius: Theme.radius

                        Rectangle {
                            width: Math.round((volumeSlider.displayPercent / 100) * parent.width)
                            height: parent.height
                            color: root.controlsModel.volumeMuted ? Theme.textMuted : Theme.accent
                            radius: parent.radius
                        }
                    }

                    Rectangle {
                        width: 20
                        height: 20
                        x: Math.max(0, Math.min(parent.width - width, Math.round((volumeSlider.displayPercent / 100) * parent.width) - width / 2))
                        y: parent.height / 2 - height / 2
                        color: volumeMouse.enabled ? Theme.text : Theme.textMuted
                        border.color: Theme.border
                        border.width: 1
                        radius: height / 2
                    }

                    MouseArea {
                        id: volumeMouse

                        anchors.fill: parent
                        enabled: !root.controlsModel.busy
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPressed: function(mouse) {
                            root.setVolumePendingFromX(mouse.x);
                        }
                        onPositionChanged: function(mouse) {
                            if (pressed) {
                                root.setVolumePendingFromX(mouse.x);
                            }
                        }
                        onReleased: function(mouse) {
                            root.setVolumePendingFromX(mouse.x);
                            root.controlsModel.volumeSet(volumeSlider.pendingPercent);
                        }
                    }
                }

                Text {
                    Layout.preferredWidth: root.volumePercentWidth
                    text: root.controlsModel.volumePercent + "%"
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
                        color: outputMouse.containsMouse && !outputDeviceRow.modelData.isDefault && !root.controlsModel.busy ? Theme.surfaceHover : Theme.surface
                        border.color: outputDeviceRow.modelData.isDefault ? Theme.accent : Theme.border
                        border.width: 1
                        opacity: root.controlsModel.busy && !outputDeviceRow.modelData.isDefault ? 0.5 : 1

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
                                color: outputDeviceRow.modelData.isDefault ? Theme.accent : Theme.textMuted
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

            SectionLabel {
                label: "Media"
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 54
                color: Theme.surface
                radius: Theme.radius
                border.color: Theme.border
                border.width: 1

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
