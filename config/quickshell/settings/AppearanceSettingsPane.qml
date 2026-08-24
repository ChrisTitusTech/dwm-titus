import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var appearanceModel
    required property var capabilities
    property string selectedThemeId: ""
    readonly property var selectedTheme: root.appearanceModel.themeById(root.selectedThemeId)
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true

    function statusColor(state) {
        if (state === "available") return Theme.success;
        if (state === "partial" || state === "restricted") return Theme.warning;
        if (state === "unavailable" || state === "failed") return Theme.danger;
        return Theme.menuMutedText;
    }

    function displayName(value) {
        if (!value || value.length === 0) return "Unknown";
        return value.charAt(0).toUpperCase() + value.substring(1).replace(/-/g, " ");
    }

    function ensureSelection() {
        if (root.appearanceModel.themeById(root.selectedThemeId)) return;
        let preferred = root.appearanceModel.activeTheme;
        if (!root.appearanceModel.themeById(preferred))
            preferred = root.appearanceModel.resolvedTheme;
        if (root.appearanceModel.themeById(preferred)) root.selectedThemeId = preferred;
        else if (root.appearanceModel.themes.length > 0)
            root.selectedThemeId = root.appearanceModel.themes[0].id;
    }

    onVisibleChanged: if (visible) root.ensureSelection()
    Component.onCompleted: root.ensureSelection()

    Connections {
        target: root.appearanceModel
        function onThemesChanged() { root.ensureSelection(); }
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

    ColumnLayout {
        id: content
        width: root.width
        spacing: Theme.spacingLg

        RowLayout {
            Layout.fillWidth: true
            UiText {
                Layout.fillWidth: true
                text: root.appearanceModel.applicationState === "available"
                    ? "Selected appearance is fully applied"
                    : root.appearanceModel.applicationState === "partial"
                        ? "Selected appearance is only partially applied"
                        : root.appearanceModel.providerDetail
                color: root.statusColor(root.appearanceModel.applicationState)
                font.bold: true
                elide: Text.ElideRight
            }
            ShellButton {
                label: root.appearanceModel.busy ? "Working..." : "Refresh"
                enabled: !root.appearanceModel.busy
                onActivated: root.appearanceModel.refreshAll()
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.appearanceModel.message.length > 0
            text: root.appearanceModel.message
            color: root.appearanceModel.messageSeverity === "success" ? Theme.success
                : root.appearanceModel.messageSeverity === "warning" ? Theme.warning
                    : root.appearanceModel.messageSeverity === "danger" ? Theme.danger
                        : Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        StatusCard {
            visible: !root.appearanceModel.mutationReady
            label: "Theme changes are read-only"
            statusState: "restricted"
            value: "Protected"
            detail: "Inventory and active colors remain available, but a theme source or integration path failed ownership, link, or atomic-update safety checks."
        }

        StatusCard {
            visible: root.appearanceModel.recoveryState === "available"
            label: "Interrupted theme transaction"
            statusState: "failed"
            value: root.appearanceModel.recoveryAction
            detail: "Recovery is available for " + root.appearanceModel.recoveryTheme
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.appearanceModel.recoveryState === "available"
            ShellButton {
                label: root.appearanceModel.busy ? "Recovering..." : "Restore previous state"
                enabled: !root.appearanceModel.busy
                onActivated: root.appearanceModel.recover()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.appearanceModel.previewState !== "none"
            Layout.preferredHeight: previewColumn.implicitHeight + Theme.spacingLg * 2
            color: Theme.controlNormalFill
            border.color: root.appearanceModel.previewState === "failed" ? Theme.danger : Theme.warning
            border.width: Theme.controlFocusBorderWidth
            radius: Theme.controlRadius

            ColumnLayout {
                id: previewColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.previewState === "failed"
                        ? "Preview rollback needs attention"
                        : "Previewing " + root.appearanceModel.previewTheme
                            + " / " + root.appearanceModel.previewRemaining + "s remaining"
                    color: root.appearanceModel.previewState === "failed" ? Theme.danger : Theme.warning
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.previewDetail
                    color: Theme.menuText
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    ShellButton {
                        visible: root.appearanceModel.previewState === "active"
                        label: "Keep theme"
                        enabled: !root.appearanceModel.busy
                        onActivated: root.appearanceModel.keepPreview()
                    }
                    ShellButton {
                        label: "Restore previous"
                        enabled: !root.appearanceModel.busy
                        onActivated: root.appearanceModel.revertPreview()
                    }
                    ShellButton {
                        visible: root.appearanceModel.previewState === "failed"
                        label: "Accept external state"
                        danger: true
                        enabled: !root.appearanceModel.busy
                        onActivated: root.appearanceModel.abandonPreview()
                    }
                }
            }
        }

        SectionLabel { label: "Themes" }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: root.appearanceModel.themes
                delegate: ShellButton {
                    id: themeButton
                    required property var modelData
                    label: root.displayName(themeButton.modelData.id)
                        + (themeButton.modelData.id === root.selectedThemeId ? " / Selected" : "")
                        + (themeButton.modelData.id === root.appearanceModel.activeTheme ? " / Active" : "")
                    enabled: themeButton.modelData.valid && !root.appearanceModel.busy
                    onActivated: root.selectedThemeId = themeButton.modelData.id
                }
            }
        }

        StatusCard {
            visible: root.selectedTheme !== null
            label: root.selectedTheme ? root.displayName(root.selectedTheme.id) : "Theme"
            statusState: root.selectedTheme && root.selectedTheme.valid ? "available" : "unavailable"
            value: root.selectedTheme && root.selectedTheme.dark ? "Dark" : "Light"
            detail: root.selectedTheme ? root.selectedTheme.detail
                + " / GTK: " + root.selectedTheme.gtkTheme : "Select a theme"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            ShellButton {
                label: "Preview for 30 seconds"
                enabled: root.appearanceModel.mutationReady && root.selectedTheme !== null
                    && root.selectedTheme.valid && root.selectedTheme.mutable
                    && !root.appearanceModel.busy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.startPreview(root.selectedThemeId)
            }
            ShellButton {
                label: "Apply"
                enabled: root.appearanceModel.mutationReady && root.selectedTheme !== null
                    && root.selectedTheme.valid && root.selectedTheme.mutable
                    && !root.appearanceModel.busy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.applyTheme(root.selectedThemeId)
            }
            ShellButton {
                label: "Reset to managed default"
                enabled: root.appearanceModel.mutationReady && !root.appearanceModel.busy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.resetTheme()
            }
        }

        SectionLabel { label: "Application status" }

        Repeater {
            model: root.appearanceModel.integrations
            delegate: StatusCard {
                id: integrationCard
                required property var modelData
                label: root.displayName(integrationCard.modelData.id)
                statusState: integrationCard.modelData.state
                value: integrationCard.modelData.state
                detail: integrationCard.modelData.detail
                    + (integrationCard.modelData.value.length > 0
                        ? " / " + integrationCard.modelData.value : "")
            }
        }

        SectionLabel {
            visible: root.capabilities.length > 0
            label: "Additional capabilities"
        }

        Repeater {
            model: root.capabilities
            delegate: StatusCard {
                id: capabilityCard
                required property var modelData
                label: capabilityCard.modelData.label
                statusState: capabilityCard.modelData.status
                value: capabilityCard.modelData.status
                detail: capabilityCard.modelData.detail
            }
        }

        SectionLabel {
            visible: root.appearanceModel.errors.length > 0
            label: "Unresolved details"
        }

        Repeater {
            model: root.appearanceModel.errors
            delegate: StatusCard {
                id: errorCard
                required property var modelData
                label: root.displayName(errorCard.modelData.scope)
                statusState: "failed"
                value: errorCard.modelData.code
                detail: errorCard.modelData.detail
            }
        }
    }
}
