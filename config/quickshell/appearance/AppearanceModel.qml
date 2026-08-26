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
    property bool wallpaperMutationReady: false
    property string wallpaperMutationDetail: "Wallpaper changes have not been checked"
    property bool wallpaperResetReady: false
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
    property string message: ""
    property string messageSeverity: "idle"
    property string previewState: "none"
    property string previewToken: ""
    property string previewTheme: ""
    property int previewRemaining: 0
    property string previewDetail: ""
    property int previewZeroRetryAttempts: 0
    property bool previewStatusParsed: false
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
    readonly property string managedThemesPath: root.dataHome + "/dwm-titus/config/themes.toml"
    readonly property var wallpaperCandidates: root.inventoryCandidates.filter(function(candidate) {
        return candidate.id === "wallpaper";
    })
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

    function refreshPreviewStatus() {
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
                || wallpaperActionProcess.running || inventoryProcess.running
                || (inventoryWatchProcess.running && !root.inventoryWatchReady)) {
            root.wallpaperStatusPending = true;
            return;
        }
        root.wallpaperStatusPending = false;
        root.wallpaperStatusParsed = false;
        wallpaperStatusProcess.running = true;
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

    function refreshAll() {
        root.refreshSnapshot();
        root.refreshInventory();
        root.refreshPreviewStatus();
        root.refreshRecoveryStatus();
        root.refreshMutationReadiness();
        root.refreshWallpaperStatus();
    }

    function openSettings() {
        root.settingsVisible = true;
        root.inventoryPending = true;
        root.inventoryPendingAllowUnwatched = false;
        root.inventoryWatchReady = false;
        root.inventoryWatchSawEvent = false;
        root.inventoryWatchFailed = false;
        if (!wallpaperReadinessProcess.running)
            wallpaperReadinessProcess.running = true;
        root.startInventoryWatcher(true);
        root.refreshAll();
    }

    function startInventoryWatcher(restartIfRunning) {
        if (inventoryWatchProcess.running) {
            if (restartIfRunning === true) root.inventoryWatchRestartPending = true;
            return;
        }
        root.inventoryWatchRestartPending = false;
        root.inventoryWatchSawEvent = false;
        inventoryWatchProcess.running = true;
    }

    function closeSettings() {
        root.settingsVisible = false;
        root.inventoryGeneration++;
        inventoryWatchRestartTimer.stop();
        root.inventoryWatchRestartPending = false;
        inventoryWatchProcess.running = false;
        root.inventoryWatchReady = false;
        root.inventoryWatchSawEvent = false;
        compositorWatchSettleTimer.stop();
        compositorWatchRestartTimer.stop();
        compositorWatchProcess.running = false;
        inventoryProcess.running = false;
        wallpaperStatusProcess.running = false;
        root.wallpaperStatusPending = false;
        root.inventoryPending = false;
        root.inventoryPendingAllowUnwatched = false;
    }

    function nextPreviewToken() {
        return "qs-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function runAction(action, args, theme, token) {
        if (root.busy || root.wallpaperBusy || actionProcess.running) {
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
        root.wallpaperMutationReady = false;
        root.wallpaperMutationDetail = detail;
        root.wallpaperResetReady = false;
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
        root.wallpaperMutationReady = mutation.state === "available";
        root.wallpaperMutationDetail = mutation.detail;
        root.wallpaperResetReady = reset.state === "available";
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
                && !root.busy) {
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
                || root.busy) {
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
                    }
                } else if (line.startsWith("changed\t")) {
                    root.inventoryWatchReady = false;
                    root.inventoryWatchSawEvent = true;
                    root.inventoryPending = true;
                    if (root.settingsVisible) root.refreshWallpaperStatus();
                }
            }
        }
        stderr: StdioCollector {
            id: inventoryWatchError
        }
        onRunningChanged: {
            if (!running) {
                root.inventoryWatchReady = false;
                if (root.settingsVisible && root.inventoryWatchRestartPending
                        && !root.inventoryWatchFailed) {
                    root.inventoryWatchRestartPending = false;
                    if (root.inventoryWatchSawEvent) inventoryWatchRestartTimer.restart();
                    else Qt.callLater(root.startInventoryWatcher);
                } else if (root.settingsVisible && !root.inventoryWatchSawEvent
                        && !root.inventoryWatchFailed) {
                    const error = inventoryWatchError.text.trim();
                    root.inventoryWatchFailed = true;
                    root.inventoryWatchState = "unavailable";
                    root.inventoryWatchDetail = error.length > 0 ? error
                        : "Live appearance asset watching stopped unexpectedly";
                    root.refreshInventory(true);
                } else if (root.settingsVisible && (root.inventoryWatchState === "available"
                        || root.inventoryWatchState === "idle")) inventoryWatchRestartTimer.restart();
            }
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
                    if (root.previewRemaining > 0) root.previewZeroRetryAttempts = 0;
                    else {
                        root.previewZeroRetryAttempts++;
                        if (root.previewZeroRetryAttempts > 3) {
                            root.message = "Automatic rollback status needs a manual refresh";
                            root.messageSeverity = "warning";
                        }
                    }
                } else if (record.length === 3 && record[0] === "preview-failed") {
                    root.previewStatusParsed = true;
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
        id: integrationChangeSettleTimer
        interval: 100
        repeat: false
        onTriggered: if (root.settingsVisible) root.refreshAll()
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
}
