#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell_qml=$repo/config/quickshell/shell.qml
theme=$repo/config/quickshell/core/Theme.qml
commands=$repo/config/quickshell/core/Commands.qml
model=$repo/config/quickshell/appearance/AppearanceModel.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml

# Syntax is validated here; executable state and lifecycle are exercised by
# test-quickshell-settings-xvfb.sh. The assertions below protect module wiring
# and security boundaries that are intentionally source-level contracts.
"$repo/scripts/quickshell-qmllint" --root "$repo/config/quickshell"

test "$(grep -c 'AppearanceModel {' "$shell_qml")" -eq 1
grep -Fq 'appearanceModel: appearanceModel' "$shell_qml"
grep -Fq 'root.appearanceModel.openSettings()' "$settings_model"
grep -Fq 'root.appearanceModel.closeSettings()' "$settings_model"
test "$(grep -Fc 'root.appearanceModel.closeSettings()' "$settings_model")" -eq 2
grep -Fq 'AppearanceSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "appearance"' "$settings_window"
grep -Fq 'capability.id !== "themes"' "$settings_window"

grep -Fq 'function settingsAppearanceCommand(action, args)' "$commands"
grep -Fq 'function settingsThemeCommand(action, args)' "$commands"
grep -Fq 'function booleanStatusCommand(command)' "$commands"
grep -Fq 'appearance-protocol' "$model"
grep -Fq 'appearance-action-protocol' "$model"
grep -Fq 'appearance-inventory-protocol' "$model"
grep -Fq 'value === "@legacy-colors" || root.validThemeName(value)' "$model"
grep -Fq 'root.validProviderActiveLabel(fields[1])' "$model"
grep -Fq 'fields[3] === "invalid"' "$model"
grep -Fq '"dark": fields[4] !== "false"' "$model"
grep -Fq 'value === "selected" || value === "recovery" || value === "unresolved"' "$model"
grep -Fq 'fields[1] === "none" && fields[2] === "unavailable"' "$model"
grep -Fq '"mutable": root.validThemeName(fields[1])' "$model"
grep -Fq 'Commands.checkedCommand(Commands.settingsThemeCommand(action, args))' "$model"
grep -Fq 'Commands.settingsThemeCommand("mutation-ready", [])' "$model"
grep -Fq 'Theme.applyAppearanceColors(colors, darkMode)' "$model"
grep -Fq 'watchChanges: true' "$model"
test "$(grep -Fc 'watchChanges: true' "$model")" -eq 3
grep -Fq 'model: root.integrationWatchPaths' "$model"
grep -Fq 'Commands.settingsAppearanceCommand("inventory", [])' "$model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsAppearanceCommand("inventory", []))' \
	"$model"; then
	printf 'Appearance inventory remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'Commands.settingsAppearanceCommand("watch-inventory", [])' "$model"
grep -Fq 'Commands.settingsAppearanceCommand("watch-compositor", [])' "$model"
grep -Fq 'function startInventoryWatcher()' "$model"
grep -Fq 'root.inventoryWatchSawEvent = false' "$model"
grep -Fq 'if (!root.inventoryWatchReady && allowUnwatched !== true)' "$model"
grep -Fq 'root.inventoryPendingAllowUnwatched = root.inventoryPendingAllowUnwatched' "$model"
grep -Fq 'root.refreshInventory(allowUnwatched)' "$model"
grep -Fq 'if (line === "ready\tinventory")' "$model"
grep -Fq 'root.refreshInventory(true)' "$model"
grep -Fq 'root.inventoryWatchFailed = true' "$model"
grep -Fq 'root.inventoryWatchState = "unavailable"' "$model"
grep -Fq '&& !root.inventoryWatchFailed' "$model"
grep -Fq 'onTriggered: root.refreshInventory(true)' "$model"
grep -Fq 'if (!root.settingsVisible) return;' "$model"
grep -Fq 'inventoryWatchProcess.running = false' "$model"
grep -Fq 'compositorWatchProcess.running = false' "$model"
grep -Fq 'root.inventoryCandidates = candidates' "$model"
grep -Fq 'model: root.settingsVisible ? root.statusWatchPaths : []' "$model"
grep -Fq 'watchChanges: root.settingsVisible' "$model"
grep -Fq 'onTriggered: if (root.settingsVisible) root.refreshAll()' "$model"
test "$(grep -Fc 'onTriggered: if (root.settingsVisible) root.refreshAll()' "$model")" -eq 2
grep -Fq 'running: root.previewState === "active" && root.previewRemaining > 0' "$model"
grep -Fq 'previewZeroRetryTimer.restart()' "$model"
grep -Fq 'if (!root.previewStatusParsed) root.previewZeroRetryAttempts++' "$model"
grep -Fq 'root.snapshotParsed = false' "$model"
grep -Fq 'root.snapshotRunGeneration === root.snapshotGeneration' "$model"
grep -Fq '&& !root.snapshotParsed' "$model"
grep -Fq 'const error = snapshotError.text.trim()' "$model"
grep -Fq 'Appearance provider failed before returning a valid snapshot' "$model"
grep -Fq 'root.configuredConfigHome.startsWith("/")' "$model"
grep -Fq 'root.configuredDataHome.startsWith("/")' "$model"
grep -Fq 'root.configuredStateHome.startsWith("/")' "$model"
grep -Fq 'appliedTheme === null || !appliedTheme.valid' "$model"
grep -Fq 'if (root.activeState === "recovery") return "partial"' "$model"
grep -Fq 'root.colorsComplete(colors)' "$model"
grep -Fq 'root.integrationsComplete(integrations)' "$model"
grep -Fq 'Qt.callLater(root.refreshSnapshot)' "$model"
grep -Fq 'onTriggered: root.refreshAll()' "$model"
grep -Fq 'const wasActive = root.previewState === "active"' "$model"
grep -Fq 'Theme preview completed outside Settings' "$model"

grep -Fq 'function applyAppearanceColors(colors, darkMode)' "$theme"
if grep -Eq 'FileView|themes\.toml|function applyThemes' "$theme"; then
	printf 'Theme.qml still owns theme file parsing instead of the shared AppearanceModel\n' >&2
	exit 1
fi

grep -Fq 'Preview for 30 seconds' "$pane"
grep -Fq 'Component.onCompleted: root.ensureSelection()' "$pane"
grep -Fq 'preferred = root.appearanceModel.resolvedTheme' "$pane"
grep -Fq 'label: "Additional capabilities"' "$pane"
grep -Fq 'model: root.capabilities' "$pane"
grep -Fq 'onActivated: root.appearanceModel.keepPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.revertPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.abandonPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.recover()' "$pane"
grep -Fq 'Selected appearance is only partially applied' "$pane"
grep -Fq 'root.appearanceModel.integrations' "$pane"
grep -Fq 'root.appearanceModel.errors' "$pane"
grep -Fq 'function appearanceIntegrationState(integrationId: string): string' "$shell_qml"
test "$(grep -Fc 'root.selectedTheme.valid && root.selectedTheme.mutable' "$pane")" -eq 2

if grep -ERq 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$model" "$pane"; then
	printf 'Appearance model introduced a forbidden Wayland or Omarchy dependency\n' >&2
	exit 1
fi

printf 'Quickshell shared appearance model contract: PASS\n'
