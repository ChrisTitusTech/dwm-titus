import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

pragma ComponentBehavior: Bound

Scope {
    id: root

    property bool settingsVisible: false
    property bool busy: false
    property bool mutationReady: false
    property string providerState: "idle"
    property string providerDetail: "Appearance has not been loaded"
    property string sourceKind: "none"
    property string sourcePath: ""
    property string activeTheme: "none"
    property string resolvedTheme: "nord"
    property string activeState: "recovery"
    property var themes: []
    property var colors: ({})
    property var integrations: []
    property var errors: []
    property string inventoryProviderState: "idle"
    property string inventoryProviderDetail: "Appearance assets have not been inventoried"
    property string inventoryWatchState: "idle"
    property string inventoryWatchDetail: "Live asset updates have not been checked"
    property var inventorySelections: ({})
    property var inventoryCandidates: []
    property int inventoryGeneration: 0
    property int inventoryRunGeneration: 0
    property bool inventoryPending: false
    property bool inventoryPendingAllowUnwatched: false
    property bool inventoryParsed: false
    property bool inventoryWatchReady: false
    property bool inventoryWatchSawEvent: false
    property bool inventoryWatchFailed: false
    property bool inventoryWatchRestartPending: false
    property bool compositorWatchReady: false
    property string wallpaperState: "idle"
    property string wallpaperPath: ""
    property string wallpaperFit: "fill"
    property string wallpaperDetail: "Wallpaper state has not been loaded"
    property string wallpaperProviderState: "idle"
    property string wallpaperProviderDetail: "Wallpaper provider has not been checked"
    property string wallpaperMutationState: "idle"
    property bool wallpaperMutationReady: false
    property string wallpaperMutationDetail: "Wallpaper changes have not been checked"
    property string wallpaperResetState: "idle"
    property bool wallpaperResetReady: false
    property string wallpaperResetDetail: "Wallpaper reset readiness has not been checked"
    property bool wallpaperBusy: false
    readonly property bool wallpaperStatusBusy: wallpaperReadinessProcess.running
        || wallpaperStatusProcess.running || inventoryProcess.running
        || root.wallpaperStatusPending || root.inventoryPending
        || (inventoryWatchProcess.running && !root.inventoryWatchReady)
    readonly property bool wallpaperPreviewActionBusy: wallpaperReadinessProcess.running
        || wallpaperStatusProcess.running || wallpaperActionProcess.running || root.busy
    property string wallpaperPreviewState: "none"
    property string wallpaperPreviewToken: ""
    property string wallpaperPreviewPath: ""
    property string wallpaperPreviewFit: "fill"
    property int wallpaperPreviewRemaining: 0
    property string wallpaperPreviewDetail: ""
    property string wallpaperActionKind: ""
    property string wallpaperActionToken: ""
    property string wallpaperActionPath: ""
    property string wallpaperActionFit: "fill"
    property string wallpaperActionResultState: ""
    property string wallpaperActionError: ""
    property bool wallpaperActionSucceeded: false
    property bool wallpaperStatusParsed: false
    property bool wallpaperStatusPending: false
    property string fontState: "idle"
    property string fontFamily: "MesloLGS Nerd Font Mono"
    property real fontScale: 1.0
    property string fontDetail: "Managed shell font state has not been loaded"
    property string fontProviderState: "idle"
    property string fontProviderDetail: "Font provider has not been checked"
    property bool fontMutationReady: false
    property bool fontBusy: false
    readonly property bool fontStatusBusy: fontStatusProcess.running || fontReadinessProcess.running
    property bool fontStatusParsed: false
    property bool fontStatusPending: false
    property int fontStatusRetryAttempts: 0
    property string fontPreviewState: "none"
    property string fontPreviewToken: ""
    property string fontPreviewFamily: ""
    property real fontPreviewScale: 1.0
    property int fontPreviewRemaining: 0
    property string fontPreviewDetail: ""
    property string fontActionKind: ""
    property string fontActionToken: ""
    property string fontActionFamily: ""
    property real fontActionScale: 1.0
    property string fontActionError: ""
    property bool fontActionSucceeded: false
    property string personalizationProviderState: "idle"
    property string personalizationProviderDetail: "Desktop personalization has not been loaded"
    property string personalizationMutationState: "idle"
    property string personalizationMutationDetail: "Desktop personalization changes have not been checked"
    property string personalizationRepairState: "unavailable"
    property string personalizationRepairDetail: "Personalization state does not need repair"
    property var personalizationSelections: ({})
    property var personalizationActionReadiness: ({})
    property var personalizationDelegates: ({})
    property bool personalizationBusy: false
    property bool personalizationStatusParsed: false
    property bool personalizationStatusPending: false
    property bool xsettingsWatchReady: false
    property bool xsettingsWatchProtocolSeen: false
    property bool xsettingsWatchSawEvent: false
    property bool xsettingsWatchFailed: false
    readonly property bool personalizationStatusBusy: personalizationStatusProcess.running
    property string personalizationActionKind: ""
    property string personalizationActionCapability: ""
    property string personalizationActionValue: ""
    property string personalizationActionError: ""
    property bool personalizationActionSucceeded: false
    property string message: ""
    property string messageSeverity: "idle"
    property string previewState: "none"
    property string previewToken: ""
    property string previewTheme: ""
    property int previewRemaining: 0
    property string previewDetail: ""
    property int previewZeroRetryAttempts: 0
    property bool previewStatusParsed: false
    property bool previewStatusManualOnly: false
    property string recoveryState: "none"
    property string recoveryAction: ""
    property string recoveryTheme: ""
    property int snapshotGeneration: 0
    property int snapshotRunGeneration: 0
    property bool snapshotPending: false
    property bool snapshotParsed: false
    property string actionKind: ""
    property string actionTheme: ""
    property string actionToken: ""
    property string actionError: ""
    property bool actionSucceeded: false

    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string configuredConfigHome: Quickshell.env("XDG_CONFIG_HOME")
    readonly property string configuredDataHome: Quickshell.env("XDG_DATA_HOME")
    readonly property string configuredStateHome: Quickshell.env("XDG_STATE_HOME")
    readonly property string configHome: root.configuredConfigHome.startsWith("/")
        ? root.configuredConfigHome : root.homeDir + "/.config"
    readonly property string dataHome: root.configuredDataHome.startsWith("/")
        ? root.configuredDataHome : root.homeDir + "/.local/share"
    readonly property string stateHome: root.configuredStateHome.startsWith("/")
        ? root.configuredStateHome : root.homeDir + "/.local/state"
    readonly property string themesPath: root.configHome + "/dwm-titus/themes.toml"
    readonly property string wallpaperConfigPath: root.configHome + "/dwm-titus/wallpaper.conf"
    readonly property string fontConfigPath: root.configHome + "/dwm-titus/font.conf"
    readonly property string fontPreviewPath: root.stateHome
        + "/dwm-titus/appearance/font/preview.current"
    readonly property var fontCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "font";
    })
    readonly property string managedThemesPath: root.dataHome + "/dwm-titus/config/themes.toml"
    readonly property var wallpaperCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "wallpaper";
    })
    readonly property var cursorCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "cursor";
    })
    readonly property var iconCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "icon";
    })
    readonly property var gtkCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "gtk";
    })
    readonly property var qtCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "qt";
    })
    readonly property var desktopTextScaleCandidates: [
        { "token": "0.75", "label": "75%", "state": "available" },
        { "token": "0.875", "label": "87.5%", "state": "available" },
        { "token": "1.0", "label": "100%", "state": "available" },
        { "token": "1.125", "label": "112.5%", "state": "available" },
        { "token": "1.25", "label": "125%", "state": "available" },
        { "token": "1.5", "label": "150%", "state": "available" },
        { "token": "1.75", "label": "175%", "state": "available" },
        { "token": "2.0", "label": "200%", "state": "available" }
    ]
    readonly property var integrationWatchPaths: [
        root.configHome + "/alacritty/active-theme.toml",
        root.configHome + "/alacritty/alacritty.toml",
        root.configHome + "/kitty/active-theme.conf",
        root.configHome + "/kitty/kitty.conf",
        root.configHome + "/gtk-3.0/settings.ini",
        root.configHome + "/gtk-4.0/settings.ini",
        (Quickshell.env("HOME") || "") + "/.gtkrc-2.0",
        root.configHome + "/dwm-titus/cursor.Xresources",
        root.configHome + "/dwm-titus/theme-env.sh",
        root.configHome + "/qt5ct/qt5ct.conf",
        root.configHome + "/qt6ct/qt6ct.conf",
        root.configHome + "/dconf/user"
    ]
    readonly property var statusWatchPaths: [
        root.stateHome + "/dwm-titus/appearance/preview.current",
        root.stateHome + "/dwm-titus/appearance/transaction.meta",
        root.stateHome + "/dwm-titus/appearance/transaction.failed",
        root.stateHome + "/dwm-titus/appearance/integration-transaction",
        root.wallpaperConfigPath,
        root.configHome + "/dwm-titus/personalization.conf",
        root.stateHome + "/dwm-titus/appearance/wallpaper/preview.current"
    ]
    readonly property var requiredIntegrationIds: [
        "gtk", "qt", "cursor", "alacritty", "kitty", "compositor"
    ]
    readonly property var requiredColors: [
        "background", "bar-background", "surface", "surface-hover", "surface-active",
        "border", "border-strong", "text", "text-strong", "text-muted", "placeholder",
        "accent", "accent-secondary", "accent-text", "success", "warning", "danger",
        "danger-surface"
    ]
    readonly property string applicationState: {
        if (root.providerState === "idle") return "idle";
        let appliedTheme = null;
        for (const theme of root.themes) {
            if (theme.id === root.resolvedTheme) {
                appliedTheme = theme;
                break;
            }
        }
        if (root.providerState === "unavailable" || root.activeState === "unresolved"
                || appliedTheme === null || !appliedTheme.valid) return "unavailable";
        if (root.activeState === "recovery") return "partial";
        for (const integration of root.integrations) {
            if (integration.state !== "available") return "partial";
        }
        if (root.wallpaperProviderState !== "available"
                || root.wallpaperState !== "available") return "partial";
        if (root.fontProviderState !== "available"
                || root.fontState !== "available") return "partial";
        if (root.personalizationProviderState !== "available") return "partial";
        for (const capability of ["font", "text-size", "cursor", "icon", "gtk", "qt"]) {
            if (root.personalizationEffectiveState(capability) !== "available") return "partial";
        }
        return "available";
    }

    function validState(value) {
        return value === "available" || value === "partial" || value === "restricted"
            || value === "unavailable";
    }

    function validInventoryCapability(value) {
        return value === "wallpaper" || value === "font" || value === "cursor"
            || value === "icon" || value === "gtk" || value === "qt"
            || value === "compositor";
    }

    function validInventoryField(value, allowEmpty) {
        return typeof value === "string" && value.indexOf("\t") < 0
            && value.indexOf("\n") < 0 && value.length <= 4095
            && (allowEmpty || value.length > 0);
    }

    function validWallpaperFit(value) {
        return value === "center" || value === "fill" || value === "max"
            || value === "scale" || value === "tile";
    }

    function validFontScale(value) {
        return value === "0.80" || value === "0.90" || value === "1.00"
            || value === "1.10" || value === "1.25" || value === "1.50";
    }

    function validPersonalizationCapability(value) {
        return value === "font" || value === "text-size" || value === "cursor"
            || value === "icon" || value === "gtk" || value === "qt";
    }

    function validDesktopTextScale(value) {
        return value === "0.75" || value === "0.875" || value === "1.0"
            || value === "1.125" || value === "1.25" || value === "1.5"
            || value === "1.75" || value === "2.0";
    }

    function validPersonalizationOption(capability, value) {
        if (value === "unknown") return true;
        if (capability === "font" || capability === "icon")
            return value === "follow-system" || root.validInventoryField(value, false);
        if (capability === "text-size")
            return value === "follow-system" || root.validDesktopTextScale(value);
        if (capability === "cursor" || capability === "gtk")
            return value === "follow-theme" || root.validInventoryField(value, false);
        if (capability === "qt")
            return value === "follow-theme" || value === "gtk3"
                || value === "qt6ct" || value === "qt5ct";
        return false;
    }

    function personalizationSelection(capability) {
        return root.personalizationSelections[capability] || {
            "id": capability, "state": "unavailable", "value": "", "option": "",
            "detail": "Desktop personalization state has not been loaded"
        };
    }

    function personalizationReadiness(capability) {
        return root.personalizationActionReadiness[capability] || {
            "id": capability, "apply": "unavailable", "reset": "unavailable",
            "detail": "Desktop personalization action readiness has not been loaded"
        };
    }

    function inventorySelection(capability) {
        return root.inventorySelections[capability] || {
            "id": capability, "state": "unavailable", "value": "", "option": "",
            "detail": "Appearance inventory state has not been loaded"
        };
    }

    function personalizationEffectiveState(capability) {
        if (!root.personalizationStatusParsed) return "unavailable";
        const personalizationState = root.personalizationSelection(capability).state;
        if (capability === "text-size") return personalizationState;
        const inventoryState = root.inventorySelection(capability).state;
        const savedState = root.personalizationSavedAssetState(capability);
        const severity = { "idle": 0, "available": 1, "partial": 2,
            "restricted": 3, "unavailable": 4 };
        const inventorySeverity = severity[inventoryState] === undefined ? 4
            : severity[inventoryState];
        const personalizationSeverity = severity[personalizationState] === undefined ? 4
            : severity[personalizationState];
        let result = inventorySeverity > personalizationSeverity
            ? inventoryState : personalizationState;
        if (severity[savedState] > severity[result]) result = savedState;
        return result;
    }

    function personalizationEffectiveDetail(capability) {
        const selection = root.personalizationSelection(capability);
        if (capability === "text-size") return selection.detail;
        const inventory = root.inventorySelection(capability);
        let detail = inventory.state === "available" ? selection.detail
            : selection.detail + " / " + inventory.detail;
        const savedState = root.personalizationSavedAssetState(capability);
        if (savedState !== "available")
            detail += savedState === "partial" ? " / Saved override asset is incomplete"
                : " / Saved override asset is unavailable; reset or choose an installed option";
        return detail;
    }

    function personalizationSavedAssetState(capability) {
        const option = root.personalizationSelection(capability).option;
        if (capability === "text-size" || option === "follow-system"
                || option === "follow-theme") return "available";
        for (const candidate of root.personalizationCandidates(capability, 24)) {
            if (candidate.token === option) return candidate.state;
        }
        return "unavailable";
    }

    function personalizationCandidates(capability, limit) {
        const source = capability === "font" ? root.fontCandidates
            : capability === "cursor" ? root.cursorCandidates
                : capability === "icon" ? root.iconCandidates
                    : capability === "gtk" ? root.gtkCandidates
                        : capability === "qt" ? root.qtCandidates : [];
        const boundedLimit = Math.max(1, Math.min(24, Math.floor(limit)));
        const result = [];
        const seen = [];
        const preferred = [root.inventorySelection(capability).value,
            root.personalizationSelection(capability).option];
        for (const token of preferred) {
            if (token === "follow-system" || token === "follow-theme" || token === "unknown"
                    || token.length === 0 || seen.indexOf(token) >= 0) continue;
            for (const candidate of source) {
                if (candidate.token !== token) continue;
                result.push(candidate);
                seen.push(token);
                break;
            }
        }
        for (const candidate of source) {
            if (result.length >= boundedLimit) break;
            if (seen.indexOf(candidate.token) >= 0) continue;
            result.push(candidate);
            seen.push(candidate.token);
        }
        return result;
    }

    function validThemeName(value) {
        // Match dwm-settings-theme's public identifier contract exactly.
        return typeof value === "string" && /^[A-Za-z0-9._-]{1,505}$/.test(value);
    }

    function validProviderThemeId(value) {
        // The read-only provider also owns a synthetic legacy palette record.
        return value === "@legacy-colors" || root.validThemeName(value);
    }

    function validProviderActiveLabel(value) {
        // Recovery snapshots preserve an invalid selected value for diagnosis.
        // The provider rejects physical lines of 4095 bytes or more.
        return typeof value === "string" && value.length > 0 && value.length < 4095;
    }

    function validActiveState(value) {
        return value === "selected" || value === "recovery" || value === "unresolved";
    }

    function validColor(value) {
        return typeof value === "string" && /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(value);
    }

    function colorsComplete(values) {
        for (const name of root.requiredColors) {
            if (!root.validColor(values[name])) return false;
        }
        return true;
    }

    function integrationsComplete(values) {
        const seen = {};
        for (const integration of values) {
            if (root.requiredIntegrationIds.indexOf(integration.id) < 0 || seen[integration.id])
                return false;
            seen[integration.id] = true;
        }
        for (const id of root.requiredIntegrationIds) {
            if (!seen[id]) return false;
        }
        return true;
    }

    function themeById(themeId) {
        for (const theme of root.themes) {
            if (theme.id === themeId) return theme;
        }
        return null;
    }

    function clearSnapshot(detail) {
        root.providerState = "unavailable";
        root.providerDetail = detail;
        root.sourceKind = "none";
        root.sourcePath = "";
        root.activeTheme = "none";
        root.activeState = "recovery";
        root.themes = [];
        root.integrations = [];
        root.errors = [];
    }

    function clearInventory(detail) {
        root.inventoryProviderState = "unavailable";
        root.inventoryProviderDetail = detail;
        root.inventoryWatchState = "unavailable";
        root.inventoryWatchDetail = detail;
        root.inventorySelections = {};
        root.inventoryCandidates = [];
        root.inventoryWatchReady = false;
        root.inventoryWatchSawEvent = false;
        root.inventoryWatchFailed = true;
        root.inventoryWatchRestartPending = false;
        root.compositorWatchReady = false;
        inventoryWatchExitSettleTimer.stop();
        inventoryWatchRestartTimer.stop();
        inventoryWatchProcess.running = false;
        compositorWatchRestartTimer.stop();
        compositorWatchProcess.running = false;
    }

    function parseInventory(text) {
        if (root.inventoryRunGeneration !== root.inventoryGeneration) return;
        let protocolValid = false;
        let provider = null;
        let watch = null;
        const selections = {};
        const candidates = [];
        const candidateKeys = {};

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "appearance-inventory-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "appearance-inventory" && root.validState(fields[2])
                    && fields[3] === "read-only" && provider === null) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "watch" && fields.length === 4
                    && (fields[1] === "available" || fields[1] === "unavailable")
                    && fields[2] === "inotifywait" && watch === null) {
                watch = { "state": fields[1], "detail": fields[3] };
            } else if (fields[0] === "selection" && fields.length === 6
                    && root.validInventoryCapability(fields[1]) && root.validState(fields[2])
                    && root.validInventoryField(fields[3], true)
                    && root.validInventoryField(fields[4], true)
                    && root.validInventoryField(fields[5], false)
                    && selections[fields[1]] === undefined) {
                selections[fields[1]] = { "id": fields[1], "state": fields[2],
                    "value": fields[3], "option": fields[4], "detail": fields[5] };
            } else if (fields[0] === "candidate" && fields.length === 6
                    && root.validInventoryCapability(fields[1])
                    && (fields[2] === "available" || fields[2] === "partial")
                    && root.validInventoryField(fields[3], false)
                    && root.validInventoryField(fields[4], false)
                    && root.validInventoryField(fields[5], false)
                    && candidates.length < 1792
                    && candidateKeys[fields[1] + "\t" + fields[3]] === undefined) {
                candidateKeys[fields[1] + "\t" + fields[3]] = true;
                candidates.push({ "id": fields[1], "state": fields[2], "token": fields[3],
                    "label": fields[4], "detail": fields[5] });
            }
        }

        const required = ["wallpaper", "font", "cursor", "icon", "gtk", "qt", "compositor"];
        let complete = provider !== null && watch !== null;
        for (const capability of required) {
            if (selections[capability] === undefined) complete = false;
        }
        if (!protocolValid || !complete) {
            root.clearInventory("Appearance inventory returned an unsupported response");
            return;
        }
        root.inventoryParsed = true;
        root.inventoryProviderState = provider.state;
        root.inventoryProviderDetail = provider.detail;
        if (!root.inventoryWatchFailed) {
            root.inventoryWatchState = watch.state;
            root.inventoryWatchDetail = watch.detail;
        }
        root.inventorySelections = selections;
        root.inventoryCandidates = candidates;
        root.compositorWatchReady = selections.compositor.value === "picom";
        if (root.settingsVisible && !root.inventoryWatchFailed && watch.state === "available")
            root.startInventoryWatcher();
        if (watch.state !== "available") {
            inventoryWatchRestartTimer.stop();
            inventoryWatchProcess.running = false;
        }
        if (root.settingsVisible && root.compositorWatchReady && !compositorWatchProcess.running)
            compositorWatchProcess.running = true;
        if (!root.compositorWatchReady) {
            compositorWatchRestartTimer.stop();
            compositorWatchProcess.running = false;
        }
    }

    function parseSnapshot(text) {
        if (root.snapshotRunGeneration !== root.snapshotGeneration) return;
        let protocolValid = false;
        let provider = null;
        let source = null;
        let active = null;
        const themes = [];
        const colors = {};
        const integrations = [];
        const errors = [];

        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "appearance-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "appearance" && root.validState(fields[2])
                    && fields[3] === "read-only") {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "source" && fields.length === 3
                    && ((fields[1] === "user" || fields[1] === "managed")
                        || (fields[1] === "none" && fields[2] === "unavailable"))) {
                source = { "kind": fields[1], "path": fields[2] };
            } else if (fields[0] === "active" && fields.length === 4
                    && root.validProviderActiveLabel(fields[1])
                    && root.validProviderThemeId(fields[2])
                    && root.validActiveState(fields[3])) {
                active = { "theme": fields[1], "resolved": fields[2], "state": fields[3] };
            } else if (fields[0] === "theme" && fields.length === 7
                    && root.validProviderThemeId(fields[1])
                    && (fields[3] === "valid" || fields[3] === "invalid")
                    && (fields[3] === "invalid"
                        || fields[4] === "true" || fields[4] === "false")) {
                themes.push({
                    "id": fields[1], "state": fields[2], "valid": fields[3] === "valid",
                    "mutable": root.validThemeName(fields[1]), "dark": fields[4] !== "false",
                    "gtkTheme": fields[5], "detail": fields[6]
                });
            } else if (fields[0] === "color" && fields.length === 4
                    && root.validColor(fields[2])) {
                colors[fields[1]] = fields[2];
            } else if (fields[0] === "integration" && fields.length === 5
                    && root.validState(fields[2])) {
                integrations.push({
                    "id": fields[1], "state": fields[2], "value": fields[3], "detail": fields[4]
                });
            } else if (fields[0] === "error" && fields.length === 4) {
                errors.push({ "scope": fields[1], "code": fields[2], "detail": fields[3] });
            }
        }

        const snapshotComplete = provider !== null && (provider.state === "unavailable"
            || (themes.length > 0 && root.colorsComplete(colors)
                && root.integrationsComplete(integrations)));
        if (!protocolValid || provider === null || source === null || active === null
                || !snapshotComplete) {
            root.clearSnapshot("Appearance provider returned an unsupported response");
            return;
        }

        root.snapshotParsed = true;
        root.providerState = provider.state;
        root.providerDetail = provider.detail;
        root.sourceKind = source.kind;
        root.sourcePath = source.path;
        root.activeTheme = active.theme;
        root.resolvedTheme = active.resolved;
        root.activeState = active.state;
        root.themes = themes;
        root.colors = colors;
        root.integrations = integrations;
        root.errors = errors;

        if (root.colorsComplete(colors)) {
            let darkMode = Theme.dark;
            for (const theme of themes) {
                if (theme.id === active.resolved) {
                    darkMode = theme.dark;
                    break;
                }
            }
            Theme.applyAppearanceColors(colors, darkMode);
        }
    }

    function refreshSnapshot() {
        root.snapshotGeneration++;
        if (snapshotProcess.running) {
            root.snapshotPending = true;
            return;
        }
        root.snapshotPending = false;
        root.snapshotRunGeneration = root.snapshotGeneration;
        root.snapshotParsed = false;
        snapshotProcess.running = true;
    }

    function refreshPreviewStatus(force) {
        if (root.previewStatusManualOnly && force !== true) return;
        if (!previewStatusProcess.running && !actionProcess.running) {
            root.previewStatusParsed = false;
            previewStatusProcess.running = true;
        }
    }

    function refreshRecoveryStatus() {
        if (!recoveryStatusProcess.running && !actionProcess.running)
            recoveryStatusProcess.running = true;
    }

    function refreshMutationReadiness() {
        if (!readinessProcess.running && !actionProcess.running)
            readinessProcess.running = true;
    }

    function refreshWallpaperStatus() {
        if (!root.settingsVisible) return;
        if (wallpaperReadinessProcess.running || wallpaperStatusProcess.running
                || wallpaperActionProcess.running || inventoryProcess.running) {
            root.wallpaperStatusPending = true;
            return;
        }
        root.wallpaperStatusPending = false;
        root.wallpaperStatusParsed = false;
        wallpaperStatusProcess.running = true;
    }

    function refreshFontStatus() {
        if (!fontReadinessProcess.running && !fontActionProcess.running) {
            root.fontMutationReady = false;
            fontReadinessProcess.running = true;
        }
        if (fontStatusProcess.running || fontActionProcess.running) {
            root.fontStatusPending = true;
            return;
        }
        root.fontStatusPending = false;
        root.fontStatusParsed = false;
        fontStatusProcess.running = true;
    }

    function clearPersonalizationStatus(detail) {
        root.personalizationStatusParsed = false;
        root.personalizationProviderState = "unavailable";
        root.personalizationProviderDetail = detail;
        root.personalizationMutationState = "unavailable";
        root.personalizationMutationDetail = detail;
        root.personalizationRepairState = "unavailable";
        root.personalizationRepairDetail = detail;
        root.personalizationSelections = {};
        root.personalizationActionReadiness = {};
        root.personalizationDelegates = {};
        root.xsettingsWatchReady = false;
        root.xsettingsWatchProtocolSeen = false;
        root.xsettingsWatchSawEvent = false;
        xsettingsWatchProcess.running = false;
    }

    function parsePersonalizationStatus(text) {
        let protocolSeen = false;
        let protocolValid = false;
        let provider = null;
        let mutation = null;
        let repair = null;
        let xsettingsWatch = null;
        const selections = {};
        const actionReadiness = {};
        const delegates = {};
        let completeSeen = false;
        let invalid = false;
        for (const line of text.trim().split("\n")) {
            if (line.length === 0) continue;
            const fields = line.split("\t");
            if (fields[0] === "personalization-protocol") {
                if (protocolSeen) invalid = true;
                protocolSeen = true;
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "personalization" && root.validState(fields[2])
                    && fields[3] === "user-session" && provider === null
                    && root.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "mutation" && fields.length === 3
                    && root.validState(fields[1]) && mutation === null
                    && root.validInventoryField(fields[2], false)) {
                mutation = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "repair" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "restricted"
                        || fields[1] === "unavailable")
                    && root.validInventoryField(fields[2], false) && repair === null) {
                repair = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "watch-readiness" && fields.length === 4
                    && fields[1] === "text-size"
                    && (fields[2] === "available" || fields[2] === "unavailable")
                    && root.validInventoryField(fields[3], false) && xsettingsWatch === null) {
                xsettingsWatch = { "state": fields[2], "detail": fields[3] };
            } else if (fields[0] === "selection" && fields.length === 6
                    && root.validPersonalizationCapability(fields[1])
                    && root.validState(fields[2])
                    && root.validInventoryField(fields[3], true)
                    && root.validPersonalizationOption(fields[1], fields[4])
                    && root.validInventoryField(fields[5], false)
                    && selections[fields[1]] === undefined) {
                selections[fields[1]] = { "id": fields[1], "state": fields[2],
                    "value": fields[3], "option": fields[4], "detail": fields[5] };
            } else if (fields[0] === "action-readiness" && fields.length === 5
                    && root.validPersonalizationCapability(fields[1])
                    && (fields[2] === "available" || fields[2] === "restricted"
                        || fields[2] === "unavailable")
                    && (fields[3] === "available" || fields[3] === "restricted"
                        || fields[3] === "unavailable")
                    && root.validInventoryField(fields[4], false)
                    && actionReadiness[fields[1]] === undefined) {
                actionReadiness[fields[1]] = { "id": fields[1], "apply": fields[2],
                    "reset": fields[3], "detail": fields[4] };
            } else if (fields[0] === "delegate" && fields.length === 5
                    && (fields[1] === "gtk" || fields[1] === "qt")
                    && (fields[2] === "available" || fields[2] === "unavailable")
                    && root.validInventoryField(fields[3], fields[2] === "unavailable")
                    && root.validInventoryField(fields[4], false)
                    && delegates[fields[1]] === undefined) {
                delegates[fields[1]] = { "state": fields[2], "tool": fields[3],
                    "detail": fields[4] };
            } else if (fields[0] === "complete" && fields.length === 2
                    && fields[1] === "status" && !completeSeen) {
                completeSeen = true;
            } else if (["personalization-protocol", "provider", "mutation", "repair", "watch-readiness", "selection",
                    "action-readiness", "delegate", "complete"].indexOf(fields[0]) >= 0) {
                // Version 1 is append-only: reject malformed required records, but let a
                // newer helper add records that this client does not need yet.
                invalid = true;
            }
        }
        const required = ["font", "text-size", "cursor", "icon", "gtk", "qt"];
        for (const capability of required) {
            if (selections[capability] === undefined) invalid = true;
            if (actionReadiness[capability] === undefined) invalid = true;
        }
        if (delegates.gtk === undefined || delegates.qt === undefined) invalid = true;
        if (invalid || !protocolValid || !completeSeen || provider === null || mutation === null
                || repair === null || xsettingsWatch === null) {
            root.clearPersonalizationStatus("Personalization helper returned an unsupported response");
            return;
        }
        root.personalizationStatusParsed = true;
        root.personalizationProviderState = provider.state;
        root.personalizationProviderDetail = provider.detail;
        root.personalizationMutationState = mutation.state;
        root.personalizationMutationDetail = mutation.detail;
        root.personalizationRepairState = repair.state;
        root.personalizationRepairDetail = repair.detail;
        root.personalizationSelections = selections;
        root.personalizationActionReadiness = actionReadiness;
        root.personalizationDelegates = delegates;
        root.xsettingsWatchReady = xsettingsWatch.state === "available"
            && !root.xsettingsWatchFailed;
        if (root.settingsVisible && root.xsettingsWatchReady && !xsettingsWatchProcess.running)
            xsettingsWatchProcess.running = true;
        if (!root.xsettingsWatchReady) {
            xsettingsWatchProcess.running = false;
        }
    }

    function refreshPersonalizationStatus() {
        if (!root.settingsVisible) return;
        if (personalizationStatusProcess.running || personalizationActionProcess.running) {
            root.personalizationStatusPending = true;
            return;
        }
        root.personalizationStatusPending = false;
        root.personalizationStatusParsed = false;
        personalizationStatusProcess.running = true;
    }

    function refreshInventory(allowUnwatched) {
        if (!root.settingsVisible) return;
        if (!root.inventoryWatchReady && !root.inventoryWatchFailed
                && allowUnwatched !== true) {
            root.inventoryPending = true;
            return;
        }
        if (wallpaperStatusProcess.running || wallpaperActionProcess.running) {
            root.inventoryPending = true;
            root.inventoryPendingAllowUnwatched = root.inventoryPendingAllowUnwatched
                || allowUnwatched === true;
            return;
        }
        root.inventoryGeneration++;
        if (inventoryProcess.running) {
            root.inventoryPending = true;
            root.inventoryPendingAllowUnwatched = root.inventoryPendingAllowUnwatched
                || allowUnwatched === true;
            return;
        }
        root.inventoryPending = false;
        root.inventoryPendingAllowUnwatched = false;
        root.inventoryRunGeneration = root.inventoryGeneration;
        root.inventoryParsed = false;
        inventoryProcess.running = true;
    }

    function refreshAll(forcePreviewStatus) {
        root.refreshSnapshot();
        root.refreshInventory();
        root.refreshPreviewStatus(forcePreviewStatus === true);
        root.refreshRecoveryStatus();
        root.refreshMutationReadiness();
        root.refreshWallpaperStatus();
        root.refreshFontStatus();
        root.refreshPersonalizationStatus();
    }

    function openSettings() {
        root.settingsVisible = true;
        root.inventoryPending = true;
        root.inventoryPendingAllowUnwatched = false;
        root.inventoryWatchReady = false;
        root.inventoryWatchSawEvent = false;
        root.inventoryWatchFailed = false;
        root.xsettingsWatchFailed = false;
        if (!wallpaperReadinessProcess.running)
            wallpaperReadinessProcess.running = true;
        root.startInventoryWatcher(true);
        root.refreshAll(true);
    }

    function startInventoryWatcher(restartIfRunning) {
        if (!root.settingsVisible) return;
        if (inventoryWatchExitSettleTimer.running) {
            if (restartIfRunning === true) root.inventoryWatchRestartPending = true;
            return;
        }
        if (inventoryWatchProcess.running) {
            if (restartIfRunning === true) root.inventoryWatchRestartPending = true;
            return;
        }
        root.inventoryWatchRestartPending = false;
        root.inventoryWatchSawEvent = false;
        inventoryWatchProcess.running = true;
    }

    function finishInventoryWatcherExit() {
        if (!root.settingsVisible || inventoryWatchProcess.running) return;
        if (root.inventoryWatchRestartPending && !root.inventoryWatchFailed) {
            root.inventoryWatchRestartPending = false;
            if (root.inventoryWatchSawEvent) inventoryWatchRestartTimer.restart();
            else Qt.callLater(root.startInventoryWatcher);
        } else if (!root.inventoryWatchSawEvent && !root.inventoryWatchFailed) {
            const error = inventoryWatchError.text.trim();
            root.inventoryWatchFailed = true;
            root.inventoryWatchState = "unavailable";
            root.inventoryWatchDetail = error.length > 0 ? error
                : "Live appearance asset watching stopped unexpectedly";
            root.refreshInventory(true);
        } else if (!root.inventoryWatchFailed && (root.inventoryWatchState === "available"
                || root.inventoryWatchState === "idle")) {
            inventoryWatchRestartTimer.restart();
        }
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.inventoryGeneration++;
        inventoryWatchExitSettleTimer.stop();
        inventoryWatchRestartTimer.stop();
        root.inventoryWatchRestartPending = false;
        inventoryWatchProcess.running = false;
        root.inventoryWatchReady = false;
        root.inventoryWatchSawEvent = false;
        compositorWatchSettleTimer.stop();
        compositorWatchRestartTimer.stop();
        compositorWatchProcess.running = false;
        xsettingsWatchProcess.running = false;
        root.xsettingsWatchReady = false;
        root.xsettingsWatchProtocolSeen = false;
        root.xsettingsWatchSawEvent = false;
        root.xsettingsWatchFailed = false;
        inventoryProcess.running = false;
        wallpaperStatusProcess.running = false;
        personalizationStatusProcess.running = false;
        root.personalizationStatusPending = false;
        root.wallpaperStatusPending = false;
        root.inventoryPending = false;
        root.inventoryPendingAllowUnwatched = false;
    }

    function nextPreviewToken() {
        return "qs-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function runAction(action, args, theme, token) {
        if (root.busy || root.wallpaperBusy || root.fontBusy || root.personalizationBusy
                || actionProcess.running) {
            root.message = "Another appearance change is already in progress";
            root.messageSeverity = "warning";
            return;
        }
        root.busy = true;
        root.actionKind = action;
        root.actionTheme = theme || "";
        root.actionToken = token || "";
        root.actionError = "";
        root.actionSucceeded = false;
        root.message = "Applying appearance change...";
        root.messageSeverity = "idle";
        actionProcess.command = Commands.checkedCommand(Commands.settingsThemeCommand(action, args));
        actionProcess.running = true;
    }

    function startPreview(theme) {
        if (!root.mutationReady || !root.validThemeName(theme) || root.previewState !== "none"
                || root.recoveryState !== "none") return;
        const token = root.nextPreviewToken();
        root.runAction("preview", [token, "30", theme], theme, token);
    }

    function applyTheme(theme) {
        if (!root.mutationReady || !root.validThemeName(theme) || root.previewState !== "none"
                || root.recoveryState !== "none") return;
        root.runAction("apply", [theme], theme, "");
    }

    function resetTheme() {
        if (!root.mutationReady || root.previewState !== "none" || root.recoveryState !== "none") return;
        root.runAction("reset", [], "", "");
    }

    function keepPreview() {
        if (root.previewState !== "active" || !root.validThemeName(root.previewTheme)
                || root.previewToken.length === 0) return;
        root.runAction("keep", [root.previewToken], root.previewTheme, root.previewToken);
    }

    function revertPreview() {
        if ((root.previewState !== "active" && root.previewState !== "failed")
                || root.previewToken.length === 0) return;
        root.runAction("revert", [root.previewToken], root.previewTheme, root.previewToken);
    }

    function abandonPreview() {
        if (root.previewState !== "failed" || root.previewToken.length === 0) return;
        root.runAction("abandon", [root.previewToken], root.previewTheme, root.previewToken);
    }

    function recover() {
        if (root.recoveryState !== "available") return;
        root.runAction("recover", [], root.recoveryTheme, "");
    }

    function nextWallpaperPreviewToken() {
        return "wallpaper-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function nextFontPreviewToken() {
        return "font-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function clearFontStatus(detail) {
        root.fontStatusParsed = false;
        root.fontProviderState = "unavailable";
        root.fontProviderDetail = detail;
        root.fontState = "unavailable";
        root.fontDetail = detail;
        root.fontMutationReady = false;
        // Keep the last valid family and scale through a transient helper
        // failure. On first launch Theme already holds the safe Meslo/100%
        // defaults, so repainting is neither necessary nor desirable.
        if (!fontStatusRetryTimer.running && root.fontStatusRetryAttempts < 3) {
            root.fontStatusRetryAttempts++;
            fontStatusRetryTimer.restart();
        }
    }

    function parseFontStatus(text) {
        let protocolValid = false;
        let provider = null;
        let selection = null;
        let preview = null;
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "appearance-font-action-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "font" && root.validState(fields[2])
                    && fields[3] === "user-session"
                    && root.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "selection" && fields.length === 5
                    && root.validState(fields[1]) && root.validInventoryField(fields[2], false)
                    && root.validFontScale(fields[3])
                    && root.validInventoryField(fields[4], false)) {
                selection = { "state": fields[1], "family": fields[2],
                    "scale": Number(fields[3]), "detail": fields[4] };
            } else if (fields[0] === "preview" && fields.length === 7
                    && (fields[1] === "none" || fields[1] === "active" || fields[1] === "failed")
                    && root.validInventoryField(fields[2], true)
                    && root.validInventoryField(fields[3], true)
                    && (fields[4].length === 0 || root.validFontScale(fields[4]))
                    && /^[0-9]+$/.test(fields[5])
                    && root.validInventoryField(fields[6], false)) {
                preview = { "state": fields[1], "token": fields[2], "family": fields[3],
                    "scale": fields[4].length > 0 ? Number(fields[4]) : 1.0,
                    "remaining": Number(fields[5]), "detail": fields[6] };
            }
        }
        if (!protocolValid || provider === null || selection === null || preview === null) {
            root.clearFontStatus("Font helper returned an unsupported response");
            return;
        }
        const previewWasActive = root.fontPreviewState === "active";
        const previousRemaining = root.fontPreviewRemaining;
        root.fontStatusParsed = true;
        root.fontStatusRetryAttempts = 0;
        fontStatusRetryTimer.stop();
        root.fontProviderState = provider.state;
        root.fontProviderDetail = provider.detail;
        root.fontState = selection.state;
        root.fontFamily = selection.family;
        root.fontScale = selection.scale;
        root.fontDetail = selection.detail;
        root.fontPreviewState = preview.state;
        root.fontPreviewToken = preview.token;
        root.fontPreviewFamily = preview.family;
        root.fontPreviewScale = preview.scale;
        root.fontPreviewRemaining = preview.remaining;
        root.fontPreviewDetail = preview.detail;
        Theme.applyFontPreferences(root.fontFamily, root.fontScale);
        if (!previewWasActive && preview.state === "active") {
            root.message = "Font preview active; keep it within " + preview.remaining
                + (preview.remaining === 1 ? " second" : " seconds") + " or it will revert";
            root.messageSeverity = "warning";
        } else if (previewWasActive && preview.state === "none"
                && previousRemaining <= 1) {
            root.message = "Font preview expired and reverted automatically";
            root.messageSeverity = "warning";
        }
    }

    function runFontAction(action, args, family, scale, token) {
        if (root.fontBusy || fontActionProcess.running || fontStatusProcess.running
                || root.busy || root.wallpaperBusy || root.personalizationBusy) {
            root.message = "Another appearance change is already in progress";
            root.messageSeverity = "warning";
            return;
        }
        root.fontBusy = true;
        root.fontActionKind = action;
        root.fontActionFamily = family || "";
        root.fontActionScale = scale || 1.0;
        root.fontActionToken = token || "";
        root.fontActionError = "";
        root.fontActionSucceeded = false;
        root.message = "Applying font change...";
        root.messageSeverity = "idle";
        fontActionProcess.command = Commands.checkedCommand(Commands.settingsFontCommand(action, args));
        fontActionProcess.running = true;
    }

    function previewFont(family, scale) {
        const scaleArgument = Number(scale).toFixed(2);
        if (!root.fontMutationReady || fontReadinessProcess.running
                || !root.validInventoryField(family, false)
                || !root.validFontScale(scaleArgument) || root.fontPreviewState !== "none") return;
        const token = root.nextFontPreviewToken();
        root.runFontAction("preview", [token, "30", family, scaleArgument], family, scale, token);
    }

    function applyFont(family, scale) {
        const scaleArgument = Number(scale).toFixed(2);
        if (!root.fontMutationReady || fontReadinessProcess.running
                || !root.validInventoryField(family, false)
                || !root.validFontScale(scaleArgument) || root.fontPreviewState !== "none") return;
        root.runFontAction("apply", [family, scaleArgument], family, scale, "");
    }

    function resetFont() {
        if (!root.fontMutationReady || fontReadinessProcess.running
                || root.fontPreviewState !== "none") return;
        root.runFontAction("reset", [], "", 1.0, "");
    }

    function keepFontPreview() {
        if (root.fontPreviewState !== "active" || root.fontPreviewToken.length === 0) return;
        root.runFontAction("keep", [root.fontPreviewToken], root.fontPreviewFamily,
            root.fontPreviewScale, root.fontPreviewToken);
    }

    function revertFontPreview() {
        if ((root.fontPreviewState !== "active" && root.fontPreviewState !== "failed")
                || root.fontPreviewToken.length === 0) return;
        root.runFontAction("revert", [root.fontPreviewToken], root.fontPreviewFamily,
            root.fontPreviewScale, root.fontPreviewToken);
    }

    function abandonFontPreview() {
        if (root.fontPreviewState !== "failed" || root.fontPreviewToken.length === 0) return;
        root.runFontAction("abandon", [root.fontPreviewToken], root.fontPreviewFamily,
            root.fontPreviewScale, root.fontPreviewToken);
    }

    function parseFontAction(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "appearance-font-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (fields.length !== 2 || fields[0] !== "result") return;
        const expected = root.fontActionKind === "preview" ? "preview-started"
            : root.fontActionKind === "apply" ? "applied" : root.fontActionKind;
        root.fontActionSucceeded = fields[1] === expected;
    }

    function personalizationCandidateAvailable(capability, value) {
        if (capability === "text-size") return root.validDesktopTextScale(value);
        const candidates = root.personalizationCandidates(capability, 24);
        for (const candidate of candidates) {
            if (candidate.token === value && candidate.state === "available") return true;
        }
        return false;
    }

    function personalizationApplyReady(capability) {
        return root.personalizationReadiness(capability).apply === "available";
    }

    function personalizationResetReady(capability) {
        return root.personalizationReadiness(capability).reset === "available";
    }

    function runPersonalizationAction(action, capability, value) {
        if (root.personalizationBusy || personalizationActionProcess.running
                || personalizationStatusProcess.running || root.busy || root.wallpaperBusy
                || root.fontBusy) {
            root.message = "Another appearance change is already in progress";
            root.messageSeverity = "warning";
            return;
        }
        if (root.personalizationMutationState !== "available"
                || !root.validPersonalizationCapability(capability)
                || (action === "apply" && !root.personalizationApplyReady(capability))
                || (action === "reset" && !root.personalizationResetReady(capability))
                || root.previewState !== "none" || root.recoveryState !== "none") return;
        let args = [capability];
        if (action === "apply") {
            if (!root.personalizationCandidateAvailable(capability, value)) return;
            args.push(value);
        } else if (action !== "reset") {
            return;
        }
        root.personalizationBusy = true;
        root.personalizationActionKind = action;
        root.personalizationActionCapability = capability;
        root.personalizationActionValue = value || "";
        root.personalizationActionError = "";
        root.personalizationActionSucceeded = false;
        root.message = "Applying desktop personalization change...";
        root.messageSeverity = "idle";
        personalizationActionProcess.command = Commands.checkedCommand(
            Commands.settingsPersonalizationCommand(action, args));
        personalizationActionProcess.running = true;
    }

    function applyPersonalization(capability, value) {
        root.runPersonalizationAction("apply", capability, value);
    }

    function resetPersonalization(capability) {
        root.runPersonalizationAction("reset", capability, "");
    }

    function repairPersonalization() {
        if (root.personalizationRepairState !== "available" || root.personalizationBusy
                || personalizationActionProcess.running || personalizationStatusProcess.running
                || root.busy || root.wallpaperBusy || root.fontBusy
                || root.previewState !== "none" || root.recoveryState !== "none") return;
        root.personalizationBusy = true;
        root.personalizationActionKind = "repair";
        root.personalizationActionCapability = "all";
        root.personalizationActionValue = "follow-sources";
        root.personalizationActionError = "";
        root.personalizationActionSucceeded = false;
        root.message = "Repairing desktop personalization state...";
        root.messageSeverity = "idle";
        personalizationActionProcess.command = Commands.checkedCommand(
            Commands.settingsPersonalizationCommand("repair", []));
        personalizationActionProcess.running = true;
    }

    function delegatePersonalization(capability) {
        const record = root.personalizationDelegates[capability];
        if (!record || record.state !== "available" || root.personalizationBusy
                || root.busy || root.wallpaperBusy || root.fontBusy
                || root.previewState !== "none" || root.recoveryState !== "none") return;
        root.personalizationBusy = true;
        root.personalizationActionKind = "delegate";
        root.personalizationActionCapability = capability;
        root.personalizationActionValue = record.tool;
        root.personalizationActionError = "";
        root.personalizationActionSucceeded = false;
        root.message = "Requesting advanced " + capability.toUpperCase() + " settings...";
        root.messageSeverity = "idle";
        personalizationActionProcess.command = Commands.checkedCommand(
            Commands.settingsPersonalizationCommand("delegate", [capability]));
        personalizationActionProcess.running = true;
    }

    function parsePersonalizationAction(text) {
        const payload = text.endsWith("\n") ? text.slice(0, -1) : text;
        const lines = payload.split("\n");
        if (lines.length !== 2 || lines[0] !== "personalization-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (fields.length !== 4 || fields[0] !== "result"
                || fields[1] !== root.personalizationActionKind
                || fields[2] !== root.personalizationActionCapability) return;
        if (root.personalizationActionKind === "apply"
                || root.personalizationActionKind === "delegate")
            root.personalizationActionSucceeded = fields[3] === root.personalizationActionValue;
        else if (root.personalizationActionKind === "repair")
            root.personalizationActionSucceeded = fields[3] === "follow-sources";
        else root.personalizationActionSucceeded = fields[3] === (fields[2] === "cursor"
                || fields[2] === "gtk" || fields[2] === "qt" ? "follow-theme" : "follow-system");
    }

    function finishPersonalizationAction() {
        root.personalizationBusy = false;
        if (root.personalizationActionSucceeded) {
            root.message = root.personalizationActionKind === "delegate"
                ? "Advanced " + root.personalizationActionCapability.toUpperCase() + " editor launch requested"
                : root.personalizationActionKind === "repair"
                    ? "Personalization overrides repaired; controls are available again"
                : root.personalizationActionKind === "reset"
                    ? root.personalizationActionCapability + " reset to follow its source"
                    : root.personalizationActionCapability + " applied";
            root.messageSeverity = "success";
        } else {
            root.message = root.personalizationActionError.length > 0
                ? root.personalizationActionError
                : "Personalization helper did not confirm the requested change";
            root.messageSeverity = "danger";
        }
        if (root.settingsVisible) {
            Qt.callLater(root.refreshPersonalizationStatus);
            root.refreshInventory(true);
            root.refreshSnapshot();
        }
    }

    function finishFontAction() {
        root.fontBusy = false;
        if (root.fontActionSucceeded) {
            if (root.fontActionKind === "preview") {
                root.fontPreviewState = "active";
                root.fontPreviewToken = root.fontActionToken;
                root.fontPreviewFamily = root.fontActionFamily;
                root.fontPreviewScale = root.fontActionScale;
                root.fontPreviewRemaining = 30;
                root.fontPreviewDetail = "Automatic rollback is armed";
            } else if (root.fontActionKind === "keep" || root.fontActionKind === "revert"
                    || root.fontActionKind === "abandon") {
                root.fontPreviewState = "none";
                root.fontPreviewToken = "";
                root.fontPreviewFamily = "";
                root.fontPreviewScale = 1.0;
                root.fontPreviewRemaining = 0;
                root.fontPreviewDetail = "";
            }
            root.message = root.fontActionKind === "preview"
                ? "Font preview active; keep it within 30 seconds or it will revert"
                : root.fontActionKind === "keep" ? "Font preview kept"
                    : root.fontActionKind === "revert" ? "Font preview reverted"
                        : root.fontActionKind === "abandon" ? "External font state accepted"
                            : root.fontActionKind === "reset"
                                ? "Font reset to the managed shell default" : "Font applied";
            root.messageSeverity = root.fontActionKind === "preview" ? "warning" : "success";
        } else {
            root.message = root.fontActionError.length > 0 ? root.fontActionError
                : "Font helper did not confirm the requested change";
            root.messageSeverity = "danger";
        }
        Qt.callLater(root.refreshFontStatus);
        if (root.settingsVisible) root.refreshInventory(true);
    }

    function clearWallpaperStatus(detail) {
        const preservePreview = (root.wallpaperPreviewState === "active"
                || root.wallpaperPreviewState === "failed")
            && root.wallpaperPreviewToken.length > 0;
        root.wallpaperStatusParsed = false;
        root.wallpaperProviderState = "unavailable";
        root.wallpaperProviderDetail = detail;
        root.wallpaperState = "unavailable";
        root.wallpaperPath = "";
        root.wallpaperFit = "fill";
        root.wallpaperDetail = detail;
        root.wallpaperMutationState = "unavailable";
        root.wallpaperMutationReady = false;
        root.wallpaperMutationDetail = detail;
        root.wallpaperResetState = "unavailable";
        root.wallpaperResetReady = false;
        root.wallpaperResetDetail = detail;
        if (!preservePreview) {
            root.wallpaperPreviewState = "none";
            root.wallpaperPreviewToken = "";
            root.wallpaperPreviewRemaining = 0;
            root.wallpaperPreviewPath = "";
            root.wallpaperPreviewFit = "fill";
            root.wallpaperPreviewDetail = "";
        }
    }

    function parseWallpaperStatus(text) {
        let protocolValid = false;
        let provider = null;
        let selection = null;
        let mutation = null;
        let reset = { "state": "restricted",
            "detail": "Installed wallpaper helper does not report reset readiness" };
        let preview = null;
        for (const line of text.trim().split("\n")) {
            const fields = line.split("\t");
            if (fields[0] === "wallpaper-protocol") {
                protocolValid = fields.length === 3 && fields[1] === "1" && fields[2] === "0";
            } else if (fields[0] === "provider" && fields.length === 5
                    && fields[1] === "wallpaper" && root.validState(fields[2])
                    && fields[3] === "user-session" && root.validInventoryField(fields[4], false)) {
                provider = { "state": fields[2], "detail": fields[4] };
            } else if (fields[0] === "selection" && fields.length === 5
                    && root.validState(fields[1]) && root.validInventoryField(fields[2], true)
                    && root.validWallpaperFit(fields[3]) && root.validInventoryField(fields[4], false)) {
                selection = { "state": fields[1], "path": fields[2], "fit": fields[3],
                    "detail": fields[4] };
            } else if (fields[0] === "mutation" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "restricted")
                    && root.validInventoryField(fields[2], false)) {
                mutation = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "reset" && fields.length === 3
                    && (fields[1] === "available" || fields[1] === "restricted")
                    && root.validInventoryField(fields[2], false)) {
                reset = { "state": fields[1], "detail": fields[2] };
            } else if (fields[0] === "preview" && fields.length === 7
                    && (fields[1] === "none" || fields[1] === "active" || fields[1] === "failed")
                    && root.validInventoryField(fields[2], true) && /^[0-9]+$/.test(fields[3])
                    && root.validInventoryField(fields[4], true) && root.validWallpaperFit(fields[5])
                    && root.validInventoryField(fields[6], false)) {
                preview = { "state": fields[1], "token": fields[2], "remaining": Number(fields[3]),
                    "path": fields[4], "fit": fields[5], "detail": fields[6] };
            }
        }
        if (!protocolValid || provider === null || selection === null || mutation === null
                || preview === null) {
            root.clearWallpaperStatus("Wallpaper helper returned an unsupported response");
            return;
        }
        const previewWasActive = root.wallpaperPreviewState === "active";
        const previewRemainingBefore = root.wallpaperPreviewRemaining;
        root.wallpaperStatusParsed = true;
        root.wallpaperProviderState = provider.state;
        root.wallpaperProviderDetail = provider.detail;
        root.wallpaperState = selection.state;
        root.wallpaperPath = selection.path;
        root.wallpaperFit = selection.fit;
        root.wallpaperDetail = selection.detail;
        root.wallpaperMutationState = mutation.state;
        root.wallpaperMutationReady = mutation.state === "available";
        root.wallpaperMutationDetail = mutation.detail;
        root.wallpaperResetState = reset.state;
        root.wallpaperResetReady = reset.state === "available";
        root.wallpaperResetDetail = reset.detail;
        root.wallpaperPreviewState = preview.state;
        root.wallpaperPreviewToken = preview.token;
        root.wallpaperPreviewRemaining = preview.remaining;
        root.wallpaperPreviewPath = preview.path;
        root.wallpaperPreviewFit = preview.fit;
        root.wallpaperPreviewDetail = preview.detail;
        if (!previewWasActive && preview.state === "active") {
            root.message = "Wallpaper preview active; keep it within " + preview.remaining
                + (preview.remaining === 1 ? " second" : " seconds") + " or it will revert";
            root.messageSeverity = "warning";
        } else if (previewWasActive && preview.state === "none"
                && root.message.startsWith("Wallpaper preview active; keep it within ")
                && root.message.endsWith(" or it will revert")) {
            root.message = previewRemainingBefore <= 1
                ? "Wallpaper preview expired and reverted automatically"
                : "Wallpaper preview completed outside Settings";
            root.messageSeverity = previewRemainingBefore <= 1 ? "warning" : "idle";
        }
    }

    function runWallpaperAction(action, args, path, fit, token) {
        const previewDecision = root.wallpaperPreviewState === "active"
            && (action === "keep" || action === "revert");
        if (previewDecision && (inventoryProcess.running || root.inventoryPending
                || root.wallpaperStatusPending)
                && !root.wallpaperBusy && !wallpaperActionProcess.running
                && !wallpaperReadinessProcess.running && !wallpaperStatusProcess.running
                && !root.busy && !root.fontBusy && !root.personalizationBusy) {
            root.inventoryGeneration++;
            root.wallpaperStatusPending = false;
            root.inventoryPending = false;
            root.inventoryPendingAllowUnwatched = false;
            if (inventoryProcess.running) inventoryProcess.running = false;
        }
        if (root.wallpaperBusy || wallpaperActionProcess.running
                || wallpaperReadinessProcess.running || wallpaperStatusProcess.running
                || (!previewDecision && (inventoryProcess.running
                    || root.wallpaperStatusPending || root.inventoryPending))
                || (!previewDecision && inventoryWatchProcess.running
                    && !root.inventoryWatchReady)
                || root.busy || root.fontBusy || root.personalizationBusy) {
            root.message = "Another appearance change is already in progress";
            root.messageSeverity = "warning";
            return;
        }
        root.wallpaperBusy = true;
        root.wallpaperActionKind = action;
        root.wallpaperActionPath = path || "";
        root.wallpaperActionFit = fit || "fill";
        root.wallpaperActionResultState = "";
        root.wallpaperActionToken = token || "";
        root.wallpaperActionError = "";
        root.wallpaperActionSucceeded = false;
        root.message = "Applying wallpaper change...";
        root.messageSeverity = "idle";
        wallpaperActionProcess.command = Commands.checkedCommand(
            Commands.settingsWallpaperCommand(action === "reconcile" ? "status" : action, args));
        wallpaperActionProcess.running = true;
    }

    function previewWallpaper(path, fit) {
        if (!root.wallpaperMutationReady || !root.validInventoryField(path, false)
                || !root.validWallpaperFit(fit) || root.wallpaperPreviewState !== "none") return;
        const token = root.nextWallpaperPreviewToken();
        root.runWallpaperAction("preview", [token, "30", path, fit], path, fit, token);
    }

    function applyWallpaper(path, fit) {
        if (!root.wallpaperMutationReady || !root.validInventoryField(path, false)
                || !root.validWallpaperFit(fit) || root.wallpaperPreviewState !== "none") return;
        root.runWallpaperAction("apply", [path, fit], path, fit, "");
    }

    function resetWallpaper() {
        if (!root.wallpaperResetReady || root.wallpaperPreviewState !== "none") return;
        root.runWallpaperAction("reset", [], "", "fill", "");
    }

    function keepWallpaperPreview() {
        if (root.wallpaperPreviewState !== "active" || root.wallpaperPreviewToken.length === 0) return;
        root.runWallpaperAction("keep", [root.wallpaperPreviewToken], root.wallpaperPreviewPath,
            root.wallpaperPreviewFit, root.wallpaperPreviewToken);
    }

    function revertWallpaperPreview() {
        if ((root.wallpaperPreviewState !== "active" && root.wallpaperPreviewState !== "failed")
                || root.wallpaperPreviewToken.length === 0) return;
        root.runWallpaperAction("revert", [root.wallpaperPreviewToken], root.wallpaperPreviewPath,
            root.wallpaperPreviewFit, root.wallpaperPreviewToken);
    }

    function abandonWallpaperPreview() {
        if (root.wallpaperPreviewState !== "failed" || root.wallpaperPreviewToken.length === 0) return;
        root.runWallpaperAction("abandon", [root.wallpaperPreviewToken], root.wallpaperPreviewPath,
            root.wallpaperPreviewFit, root.wallpaperPreviewToken);
    }

    function reconcileWallpaperPreview() {
        if (root.wallpaperPreviewState !== "failed") return;
        root.runWallpaperAction("reconcile", [], root.wallpaperPreviewPath,
            root.wallpaperPreviewFit, root.wallpaperPreviewToken);
    }

    function parseWallpaperAction(text) {
        if (root.wallpaperActionKind === "reconcile") {
            root.wallpaperStatusParsed = false;
            root.parseWallpaperStatus(text);
            root.wallpaperActionSucceeded = root.wallpaperStatusParsed;
            return;
        }
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "wallpaper-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (root.wallpaperActionKind === "preview") {
            root.wallpaperActionSucceeded = fields.length === 5 && fields[0] === "preview"
                && fields[1] === root.wallpaperActionToken && fields[2] === "30"
                && fields[3] === root.wallpaperActionPath && fields[4] === root.wallpaperActionFit;
        } else if (root.wallpaperActionKind === "apply") {
            root.wallpaperActionSucceeded = fields.length === 4 && fields[0] === "result"
                && fields[1] === "apply" && fields[2] === root.wallpaperActionPath
                && fields[3] === root.wallpaperActionFit;
        } else if (root.wallpaperActionKind === "reset") {
            root.wallpaperActionSucceeded = fields.length === 3 && fields[0] === "result"
                && fields[1] === "reset" && (fields[2] === "applied" || fields[2] === "unavailable");
            if (root.wallpaperActionSucceeded) root.wallpaperActionResultState = fields[2];
        } else {
            root.wallpaperActionSucceeded = fields.length === 3 && fields[0] === "result"
                && fields[1] === root.wallpaperActionKind && fields[2] === root.wallpaperActionToken;
        }
    }

    function finishWallpaperAction() {
        if (root.wallpaperActionSucceeded) {
            if (root.wallpaperActionKind === "preview") {
                root.wallpaperPreviewState = "active";
                root.wallpaperPreviewToken = root.wallpaperActionToken;
                root.wallpaperPreviewRemaining = 30;
                root.wallpaperPreviewPath = root.wallpaperActionPath;
                root.wallpaperPreviewFit = root.wallpaperActionFit;
                root.wallpaperPreviewDetail = "Automatic rollback is armed";
            } else if (root.wallpaperActionKind === "keep"
                    || root.wallpaperActionKind === "revert"
                    || root.wallpaperActionKind === "abandon") {
                root.wallpaperPreviewState = "none";
                root.wallpaperPreviewToken = "";
                root.wallpaperPreviewRemaining = 0;
                root.wallpaperPreviewPath = "";
                root.wallpaperPreviewFit = "fill";
                root.wallpaperPreviewDetail = "";
            }
            root.message = root.wallpaperActionKind === "reconcile"
                ? root.wallpaperPreviewState === "failed"
                    ? "Wallpaper preview recovery still needs attention"
                    : "Wallpaper preview recovery reconciled"
                : root.wallpaperActionKind === "preview"
                ? "Wallpaper preview active; keep it within 30 seconds or it will revert"
                : root.wallpaperActionKind === "keep" ? "Wallpaper preview kept"
                    : root.wallpaperActionKind === "revert" ? "Wallpaper preview reverted"
                        : root.wallpaperActionKind === "abandon" ? "External wallpaper state restored"
                            : root.wallpaperActionKind === "reset"
                                ? root.wallpaperActionResultState === "applied"
                                    ? "Wallpaper reset to the session default"
                                    : "Wallpaper selection reset; no session default was available"
                                : "Wallpaper applied";
            root.messageSeverity = root.wallpaperActionKind === "reconcile"
                ? root.wallpaperPreviewState === "failed" ? "warning" : "success"
                : root.wallpaperActionKind === "preview"
                    || (root.wallpaperActionKind === "reset"
                        && root.wallpaperActionResultState === "unavailable")
                ? "warning" : "success";
        } else {
            root.message = root.wallpaperActionError.length > 0 ? root.wallpaperActionError
                : "Wallpaper helper did not confirm the requested change";
            root.messageSeverity = "danger";
        }
        root.wallpaperBusy = false;
        Qt.callLater(root.refreshWallpaperStatus);
        root.refreshInventory(true);
    }

    function parseActionResult(text) {
        const lines = text.trim().split("\n");
        if (lines.length !== 2 || lines[0] !== "appearance-action-protocol\t1\t0") return;
        const fields = lines[1].split("\t");
        if (root.actionKind === "preview") {
            root.actionSucceeded = fields.length === 5 && fields[0] === "preview"
                && fields[1] === root.actionToken && fields[2] === "30"
                && fields[3] === root.actionTheme;
        } else if (root.actionKind === "apply" || root.actionKind === "reset") {
            root.actionSucceeded = fields.length === 4 && fields[0] === "result"
                && fields[1] === root.actionKind
                && (root.actionKind === "reset" || fields[2] === root.actionTheme);
        } else if (root.actionKind === "keep" || root.actionKind === "revert"
                || root.actionKind === "abandon") {
            root.actionSucceeded = fields.length === 4 && fields[0] === "result"
                && fields[1] === root.actionKind && fields[2] === root.actionToken;
        } else if (root.actionKind === "recover") {
            root.actionSucceeded = fields.length === 2 && fields[0] === "result"
                && fields[1] === "recovered";
        }
    }

    function finishAction() {
        root.busy = false;
        if (root.actionSucceeded) {
            if (root.actionKind === "preview") {
                root.previewState = "active";
                root.previewStatusManualOnly = false;
                root.previewToken = root.actionToken;
                root.previewTheme = root.actionTheme;
                root.previewRemaining = 30;
                root.previewZeroRetryAttempts = 0;
                root.message = "Preview active; keep it within 30 seconds or it will revert";
                root.messageSeverity = "warning";
            } else {
                if (root.actionKind === "keep" || root.actionKind === "revert"
                        || root.actionKind === "abandon") {
                    root.previewState = "none";
                    root.previewStatusManualOnly = false;
                    root.previewToken = "";
                    root.previewTheme = "";
                    root.previewRemaining = 0;
                    root.previewDetail = "";
                    root.previewZeroRetryAttempts = 0;
                } else if (root.actionKind === "recover") {
                    root.recoveryState = "none";
                    root.recoveryAction = "";
                    root.recoveryTheme = "";
                }
                root.message = root.actionKind === "keep" ? "Theme preview kept"
                    : root.actionKind === "revert" ? "Theme preview reverted"
                    : root.actionKind === "abandon" ? "External theme state accepted"
                    : root.actionKind === "recover" ? "Interrupted theme change recovered"
                    : root.actionKind === "reset" ? "Theme reset to the managed default"
                    : "Theme applied";
                root.messageSeverity = "success";
            }
        } else {
            root.message = root.actionError.length > 0 ? root.actionError
                : "Appearance helper did not confirm the requested change";
            root.messageSeverity = "danger";
        }
        Qt.callLater(root.refreshAll);
    }

    Component.onCompleted: root.refreshAll()

    FileView {
        id: userThemesWatch
        path: root.themesPath
        watchChanges: true
        printErrors: false
        onLoaded: sourceChangeSettleTimer.restart()
        onLoadFailed: sourceChangeSettleTimer.restart()
        onFileChanged: reload()
    }

    FileView {
        id: managedThemesWatch
        path: root.managedThemesPath
        watchChanges: true
        printErrors: false
        onLoaded: sourceChangeSettleTimer.restart()
        onLoadFailed: sourceChangeSettleTimer.restart()
        onFileChanged: reload()
    }

    FileView {
        id: fontConfigWatch
        path: root.fontConfigPath
        watchChanges: true
        printErrors: false
        onLoaded: fontChangeSettleTimer.restart()
        onLoadFailed: fontChangeSettleTimer.restart()
        onFileChanged: reload()
    }

    FileView {
        id: fontPreviewWatch
        path: root.fontPreviewPath
        watchChanges: true
        printErrors: false
        onLoaded: fontChangeSettleTimer.restart()
        onLoadFailed: fontChangeSettleTimer.restart()
        onFileChanged: reload()
    }

    Variants {
        model: root.integrationWatchPaths

        FileView {
            required property string modelData
            path: modelData
            watchChanges: root.settingsVisible
            printErrors: false
            onLoaded: if (root.settingsVisible) integrationChangeSettleTimer.restart()
            onLoadFailed: if (root.settingsVisible) integrationChangeSettleTimer.restart()
            onFileChanged: reload()
        }
    }

    Variants {
        model: root.settingsVisible ? root.statusWatchPaths : []

        FileView {
            required property string modelData
            path: modelData
            watchChanges: true
            printErrors: false
            onLoaded: statusChangeSettleTimer.restart()
            onLoadFailed: statusChangeSettleTimer.restart()
            onFileChanged: reload()
        }
    }

    Process {
        id: snapshotProcess
        command: Commands.settingsAppearanceCommand("snapshot", [])
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseSnapshot(this.text)
        }
        stderr: StdioCollector {
            id: snapshotError
        }
        onRunningChanged: {
            if (!running && root.snapshotRunGeneration === root.snapshotGeneration
                    && !root.snapshotParsed) {
                const error = snapshotError.text.trim();
                root.clearSnapshot(error.length > 0 ? error
                    : "Appearance provider failed before returning a valid snapshot");
            }
            if (!running && root.snapshotPending) {
                root.snapshotPending = false;
                Qt.callLater(root.refreshSnapshot);
            }
        }
    }

    Process {
        id: readinessProcess
        command: Commands.booleanStatusCommand(Commands.settingsThemeCommand("mutation-ready", []))
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.mutationReady = this.text.trim() === "available"
        }
    }

    Process {
        id: wallpaperReadinessProcess
        command: Commands.booleanStatusCommand(Commands.settingsWallpaperCommand("reset-ready", []))
        running: false
        onRunningChanged: {
            if (!running && root.settingsVisible)
                Qt.callLater(root.refreshWallpaperStatus);
        }
    }

    Process {
        id: fontReadinessProcess
        command: Commands.booleanStatusCommand(Commands.settingsFontCommand("mutation-ready", []))
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.fontMutationReady = this.text.trim() === "available"
        }
    }

    Process {
        id: fontStatusProcess
        command: Commands.checkedCommand(Commands.settingsFontCommand("status", []))
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseFontStatus(this.text) }
        stderr: StdioCollector { id: fontStatusError }
        onRunningChanged: {
            if (running) return;
            if (!root.fontStatusParsed) {
                const error = fontStatusError.text.trim();
                root.clearFontStatus(error.length > 0 ? error
                    : "Font helper failed before returning a valid status");
            }
            if (root.fontStatusPending) Qt.callLater(root.refreshFontStatus);
        }
    }

    Process {
        id: personalizationStatusProcess
        // Own the helper process directly so pane close terminates the actual
        // bounded probe rather than an output-capturing wrapper. The required
        // final completion record rejects partial output from failed probes.
        command: Commands.settingsPersonalizationCommand("status", [])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parsePersonalizationStatus(this.text) }
        stderr: StdioCollector { id: personalizationStatusError }
        onRunningChanged: {
            if (running) return;
            if (!root.personalizationStatusParsed && root.settingsVisible) {
                const error = personalizationStatusError.text.trim();
                root.clearPersonalizationStatus(error.length > 0 ? error
                    : "Personalization helper failed before returning a valid status");
            }
            if (root.personalizationStatusPending && root.settingsVisible)
                Qt.callLater(root.refreshPersonalizationStatus);
        }
    }

    Process {
        id: wallpaperStatusProcess
        command: Commands.settingsWallpaperCommand("status", ["--read-only"])
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseWallpaperStatus(this.text) }
        stderr: StdioCollector { id: wallpaperStatusError }
        onRunningChanged: {
            if (!running && root.settingsVisible && !root.wallpaperStatusParsed) {
                const error = wallpaperStatusError.text.trim();
                root.clearWallpaperStatus(error.length > 0 ? error
                    : "Wallpaper helper failed before returning a valid status");
            }
            if (!running && root.settingsVisible && root.inventoryPending) {
                const allowUnwatched = root.inventoryPendingAllowUnwatched;
                root.inventoryPending = false;
                root.inventoryPendingAllowUnwatched = false;
                Qt.callLater(function() { root.refreshInventory(allowUnwatched); });
            } else if (!running && root.settingsVisible && root.wallpaperStatusPending) {
                root.wallpaperStatusPending = false;
                Qt.callLater(root.refreshWallpaperStatus);
            }
        }
    }

    Process {
        id: inventoryProcess
        // Keep the helper as the directly owned process so pane close sends
        // SIGTERM to the scan itself instead of orphaning it behind the checked
        // command's output-capturing shell.
        command: Commands.settingsAppearanceCommand("inventory", [])
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.parseInventory(this.text)
        }
        stderr: StdioCollector {
            id: inventoryError
        }
        onRunningChanged: {
            if (!running && root.inventoryRunGeneration === root.inventoryGeneration
                    && !root.inventoryParsed) {
                const error = inventoryError.text.trim();
                root.clearInventory(error.length > 0 ? error
                    : "Appearance inventory failed before returning a valid snapshot");
            }
            if (!running && root.inventoryPending && root.settingsVisible) {
                const allowUnwatched = root.inventoryPendingAllowUnwatched;
                root.inventoryPending = false;
                root.inventoryPendingAllowUnwatched = false;
                Qt.callLater(function() { root.refreshInventory(allowUnwatched); });
            } else if (!running && root.wallpaperStatusPending && root.settingsVisible) {
                Qt.callLater(root.refreshWallpaperStatus);
            }
        }
    }

    Process {
        id: inventoryWatchProcess
        command: Commands.settingsAppearanceCommand("watch-inventory", [])
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (line === "ready\tinventory") {
                    root.inventoryWatchReady = true;
                    root.inventoryWatchSawEvent = false;
                    if (root.settingsVisible) {
                        root.refreshWallpaperStatus();
                        root.refreshInventory(true);
                        root.refreshFontStatus();
                    }
                } else if (line.startsWith("changed\t")) {
                    root.inventoryWatchReady = false;
                    root.inventoryWatchSawEvent = true;
                    root.inventoryPending = true;
                    if (root.settingsVisible) {
                        root.refreshWallpaperStatus();
                        root.refreshFontStatus();
                    }
                }
            }
        }
        stderr: StdioCollector {
            id: inventoryWatchError
        }
        onRunningChanged: {
            if (running) {
                inventoryWatchExitSettleTimer.stop();
                return;
            }
            root.inventoryWatchReady = false;
            if (root.settingsVisible) inventoryWatchExitSettleTimer.restart();
        }
    }

    Process {
        id: compositorWatchProcess
        command: Commands.settingsAppearanceCommand("watch-compositor", [])
        running: false
        stdout: SplitParser { onRead: compositorWatchSettleTimer.restart() }
        onRunningChanged: {
            if (!running && root.settingsVisible && root.compositorWatchReady)
                compositorWatchRestartTimer.restart();
        }
    }

    Process {
        id: xsettingsWatchProcess
        command: Commands.settingsXsettingsCommand("watch", [])
        running: false
        stdout: SplitParser {
            onRead: line => {
                if (line === "xsettings-event-protocol\t1\t0")
                    root.xsettingsWatchProtocolSeen = true;
                else if (line === "changed" && root.xsettingsWatchProtocolSeen) {
                    root.xsettingsWatchSawEvent = true;
                    root.xsettingsWatchReady = false;
                    root.refreshPersonalizationStatus();
                }
            }
        }
        onRunningChanged: {
            if (running) {
                root.xsettingsWatchProtocolSeen = false;
                root.xsettingsWatchSawEvent = false;
            }
            else if (root.settingsVisible && root.xsettingsWatchReady) {
                if (root.xsettingsWatchSawEvent) {
                    Qt.callLater(function() {
                        if (root.settingsVisible && root.xsettingsWatchReady
                                && !xsettingsWatchProcess.running)
                            xsettingsWatchProcess.running = true;
                    });
                } else {
                    root.xsettingsWatchReady = false;
                    root.xsettingsWatchFailed = true;
                    root.refreshPersonalizationStatus();
                }
            }
        }
    }

    Process {
        id: previewStatusProcess
        command: Commands.checkedCommand(Commands.settingsThemeCommand("preview-status", []))
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                if (lines.length < 2 || lines[0] !== "appearance-action-protocol\t1\t0") return;
                const record = lines[1].split("\t");
                if (record[0] === "result" && record[1] === "none") {
                    root.previewStatusParsed = true;
                    root.previewStatusManualOnly = false;
                    const wasActive = root.previewState === "active";
                    root.previewState = "none";
                    root.previewToken = "";
                    root.previewTheme = "";
                    root.previewRemaining = 0;
                    root.previewDetail = "";
                    root.previewZeroRetryAttempts = 0;
                    if (wasActive) {
                        root.message = "Theme preview completed outside Settings";
                        root.messageSeverity = "idle";
                    }
                } else if (record[0] === "result" && record[1] === "expired") {
                    root.previewStatusParsed = true;
                    root.previewStatusManualOnly = false;
                    root.previewState = "none";
                    root.previewToken = "";
                    root.previewTheme = "";
                    root.previewRemaining = 0;
                    root.previewDetail = "";
                    root.previewZeroRetryAttempts = 0;
                    root.message = "Theme preview reverted automatically";
                    root.messageSeverity = "warning";
                } else if (record.length === 3 && record[0] === "preview-active") {
                    root.previewStatusParsed = true;
                    root.previewState = "active";
                    root.previewToken = record[1];
                    root.previewTheme = record[2];
                    root.previewDetail = "Automatic rollback is armed";
                    if (lines.length === 3) {
                        const remaining = lines[2].split("\t");
                        root.previewRemaining = remaining.length === 2
                            && remaining[0] === "preview-remaining" && /^[0-9]+$/.test(remaining[1])
                            ? Number(remaining[1]) : 0;
                    } else root.previewRemaining = 0;
                    if (root.previewRemaining > 0) {
                        root.previewZeroRetryAttempts = 0;
                        root.previewStatusManualOnly = false;
                    }
                    else {
                        root.previewZeroRetryAttempts++;
                        if (root.previewZeroRetryAttempts > 3) {
                            root.previewStatusManualOnly = true;
                            root.message = "Automatic rollback status needs a manual refresh";
                            root.messageSeverity = "warning";
                        }
                    }
                } else if (record.length === 3 && record[0] === "preview-failed") {
                    root.previewStatusParsed = true;
                    root.previewStatusManualOnly = false;
                    root.previewState = "failed";
                    root.previewToken = record[1];
                    root.previewDetail = record[2];
                    root.previewRemaining = 0;
                    root.previewZeroRetryAttempts = 0;
                }
            }
        }
        onRunningChanged: {
            if (running) return;
            // preview-status shares the helper's mutation lock, so this second
            // snapshot observes integrations only after an external transaction
            // has finished publishing them.
            Qt.callLater(root.refreshSnapshot);
            if (root.previewState !== "active" || root.previewRemaining !== 0) return;
            if (!root.previewStatusParsed) root.previewZeroRetryAttempts++;
            if (root.previewZeroRetryAttempts <= 3) previewZeroRetryTimer.restart();
            else {
                root.previewStatusManualOnly = true;
                root.message = "Automatic rollback status needs a manual refresh";
                root.messageSeverity = "warning";
            }
        }
    }

    Process {
        id: recoveryStatusProcess
        command: Commands.checkedCommand(Commands.settingsThemeCommand("recovery-status", []))
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                if (lines.length !== 2 || lines[0] !== "appearance-action-protocol\t1\t0") return;
                const record = lines[1].split("\t");
                if (record.length === 2 && record[0] === "recovery" && record[1] === "none") {
                    root.recoveryState = "none";
                    root.recoveryAction = "";
                    root.recoveryTheme = "";
                } else if (record.length === 4 && record[0] === "recovery"
                        && record[1] === "available") {
                    root.recoveryState = "available";
                    root.recoveryAction = record[2];
                    root.recoveryTheme = record[3];
                }
            }
        }
    }

    Process {
        id: actionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseActionResult(this.text) }
        stderr: StdioCollector { onStreamFinished: root.actionError = this.text.trim() }
        onRunningChanged: if (!running && root.busy) root.finishAction()
    }

    Process {
        id: wallpaperActionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseWallpaperAction(this.text) }
        stderr: StdioCollector { onStreamFinished: root.wallpaperActionError = this.text.trim() }
        onRunningChanged: if (!running && root.wallpaperBusy) root.finishWallpaperAction()
    }

    Process {
        id: fontActionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parseFontAction(this.text) }
        stderr: StdioCollector { onStreamFinished: root.fontActionError = this.text.trim() }
        onRunningChanged: if (!running && root.fontBusy) root.finishFontAction()
    }

    Process {
        id: personalizationActionProcess
        command: ["sh", "-c", "exit 1"]
        running: false
        stdout: StdioCollector { onStreamFinished: root.parsePersonalizationAction(this.text) }
        stderr: StdioCollector {
            onStreamFinished: root.personalizationActionError = this.text.trim()
        }
        onRunningChanged: if (!running && root.personalizationBusy)
            root.finishPersonalizationAction()
    }

    Timer {
        id: previewZeroRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.refreshPreviewStatus()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.settingsVisible && root.wallpaperPreviewState === "active"
            && root.wallpaperPreviewRemaining > 0
        onTriggered: {
            root.wallpaperPreviewRemaining--;
            if (root.wallpaperPreviewRemaining === 0)
                Qt.callLater(root.refreshWallpaperStatus);
        }
    }

    Timer {
        id: sourceChangeSettleTimer
        interval: 100
        repeat: false
        onTriggered: root.refreshAll()
    }

    Timer {
        id: fontChangeSettleTimer
        interval: 100
        repeat: false
        onTriggered: root.refreshFontStatus()
    }

    Timer {
        id: fontStatusRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.refreshFontStatus()
    }

    Timer {
        id: integrationChangeSettleTimer
        interval: 100
        repeat: false
        onTriggered: if (root.settingsVisible) root.refreshAll()
    }

    Timer {
        id: inventoryWatchExitSettleTimer
        interval: 100
        repeat: false
        onTriggered: root.finishInventoryWatcherExit()
    }

    Timer {
        id: inventoryWatchRestartTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (root.settingsVisible && (root.inventoryWatchState === "available"
                    || root.inventoryWatchState === "idle")
                    && !root.inventoryWatchFailed) root.startInventoryWatcher();
        }
    }

    Timer {
        id: compositorWatchSettleTimer
        interval: 100
        repeat: false
        onTriggered: root.refreshInventory(true)
    }

    Timer {
        id: compositorWatchRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.settingsVisible && root.compositorWatchReady
                    && !compositorWatchProcess.running) compositorWatchProcess.running = true;
        }
    }

    Timer {
        id: statusChangeSettleTimer
        interval: 100
        repeat: false
        onTriggered: if (root.settingsVisible) root.refreshAll()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.previewState === "active" && root.previewRemaining > 0
        onTriggered: {
            root.previewRemaining--;
            if (root.previewRemaining === 0) {
                Qt.callLater(root.refreshPreviewStatus);
                Qt.callLater(root.refreshSnapshot);
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.settingsVisible && root.fontPreviewState === "active"
            && root.fontPreviewRemaining > 0
        onTriggered: {
            root.fontPreviewRemaining--;
            if (root.fontPreviewRemaining === 0) Qt.callLater(root.refreshFontStatus);
        }
    }
}
