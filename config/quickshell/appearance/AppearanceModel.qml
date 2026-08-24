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
    readonly property string managedThemesPath: root.dataHome + "/dwm-titus/config/themes.toml"
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
        root.configHome + "/qt6ct/qt6ct.conf"
    ]
    readonly property var statusWatchPaths: [
        root.stateHome + "/dwm-titus/appearance/preview.current",
        root.stateHome + "/dwm-titus/appearance/transaction.meta",
        root.stateHome + "/dwm-titus/appearance/transaction.failed",
        root.stateHome + "/dwm-titus/appearance/integration-transaction"
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
        return "available";
    }

    function validState(value) {
        return value === "available" || value === "partial" || value === "restricted"
            || value === "unavailable";
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

    function refreshAll() {
        root.refreshSnapshot();
        root.refreshPreviewStatus();
        root.refreshRecoveryStatus();
        root.refreshMutationReadiness();
    }

    function openSettings() {
        root.settingsVisible = true;
        root.refreshAll();
    }

    function closeSettings() {
        root.settingsVisible = false;
    }

    function nextPreviewToken() {
        return "qs-" + Quickshell.processId.toString() + "-" + Date.now().toString();
    }

    function runAction(action, args, theme, token) {
        if (root.busy || actionProcess.running) {
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

    Timer {
        id: previewZeroRetryTimer
        interval: 250
        repeat: false
        onTriggered: root.refreshPreviewStatus()
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
