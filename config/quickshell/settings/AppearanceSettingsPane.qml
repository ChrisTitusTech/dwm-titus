import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var appearanceModel
    required property var capabilities
    property string selectedThemeId: ""
    property string selectedWallpaperPath: ""
    property string selectedWallpaperFit: "fill"
    readonly property var selectedTheme: root.appearanceModel.themeById(root.selectedThemeId)
    readonly property bool appearanceBusy: root.appearanceModel.busy || root.appearanceModel.wallpaperBusy
    readonly property bool wallpaperControlsBusy: root.appearanceBusy
        || root.appearanceModel.wallpaperStatusBusy
    readonly property bool wallpaperPreviewControlsBusy: root.appearanceBusy
        || root.appearanceModel.wallpaperPreviewActionBusy
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

    function ensureWallpaperSelection() {
        for (const candidate of root.appearanceModel.wallpaperCandidates) {
            if (candidate.token === root.selectedWallpaperPath) return;
        }
        const preferred = root.appearanceModel.wallpaperPath;
        for (const candidate of root.appearanceModel.wallpaperCandidates) {
            if (candidate.token === preferred) {
                root.selectedWallpaperPath = preferred;
                root.selectedWallpaperFit = root.appearanceModel.wallpaperFit;
                return;
            }
        }
        if (root.appearanceModel.wallpaperCandidates.length > 0)
            root.selectedWallpaperPath = root.appearanceModel.wallpaperCandidates[0].token;
        else root.selectedWallpaperPath = "";
        if (root.appearanceModel.validWallpaperFit(root.appearanceModel.wallpaperFit))
            root.selectedWallpaperFit = root.appearanceModel.wallpaperFit;
    }

    function wallpaperSelectionAvailable() {
        for (const candidate of root.appearanceModel.wallpaperCandidates) {
            if (candidate.token === root.selectedWallpaperPath) return true;
        }
        return false;
    }

    function wallpaperEmptyDetail() {
        if (!root.appearanceModel.inventoryParsed
                || root.appearanceModel.inventoryProviderState === "unavailable")
            return root.appearanceModel.inventoryProviderDetail;
        const selection = root.appearanceModel.inventorySelections.wallpaper;
        if (!selection) return "Wallpaper inventory did not return a selection record";
        if (selection.state === "unavailable"
                || selection.detail === "Wallpaper candidate discovery did not complete")
            return selection.detail;
        let detail = "No supported images were found in ~/Pictures/backgrounds.";
        if (selection.state !== "available") detail += " " + selection.detail + ".";
        if (root.appearanceModel.inventoryWatchState === "available")
            return detail + " Add an AVIF, BMP, GIF, JPEG, PNG, SVG, or WebP image and this list will update while Appearance is open.";
        return detail + " " + root.appearanceModel.inventoryWatchDetail
            + ". Add an image, then use Refresh to update this list.";
    }

    function syncWallpaperSelection() {
        const preferred = root.appearanceModel.wallpaperPath;
        for (const candidate of root.appearanceModel.wallpaperCandidates) {
            if (candidate.token === preferred) {
                root.selectedWallpaperPath = preferred;
                if (root.appearanceModel.validWallpaperFit(root.appearanceModel.wallpaperFit))
                    root.selectedWallpaperFit = root.appearanceModel.wallpaperFit;
                return;
            }
        }
        root.ensureWallpaperSelection();
    }

    onVisibleChanged: if (visible) {
        root.ensureSelection();
        root.ensureWallpaperSelection();
    }
    Component.onCompleted: {
        root.ensureSelection();
        root.ensureWallpaperSelection();
    }

    Connections {
        target: root.appearanceModel
        function onThemesChanged() { root.ensureSelection(); }
        function onWallpaperCandidatesChanged() { root.ensureWallpaperSelection(); }
        function onWallpaperPathChanged() { root.syncWallpaperSelection(); }
        function onWallpaperFitChanged() {
            if (root.selectedWallpaperPath === root.appearanceModel.wallpaperPath
                    && root.appearanceModel.validWallpaperFit(root.appearanceModel.wallpaperFit))
                root.selectedWallpaperFit = root.appearanceModel.wallpaperFit;
        }
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
                label: root.appearanceBusy ? "Working..." : "Refresh"
                enabled: !root.appearanceBusy
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
                label: root.appearanceBusy ? "Recovering..." : "Restore previous state"
                enabled: !root.appearanceBusy
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
                        enabled: !root.appearanceBusy
                        onActivated: root.appearanceModel.keepPreview()
                    }
                    ShellButton {
                        label: "Restore previous"
                        enabled: !root.appearanceBusy
                        onActivated: root.appearanceModel.revertPreview()
                    }
                    ShellButton {
                        visible: root.appearanceModel.previewState === "failed"
                        label: "Accept external state"
                        danger: true
                        enabled: !root.appearanceBusy
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
                    enabled: themeButton.modelData.valid && !root.appearanceBusy
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
                    && !root.appearanceBusy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.startPreview(root.selectedThemeId)
            }
            ShellButton {
                label: "Apply"
                enabled: root.appearanceModel.mutationReady && root.selectedTheme !== null
                    && root.selectedTheme.valid && root.selectedTheme.mutable
                    && !root.appearanceBusy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.applyTheme(root.selectedThemeId)
            }
            ShellButton {
                label: "Reset to managed default"
                enabled: root.appearanceModel.mutationReady && !root.appearanceBusy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.resetTheme()
            }
        }

        SectionLabel { label: "Wallpaper" }

        StatusCard {
            label: "Configured wallpaper"
            statusState: root.appearanceModel.wallpaperState
            value: root.appearanceModel.wallpaperFit
            detail: root.appearanceModel.wallpaperDetail
                + (root.appearanceModel.wallpaperPath.length > 0
                    ? " / " + root.appearanceModel.wallpaperPath : "")
        }

        StatusCard {
            visible: root.appearanceModel.wallpaperProviderState !== "available"
            label: "Wallpaper provider"
            statusState: root.appearanceModel.wallpaperProviderState
            value: root.appearanceModel.wallpaperProviderState
            detail: root.appearanceModel.wallpaperProviderDetail
        }

        StatusCard {
            visible: !root.appearanceModel.wallpaperMutationReady
            label: "Wallpaper apply and preview unavailable"
            statusState: "restricted"
            value: root.appearanceModel.wallpaperResetReady ? "Reset available" : "Protected"
            detail: root.appearanceModel.wallpaperMutationDetail
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.appearanceModel.wallpaperPreviewState !== "none"
            Layout.preferredHeight: wallpaperPreviewColumn.implicitHeight + Theme.spacingLg * 2
            color: Theme.controlNormalFill
            border.color: root.appearanceModel.wallpaperPreviewState === "failed"
                ? Theme.danger : Theme.warning
            border.width: Theme.controlFocusBorderWidth
            radius: Theme.controlRadius

            ColumnLayout {
                id: wallpaperPreviewColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.wallpaperPreviewState === "failed"
                        ? "Wallpaper preview recovery needs attention"
                        : "Wallpaper preview / " + root.appearanceModel.wallpaperPreviewRemaining
                            + "s remaining / " + root.appearanceModel.wallpaperPreviewFit
                    color: root.appearanceModel.wallpaperPreviewState === "failed"
                        ? Theme.danger : Theme.warning
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.wallpaperPreviewDetail
                        + (root.appearanceModel.wallpaperPreviewPath.length > 0
                            ? " / " + root.appearanceModel.wallpaperPreviewPath : "")
                    color: Theme.menuText
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    ShellButton {
                        visible: root.appearanceModel.wallpaperPreviewState === "active"
                        label: "Keep wallpaper"
                        enabled: !root.wallpaperPreviewControlsBusy
                        onActivated: root.appearanceModel.keepWallpaperPreview()
                    }
                    ShellButton {
                        label: "Restore configured"
                        visible: root.appearanceModel.wallpaperPreviewToken.length > 0
                        enabled: root.appearanceModel.wallpaperPreviewState === "active"
                            ? !root.wallpaperPreviewControlsBusy : !root.wallpaperControlsBusy
                        onActivated: root.appearanceModel.revertWallpaperPreview()
                    }
                    ShellButton {
                        visible: root.appearanceModel.wallpaperPreviewState === "failed"
                            && root.appearanceModel.wallpaperPreviewToken.length > 0
                        label: "Use current configuration"
                        danger: true
                        enabled: !root.wallpaperControlsBusy
                        onActivated: root.appearanceModel.abandonWallpaperPreview()
                    }
                    ShellButton {
                        visible: root.appearanceModel.wallpaperPreviewState === "failed"
                        label: "Repair wallpaper state"
                        enabled: !root.wallpaperControlsBusy
                        onActivated: root.appearanceModel.reconcileWallpaperPreview()
                    }
                }
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: root.appearanceModel.wallpaperCandidates.length === 0
            text: root.wallpaperEmptyDetail()
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: root.appearanceModel.wallpaperCandidates
                delegate: ShellButton {
                    id: wallpaperButton
                    required property var modelData
                    label: wallpaperButton.modelData.label
                        + (wallpaperButton.modelData.token === root.selectedWallpaperPath
                            ? " / Selected" : "")
                        + (wallpaperButton.modelData.token === root.appearanceModel.wallpaperPath
                            ? " / Saved" : "")
                    enabled: !root.wallpaperControlsBusy
                    onActivated: root.selectedWallpaperPath = wallpaperButton.modelData.token
                }
            }
        }

        SectionLabel { label: "Fit mode" }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: [
                    { "id": "fill", "label": "Fill" },
                    { "id": "max", "label": "Fit" },
                    { "id": "center", "label": "Center" },
                    { "id": "scale", "label": "Stretch" },
                    { "id": "tile", "label": "Tile" }
                ]
                delegate: ShellButton {
                    id: fitButton
                    required property var modelData
                    label: fitButton.modelData.label
                        + (fitButton.modelData.id === root.selectedWallpaperFit ? " / Selected" : "")
                    enabled: !root.wallpaperControlsBusy
                    onActivated: root.selectedWallpaperFit = fitButton.modelData.id
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            ShellButton {
                label: "Preview wallpaper for 30 seconds"
                enabled: root.appearanceModel.wallpaperMutationReady
                    && root.wallpaperSelectionAvailable() && !root.wallpaperControlsBusy
                    && root.appearanceModel.wallpaperPreviewState === "none"
                onActivated: root.appearanceModel.previewWallpaper(
                    root.selectedWallpaperPath, root.selectedWallpaperFit)
            }
            ShellButton {
                label: "Apply wallpaper"
                enabled: root.appearanceModel.wallpaperMutationReady
                    && root.wallpaperSelectionAvailable() && !root.wallpaperControlsBusy
                    && root.appearanceModel.wallpaperPreviewState === "none"
                onActivated: root.appearanceModel.applyWallpaper(
                    root.selectedWallpaperPath, root.selectedWallpaperFit)
            }
            ShellButton {
                label: "Reset wallpaper"
                enabled: root.appearanceModel.wallpaperResetReady && !root.wallpaperControlsBusy
                    && root.appearanceModel.wallpaperPreviewState === "none"
                onActivated: root.appearanceModel.resetWallpaper()
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
