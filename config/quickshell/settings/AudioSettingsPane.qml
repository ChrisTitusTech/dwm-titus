import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var controlsModel
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true

            UiText {
                Layout.fillWidth: true
                text: root.controlsModel.audioProviderState === "available"
                    ? "PipeWire / " + root.controlsModel.audioSourceKind
                    : root.controlsModel.audioProviderDetail
                color: root.controlsModel.audioProviderState === "available" ? Theme.menuText : Theme.warning
                font.bold: true
                elide: Text.ElideRight
            }

            ShellButton {
                label: "Refresh"
                enabled: !root.controlsModel.busy
                onActivated: root.controlsModel.refresh()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.controlsModel.message.length > 0
            text: root.controlsModel.message
            color: Theme.danger
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Output devices" }

        Repeater {
            model: root.controlsModel.outputDevices
            delegate: Rectangle {
                id: outputRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 46
                color: Theme.controlNormalFill
                border.color: outputRow.modelData.isDefault ? Theme.controlSelectedBorder : Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    UiText { Layout.fillWidth: true; text: outputRow.modelData.description; elide: Text.ElideRight }
                    ShellButton {
                        label: outputRow.modelData.isDefault ? "Default" : "Set Default"
                        enabled: !outputRow.modelData.isDefault && !root.controlsModel.busy
                        onActivated: root.controlsModel.outputSetDefault(outputRow.modelData.name, "settings")
                    }
                }
            }
        }

        SectionLabel { label: "Input devices and microphone" }

        Repeater {
            model: root.controlsModel.inputDevices
            delegate: Rectangle {
                id: inputRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                color: Theme.controlNormalFill
                border.color: inputRow.modelData.isDefault ? Theme.controlSelectedBorder : Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    RowLayout {
                        Layout.fillWidth: true
                        UiText { Layout.fillWidth: true; text: inputRow.modelData.description; elide: Text.ElideRight }
                        ShellButton {
                            label: inputRow.modelData.isDefault ? "Default" : "Set"
                            enabled: !inputRow.modelData.isDefault && !root.controlsModel.busy
                            onActivated: root.controlsModel.inputSetDefault(inputRow.modelData.name, "settings")
                        }
                        ShellButton {
                            label: inputRow.modelData.muted ? "Unmute" : "Mute"
                            enabled: !root.controlsModel.busy
                            onActivated: root.controlsModel.inputToggleMute(inputRow.modelData.name, "settings")
                        }
                    }
                    PanelSlider {
                        Layout.fillWidth: true
                        value: inputRow.modelData.volume
                        muted: inputRow.modelData.muted
                        enabled: !root.controlsModel.busy
                        onValueCommitted: value => root.controlsModel.inputVolumeSet(inputRow.modelData.name, value, "settings")
                    }
                }
            }
        }

        SectionLabel { label: "Application streams" }

        UiText {
            visible: root.controlsModel.audioStreams.length === 0
            text: "No active application streams"
            color: Theme.menuMutedText
        }

        Repeater {
            model: root.controlsModel.audioStreams
            delegate: Rectangle {
                id: streamRow
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingSm
                    RowLayout {
                        Layout.fillWidth: true
                        UiText {
                            Layout.fillWidth: true
                            text: streamRow.modelData.application + " / " + streamRow.modelData.description
                            elide: Text.ElideRight
                        }
                        ShellButton {
                            label: streamRow.modelData.muted ? "Unmute" : "Mute"
                            enabled: !root.controlsModel.busy
                            onActivated: root.controlsModel.streamToggleMute(streamRow.modelData.index, "settings")
                        }
                    }
                    PanelSlider {
                        Layout.fillWidth: true
                        value: streamRow.modelData.volume
                        muted: streamRow.modelData.muted
                        enabled: !root.controlsModel.busy
                        onValueCommitted: value => root.controlsModel.streamVolumeSet(streamRow.modelData.index, value, "settings")
                    }
                }
            }
        }
    }
}
