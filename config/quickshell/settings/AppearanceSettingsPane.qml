import QtQuick
import QtQuick.Layouts
import qs.core

pragma ComponentBehavior: Bound

Flickable {
    id: root

    required property var appearanceModel
    required property var panelSettingsModel
    required property var capabilities
    required property var textScaleCapability
    property string selectedThemeId: ""
    property string selectedWallpaperPath: ""
    property string selectedWallpaperFit: "fill"
    property string selectedFontFamily: "MesloLGS Nerd Font Mono"
    property real selectedFontScale: 1.0
    readonly property var selectedTheme: root.appearanceModel.themeById(root.selectedThemeId)
    readonly property bool appearanceBusy: root.appearanceModel.busy
        || root.appearanceModel.wallpaperBusy || root.appearanceModel.fontBusy
        || root.appearanceModel.personalizationBusy
    readonly property bool wallpaperControlsBusy: root.appearanceBusy
        || root.appearanceModel.wallpaperStatusBusy
    readonly property bool wallpaperPreviewControlsBusy: root.appearanceBusy
        || root.appearanceModel.wallpaperPreviewActionBusy
    readonly property bool fontControlsBusy: root.appearanceBusy || root.appearanceModel.fontStatusBusy
        || root.appearanceModel.wallpaperStatusBusy
    readonly property bool personalizationActionsReady:
        root.appearanceModel.personalizationMutationState === "available"
        && !root.appearanceModel.personalizationStatusBusy
        && root.appearanceModel.previewState === "none"
        && root.appearanceModel.recoveryState === "none"
    readonly property bool personalizationDelegatesReady:
        !root.appearanceModel.personalizationStatusBusy
        && root.appearanceModel.previewState === "none"
        && root.appearanceModel.recoveryState === "none"
    readonly property var accessibilityCapabilities: root.capabilities.filter(function(capability) {
        return capability.id.indexOf("accessibility-") === 0
            && capability.id !== "accessibility-text-scale";
    })
    readonly property var additionalCapabilities: root.capabilities.filter(function(capability) {
        return capability.id.indexOf("accessibility-") !== 0;
    })
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

    function syncFontSelection() {
        if (root.appearanceModel.fontFamily.length > 0)
            root.selectedFontFamily = root.appearanceModel.fontFamily;
        if (root.appearanceModel.fontScale >= 0.8 && root.appearanceModel.fontScale <= 1.5)
            root.selectedFontScale = root.appearanceModel.fontScale;
    }

    function followLabel(capability, option) {
        if (option === "follow-theme") return "Following the selected DWM theme";
        if (option === "follow-system") return "Following the system setting";
        if (option === "unknown") return "Saved preference needs repair";
        return "Saved override: " + option;
    }

    onVisibleChanged: if (visible) {
        root.ensureSelection();
        root.ensureWallpaperSelection();
        root.syncFontSelection();
    }
    Component.onCompleted: {
        root.ensureSelection();
        root.ensureWallpaperSelection();
        root.syncFontSelection();
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
        function onFontFamilyChanged() { root.syncFontSelection(); }
        function onFontScaleChanged() { root.syncFontSelection(); }
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
                    Layout.maximumWidth: Math.max(120, statusCard.width * 0.45)
                    text: statusCard.value
                    color: root.statusColor(statusCard.statusState)
                    font.bold: true
                    elide: Text.ElideRight
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

    component PersonalizationControl: ColumnLayout {
        id: personalizationControl
        required property string capability
        required property string title
        required property string resetLabel
        required property var candidates
        property var capabilityGate: null
        property bool advancedEditor: false
        property string selectedValue: ""
        property bool selectionDirty: false
        property string lastSavedOption: ""
        readonly property var selection: root.appearanceModel.personalizationSelection(
            personalizationControl.capability)
        readonly property var readiness: root.appearanceModel.personalizationReadiness(
            personalizationControl.capability)
        readonly property var inventorySelection: root.appearanceModel.inventorySelection(
            personalizationControl.capability)
        readonly property bool gateAllowsActions: personalizationControl.capabilityGate === null
            || personalizationControl.capabilityGate.status === "available"
            || personalizationControl.capabilityGate.status === "partial"
        readonly property string effectiveState: personalizationControl.gateAllowsActions
            ? root.appearanceModel.personalizationEffectiveState(personalizationControl.capability)
            : personalizationControl.capabilityGate.status
        readonly property string effectiveDetail: personalizationControl.gateAllowsActions
            ? root.appearanceModel.personalizationEffectiveDetail(personalizationControl.capability)
            : personalizationControl.capabilityGate.detail
        readonly property var delegateRecord: root.appearanceModel.personalizationDelegates[
            personalizationControl.capability] || ({ "state": "unavailable", "tool": "",
                "detail": "No trusted advanced editor is installed" })

        Layout.fillWidth: true
        spacing: Theme.spacingSm

        function candidateAvailable(value) {
            for (const candidate of personalizationControl.candidates) {
                if (candidate.token === value && candidate.state === "available") return true;
            }
            return false;
        }

        function syncSelection() {
            const savedOptionChanged = personalizationControl.lastSavedOption.length > 0
                && personalizationControl.lastSavedOption !== personalizationControl.selection.option;
            personalizationControl.lastSavedOption = personalizationControl.selection.option;
            if (personalizationControl.selectionDirty && !savedOptionChanged
                    && personalizationControl.candidateAvailable(
                        personalizationControl.selectedValue)) return;
            personalizationControl.selectionDirty = false;
            let preferred = personalizationControl.selection.option;
            if (personalizationControl.capability === "font" && preferred === "follow-system")
                preferred = personalizationControl.inventorySelection.value;
            if (preferred === "follow-system" || preferred === "follow-theme"
                    || preferred === "unknown") preferred = personalizationControl.selection.value;
            if (personalizationControl.candidateAvailable(preferred)) {
                personalizationControl.selectedValue = preferred;
                return;
            }
            if (!personalizationControl.candidateAvailable(personalizationControl.selectedValue))
                personalizationControl.selectedValue = "";
        }

        onSelectionChanged: syncSelection()
        onInventorySelectionChanged: syncSelection()
        onCandidatesChanged: syncSelection()
        Component.onCompleted: syncSelection()

        SectionLabel { label: personalizationControl.title }

        StatusCard {
            label: personalizationControl.title
            statusState: personalizationControl.effectiveState
            value: personalizationControl.selection.value.length > 0
                ? personalizationControl.selection.value : "Unavailable"
            detail: personalizationControl.effectiveDetail + " / "
                + root.followLabel(personalizationControl.capability,
                    personalizationControl.selection.option)
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: personalizationControl.candidates
                delegate: ShellButton {
                    id: personalizationButton
                    required property var modelData
                    label: personalizationButton.modelData.label
                        + (personalizationButton.modelData.token
                            === personalizationControl.selectedValue ? " / Selected" : "")
                        + (personalizationButton.modelData.token
                            === personalizationControl.selection.option ? " / Saved" : "")
                    enabled: personalizationControl.gateAllowsActions && !root.appearanceBusy
                        && personalizationButton.modelData.state === "available"
                    onActivated: {
                        personalizationControl.selectedValue = personalizationButton.modelData.token;
                        personalizationControl.selectionDirty = true;
                    }
                }
            }
        }

        UiText {
            Layout.fillWidth: true
            visible: personalizationControl.readiness.apply !== "available"
                || personalizationControl.readiness.reset !== "available"
            text: personalizationControl.readiness.detail
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        UiText {
            Layout.fillWidth: true
            visible: personalizationControl.candidates.length === 0
            text: root.appearanceModel.inventoryProviderState === "unavailable"
                ? root.appearanceModel.inventoryProviderDetail
                : "No supported choices are installed for this capability."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            ShellButton {
                label: "Apply " + personalizationControl.title.toLowerCase()
                enabled: root.personalizationActionsReady
                    && personalizationControl.gateAllowsActions
                    && root.appearanceModel.personalizationApplyReady(
                        personalizationControl.capability)
                    && personalizationControl.candidateAvailable(
                        personalizationControl.selectedValue) && !root.appearanceBusy
                onActivated: root.appearanceModel.applyPersonalization(
                    personalizationControl.capability, personalizationControl.selectedValue)
            }
            ShellButton {
                label: personalizationControl.resetLabel
                enabled: root.personalizationActionsReady
                    && personalizationControl.gateAllowsActions
                    && root.appearanceModel.personalizationResetReady(
                        personalizationControl.capability)
                    && !root.appearanceBusy
                onActivated: {
                    personalizationControl.selectionDirty = false;
                    root.appearanceModel.resetPersonalization(personalizationControl.capability);
                }
            }
            ShellButton {
                visible: personalizationControl.advancedEditor
                    && personalizationControl.delegateRecord.state === "available"
                label: personalizationControl.delegateRecord.tool.length > 0
                    ? "Open " + personalizationControl.delegateRecord.tool : "Open advanced editor"
                enabled: root.personalizationDelegatesReady && !root.appearanceBusy
                onActivated: root.appearanceModel.delegatePersonalization(
                    personalizationControl.capability)
            }
        }

        StatusCard {
            visible: personalizationControl.advancedEditor
                && personalizationControl.delegateRecord.state !== "available"
            label: "Advanced " + personalizationControl.title + " editing"
            statusState: "unavailable"
            value: "Optional"
            detail: personalizationControl.delegateRecord.detail
        }

        Connections {
            target: root.appearanceModel
            function onPersonalizationBusyChanged() {
                if (!root.appearanceModel.personalizationBusy
                        && root.appearanceModel.personalizationActionSucceeded
                        && root.appearanceModel.personalizationActionKind !== "delegate"
                        && root.appearanceModel.personalizationActionCapability
                            === personalizationControl.capability) {
                    personalizationControl.selectionDirty = false;
                    personalizationControl.syncSelection();
                }
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
                onActivated: root.appearanceModel.refreshAll(true)
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

        SectionLabel { label: "Font and text size" }

        StatusCard {
            label: "Managed shell font"
            statusState: root.appearanceModel.fontState
            value: Math.round(root.appearanceModel.fontScale * 100) + "%"
            detail: root.appearanceModel.fontDetail + " / " + root.appearanceModel.fontFamily
        }

        StatusCard {
            visible: root.appearanceModel.fontProviderState !== "available"
                || !root.appearanceModel.fontMutationReady
            label: "Font changes unavailable"
            statusState: root.appearanceModel.fontProviderState === "available"
                ? "restricted" : root.appearanceModel.fontProviderState
            value: "Protected"
            detail: root.appearanceModel.fontProviderState !== "available"
                ? root.appearanceModel.fontProviderDetail
                : "The installed font helper cannot safely update user state"
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Theme.controlHeight, fontInput.implicitHeight + 14)
            color: Theme.controlNormalFill
            border.color: fontInput.activeFocus ? Theme.controlFocusBorder : Theme.controlNormalBorder
            border.width: fontInput.activeFocus ? Theme.controlFocusBorderWidth : Theme.controlBorderWidth
            radius: Theme.controlRadius

            TextInput {
                id: fontInput
                anchors.fill: parent
                anchors.margins: 7
                text: root.selectedFontFamily
                color: Theme.textStrong
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontBodySize
                activeFocusOnTab: true
                selectByMouse: true
                verticalAlignment: TextInput.AlignVCenter
                onTextEdited: root.selectedFontFamily = text
            }
        }

        UiText {
            Layout.fillWidth: true
            text: "Enter an exact installed Fontconfig family. Suggestions are bounded to the first 24 discovered families."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: root.appearanceModel.fontCandidates.slice(0, 24)
                delegate: ShellButton {
                    id: fontButton
                    required property var modelData
                    label: fontButton.modelData.label
                        + (fontButton.modelData.token === root.selectedFontFamily ? " / Selected" : "")
                    enabled: !root.fontControlsBusy && fontButton.modelData.state === "available"
                    onActivated: root.selectedFontFamily = fontButton.modelData.token
                }
            }
        }

        SectionLabel { label: "Text scale" }

        Flow {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Repeater {
                model: [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
                delegate: ShellButton {
                    id: scaleButton
                    required property real modelData
                    label: Math.round(scaleButton.modelData * 100) + "%"
                        + (Math.abs(scaleButton.modelData - root.selectedFontScale) < 0.001
                            ? " / Selected" : "")
                    enabled: !root.fontControlsBusy
                    onActivated: root.selectedFontScale = scaleButton.modelData
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.appearanceModel.fontPreviewState !== "none"
            Layout.preferredHeight: fontPreviewColumn.implicitHeight + Theme.spacingLg * 2
            color: Theme.controlNormalFill
            border.color: root.appearanceModel.fontPreviewState === "failed"
                ? Theme.danger : Theme.warning
            border.width: Theme.controlFocusBorderWidth
            radius: Theme.controlRadius

            ColumnLayout {
                id: fontPreviewColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingLg
                spacing: Theme.spacingSm

                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.fontPreviewState === "failed"
                        ? "Font preview recovery needs attention"
                        : "Font preview / " + root.appearanceModel.fontPreviewRemaining
                            + "s remaining / " + root.appearanceModel.fontPreviewFamily
                            + " / " + Math.round(root.appearanceModel.fontPreviewScale * 100) + "%"
                    color: root.appearanceModel.fontPreviewState === "failed"
                        ? Theme.danger : Theme.warning
                    font.bold: true
                    wrapMode: Text.WordWrap
                }
                UiText {
                    Layout.fillWidth: true
                    text: root.appearanceModel.fontPreviewDetail
                    color: Theme.menuText
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    ShellButton {
                        visible: root.appearanceModel.fontPreviewState === "active"
                        label: "Keep font"
                        enabled: !root.fontControlsBusy
                        onActivated: root.appearanceModel.keepFontPreview()
                    }
                    ShellButton {
                        label: "Restore previous"
                        enabled: !root.fontControlsBusy
                        onActivated: root.appearanceModel.revertFontPreview()
                    }
                    ShellButton {
                        visible: root.appearanceModel.fontPreviewState === "failed"
                        label: "Accept external state"
                        danger: true
                        enabled: !root.fontControlsBusy
                        onActivated: root.appearanceModel.abandonFontPreview()
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            ShellButton {
                label: "Preview font for 30 seconds"
                enabled: root.appearanceModel.fontMutationReady
                    && root.selectedFontFamily.trim().length > 0 && !root.fontControlsBusy
                    && root.appearanceModel.fontPreviewState === "none"
                onActivated: root.appearanceModel.previewFont(
                    root.selectedFontFamily.trim(), root.selectedFontScale)
            }
            ShellButton {
                label: "Apply font"
                enabled: root.appearanceModel.fontMutationReady
                    && root.selectedFontFamily.trim().length > 0 && !root.fontControlsBusy
                    && root.appearanceModel.fontPreviewState === "none"
                onActivated: root.appearanceModel.applyFont(
                    root.selectedFontFamily.trim(), root.selectedFontScale)
            }
            ShellButton {
                label: "Reset font"
                enabled: root.appearanceModel.fontMutationReady && !root.fontControlsBusy
                    && root.appearanceModel.fontPreviewState === "none"
                onActivated: root.appearanceModel.resetFont()
            }
        }

        SectionLabel { label: "Desktop applications" }

        StatusCard {
            visible: root.appearanceModel.personalizationProviderState !== "available"
                || root.appearanceModel.personalizationMutationState !== "available"
            label: "Desktop personalization"
            statusState: root.appearanceModel.personalizationMutationState !== "available"
                ? root.appearanceModel.personalizationMutationState
                : root.appearanceModel.personalizationProviderState
            value: root.appearanceModel.personalizationMutationState === "available"
                ? "Partially available" : "Protected"
            detail: root.appearanceModel.personalizationProviderState !== "available"
                ? root.appearanceModel.personalizationProviderDetail
                : root.appearanceModel.personalizationMutationDetail
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.appearanceModel.personalizationRepairState !== "unavailable"

            UiText {
                Layout.fillWidth: true
                text: root.appearanceModel.personalizationRepairDetail
                color: root.statusColor(root.appearanceModel.personalizationRepairState)
                wrapMode: Text.WordWrap
            }

            ShellButton {
                label: "Repair personalization state"
                enabled: root.appearanceModel.personalizationRepairState === "available"
                    && !root.appearanceBusy && !root.appearanceModel.personalizationStatusBusy
                    && root.appearanceModel.previewState === "none"
                    && root.appearanceModel.recoveryState === "none"
                onActivated: root.appearanceModel.repairPersonalization()
            }
        }

        UiText {
            Layout.fillWidth: true
            text: "These choices affect GTK, Qt, and other desktop applications. The managed shell font above remains independent so icon glyphs and panel geometry stay stable."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        PersonalizationControl {
            capability: "font"
            title: "Application font"
            resetLabel: "Follow system font"
            candidates: root.appearanceModel.personalizationCandidates("font", 24)
        }

        PersonalizationControl {
            capability: "cursor"
            title: "Cursor theme"
            resetLabel: "Follow DWM theme"
            candidates: root.appearanceModel.personalizationCandidates("cursor", 24)
        }

        PersonalizationControl {
            capability: "icon"
            title: "Icon theme"
            resetLabel: "Follow system icons"
            candidates: root.appearanceModel.personalizationCandidates("icon", 24)
        }

        PersonalizationControl {
            capability: "gtk"
            title: "GTK theme"
            resetLabel: "Follow DWM theme"
            candidates: root.appearanceModel.personalizationCandidates("gtk", 24)
            advancedEditor: true
        }

        PersonalizationControl {
            capability: "qt"
            title: "Qt platform theme"
            resetLabel: "Follow DWM theme"
            candidates: root.appearanceModel.personalizationCandidates("qt", 24)
            advancedEditor: true
        }

        SectionLabel { label: "Accessibility" }

        UiText {
            Layout.fillWidth: true
            text: "Use the text-scale controls below when their provider is available. The remaining cards explain which keyboard, pointer, contrast, motion, and notification controls are not yet managed by this desktop."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        PersonalizationControl {
            capability: "text-size"
            title: "Application text scale"
            resetLabel: "Follow system scale"
            candidates: root.appearanceModel.desktopTextScaleCandidates
            capabilityGate: root.textScaleCapability
        }

        Repeater {
            model: root.accessibilityCapabilities
            delegate: StatusCard {
                id: accessibilityCard
                required property var modelData
                label: accessibilityCard.modelData.label
                statusState: accessibilityCard.modelData.status
                value: accessibilityCard.modelData.status
                detail: accessibilityCard.modelData.detail
            }
        }

        SectionLabel { label: "Panel widgets" }

        StatusCard {
            visible: root.panelSettingsModel.providerState !== "available"
                && root.panelSettingsModel.providerState !== "defaults"
            label: "Panel visibility"
            statusState: root.panelSettingsModel.providerState
            value: "Using safe defaults"
            detail: root.panelSettingsModel.providerDetail
        }

        UiText {
            Layout.fillWidth: true
            text: "These choices apply to every monitor and persist for future shell sessions."
            color: Theme.menuMutedText
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.panelSettingsModel.widgets

            delegate: Rectangle {
                id: panelWidgetRow
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 48
                color: Theme.controlNormalFill
                border.color: Theme.controlNormalBorder
                border.width: Theme.controlBorderWidth
                radius: Theme.controlRadius

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacingLg
                    anchors.rightMargin: Theme.spacingLg

                    UiText {
                        Layout.fillWidth: true
                        text: panelWidgetRow.modelData.label
                        color: Theme.menuText
                    }

                    PanelToggleSwitch {
                        checked: root.panelSettingsModel.widgetEnabled(panelWidgetRow.modelData.id)
                        busy: root.panelSettingsModel.busy
                        enabled: root.panelSettingsModel.mutationReady
                        onToggled: root.panelSettingsModel.toggleWidget(panelWidgetRow.modelData.id)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            UiText {
                Layout.fillWidth: true
                text: root.panelSettingsModel.message.length > 0
                        && !root.panelSettingsModel.actionSucceeded
                    ? root.panelSettingsModel.message
                    : root.panelSettingsModel.providerState !== "available"
                        && root.panelSettingsModel.providerState !== "defaults"
                        ? root.panelSettingsModel.providerDetail
                        : root.panelSettingsModel.message.length > 0
                            ? root.panelSettingsModel.message : root.panelSettingsModel.providerDetail
                color: root.panelSettingsModel.providerState === "unavailable"
                    ? Theme.danger : Theme.menuMutedText
                wrapMode: Text.WordWrap
            }

            ShellButton {
                label: "Show all widgets"
                enabled: root.panelSettingsModel.mutationReady && !root.panelSettingsModel.busy
                onActivated: root.panelSettingsModel.reset()
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
            visible: root.additionalCapabilities.length > 0
            label: "Additional capabilities"
        }

        Repeater {
            model: root.additionalCapabilities
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
