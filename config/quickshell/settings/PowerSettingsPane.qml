import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var powerModel
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    function statusColor(state) {
        if (state === "available") return Theme.success;
        if (state === "partial" || state === "restricted") return Theme.warning;
        if (state === "unavailable") return Theme.danger;
        return Theme.menuMutedText;
    }

    function formatDuration(seconds) {
        if (seconds >= 3600 && seconds % 3600 === 0) return (seconds / 3600) + "h";
        if (seconds >= 60 && seconds % 60 === 0) return (seconds / 60) + "m";
        return seconds + "s";
    }

    component StatusCard: Rectangle {
        id: statusCard
        required property string label
        required property string statusState
        required property string detail
        property string value: ""

        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(70, statusColumn.implicitHeight + Theme.spacingLg * 2)
        color: Theme.controlNormalFill
        border.color: root.statusColor(statusState)
        border.width: Theme.controlBorderWidth
        radius: Theme.controlRadius

        ColumnLayout {
            id: statusColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingLg
            spacing: Theme.spacingXs

            RowLayout {
                Layout.fillWidth: true
                UiText {
                    Layout.fillWidth: true
                    text: statusCard.label
                    color: Theme.controlNormalText
                    font.bold: true
                    elide: Text.ElideRight
                }
                UiText {
                    visible: statusCard.value.length > 0
                    text: statusCard.value
                    color: root.statusColor(statusCard.statusState)
                    font.bold: true
                }
            }
            UiText {
                Layout.fillWidth: true
                text: statusCard.detail
                color: Theme.menuMutedText
                wrapMode: Text.WordWrap
            }
        }
    }

    component TimeoutButton: ShellButton {
        required property var preset
        property bool selected: false
        label: preset.label + (selected ? " / Active" : "")
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: root.powerModel.providerState === "available"
                    ? root.powerModel.providerDetail : "Power provider: " + root.powerModel.providerState
                color: root.statusColor(root.powerModel.providerState)
                font.bold: true
                elide: Text.ElideRight
            }
            ShellButton {
                label: root.powerModel.busy ? "Applying..." : "Refresh"
                enabled: !root.powerModel.busy
                onActivated: root.powerModel.refresh()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.powerModel.messageFor("settings").length > 0
            text: root.powerModel.messageFor("settings")
            color: root.powerModel.messageFor("settings") === "Power setting updated" ? Theme.success : Theme.danger
            wrapMode: Text.WordWrap
        }

        SectionLabel { label: "Battery and external power" }

        StatusCard {
            label: root.powerModel.batteryAvailable ? "Battery" : "Battery unavailable"
            statusState: root.powerModel.batteryAvailable ? "available" : "unavailable"
            value: root.powerModel.batteryAvailable ? root.powerModel.batteryPercent + "%" : ""
            detail: root.powerModel.batteryAvailable
                ? root.powerModel.batteryStatus + " / " + root.powerModel.batteryDetail
                : root.powerModel.batteryDetail
        }

        StatusCard {
            label: "External power"
            statusState: root.powerModel.externalPowerState === "unknown" ? "unavailable" : "available"
            value: root.powerModel.externalPowerState === "on" ? "Connected"
                : root.powerModel.externalPowerState === "off" ? "Disconnected" : "Unknown"
            detail: root.powerModel.externalPowerDetail
        }

        SectionLabel { label: "Power profile" }

        UiText {
            Layout.fillWidth: true
            visible: root.powerModel.profileState !== "available"
            text: root.powerModel.profileDetail
            color: root.statusColor(root.powerModel.profileState)
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.powerModel.profileState === "available"
            spacing: Theme.spacingSm

            Repeater {
                model: root.powerModel.profiles
                delegate: ShellButton {
                    id: profileButton
                    required property var modelData
                    Layout.fillWidth: true
                    label: profileButton.modelData.id + (profileButton.modelData.active ? " / Active" : "")
                    enabled: !profileButton.modelData.active && !root.powerModel.busy
                    onActivated: root.powerModel.setProfile(profileButton.modelData.id, "settings")
                }
            }
        }

        SectionLabel { label: "Display power" }

        StatusCard {
            label: root.powerModel.dpmsEnabled ? "Screen timeout enabled" : "Screen timeout disabled"
            statusState: root.powerModel.dpmsState
            value: root.powerModel.dpmsEnabled ? root.formatDuration(root.powerModel.dpmsTimeout) : "Off"
            detail: root.powerModel.dpmsDetail
        }

        RowLayout {
            Layout.fillWidth: true
            ShellButton {
                label: root.powerModel.dpmsEnabled ? "Disable DPMS" : "Enable DPMS"
                enabled: root.powerModel.dpmsAvailable && !root.powerModel.busy
                onActivated: root.powerModel.setDpms(!root.powerModel.dpmsEnabled, "settings")
            }
            Repeater {
                model: root.powerModel.timeoutPresets
                delegate: TimeoutButton {
                    id: dpmsPreset
                    required property var modelData
                    preset: dpmsPreset.modelData
                    selected: root.powerModel.dpmsEnabled
                        && root.powerModel.dpmsTimeout === dpmsPreset.modelData.seconds
                    enabled: root.powerModel.dpmsAvailable && !root.powerModel.busy
                    onActivated: root.powerModel.setDpmsTimeout(dpmsPreset.modelData.seconds, "settings")
                }
            }
        }

        SectionLabel { label: "Automatic locking" }

        StatusCard {
            label: root.powerModel.lockEnabled ? "Automatic lock enabled" : "Automatic lock disabled"
            statusState: root.powerModel.lockState
            value: root.powerModel.lockEnabled ? root.formatDuration(root.powerModel.lockTimeout) : "Off"
            detail: root.powerModel.lockDetail + (root.powerModel.lockRunning ? " / locker running" : "")
        }

        RowLayout {
            Layout.fillWidth: true
            ShellButton {
                label: root.powerModel.lockEnabled ? "Disable Auto Lock" : "Enable Auto Lock"
                enabled: root.powerModel.lockAvailable && !root.powerModel.busy
                onActivated: root.powerModel.setLock(!root.powerModel.lockEnabled, "settings")
            }
            Repeater {
                model: root.powerModel.timeoutPresets
                delegate: TimeoutButton {
                    id: lockPreset
                    required property var modelData
                    preset: lockPreset.modelData
                    selected: root.powerModel.lockEnabled
                        && root.powerModel.lockTimeout === lockPreset.modelData.seconds
                    enabled: root.powerModel.lockAvailable && !root.powerModel.busy
                    onActivated: root.powerModel.setLockTimeout(lockPreset.modelData.seconds, "settings")
                }
            }
        }

        SectionLabel { label: "Suspend and lid behavior" }

        StatusCard {
            label: "Suspend"
            statusState: root.powerModel.suspendState
            value: root.powerModel.suspendCapabilityClass
            detail: root.powerModel.suspendDetail
        }

        StatusCard {
            label: root.powerModel.lidState === "available" ? "Laptop lid" : "Laptop lid unavailable"
            statusState: root.powerModel.lidState
            value: root.powerModel.lidPosition
            detail: root.powerModel.lidDetail
        }

        StatusCard {
            label: "Lid policy"
            statusState: root.powerModel.lidPolicyState
            value: root.powerModel.lidPolicyCapabilityClass
            detail: root.powerModel.lidPolicyDetail + " / battery: " + root.powerModel.lidPolicy
                + ", external power: " + root.powerModel.lidExternalPowerPolicy
                + ", docked: " + root.powerModel.lidDockedPolicy
        }
    }
}
