#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell_qml=$repo/config/quickshell/shell.qml
theme=$repo/config/quickshell/core/Theme.qml
icon_text=$repo/config/quickshell/core/IconText.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
commands=$repo/config/quickshell/core/Commands.qml
model=$repo/config/quickshell/appearance/AppearanceModel.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
display_pane=$repo/config/quickshell/settings/DisplaySettingsPane.qml
input_pane=$repo/config/quickshell/settings/InputSettingsPane.qml
network_pane=$repo/config/quickshell/settings/NetworkSettingsPane.qml

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
grep -Fq 'function settingsFontCommand(action, args)' "$commands"
grep -Fq 'function settingsWallpaperCommand(action, args)' "$commands"
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
test "$(grep -Fc 'watchChanges: true' "$model")" -eq 5
grep -Fq 'model: root.integrationWatchPaths' "$model"
grep -Fq 'Commands.settingsAppearanceCommand("inventory", [])' "$model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsAppearanceCommand("inventory", []))' \
	"$model"; then
	printf 'Appearance inventory remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'Commands.settingsAppearanceCommand("watch-inventory", [])' "$model"
grep -Fq 'Commands.settingsAppearanceCommand("watch-compositor", [])' "$model"
grep -Fq 'function startInventoryWatcher(restartIfRunning)' "$model"
sed -n '/function startInventoryWatcher(restartIfRunning)/,/^    }/p' "$model" |
	grep -Fq 'if (!root.settingsVisible) return;'
grep -Fq 'root.startInventoryWatcher(true);' "$model"
grep -Fq 'if (restartIfRunning === true) root.inventoryWatchRestartPending = true;' "$model"
grep -Fq 'root.inventoryWatchSawEvent = false' "$model"
grep -Fq 'if (!root.inventoryWatchReady && !root.inventoryWatchFailed' "$model"
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
grep -Fq 'candidate.id === "wallpaper"' "$model"
grep -Fq 'candidate.id === "font"' "$model"
grep -Fq 'Commands.checkedCommand(Commands.settingsFontCommand("status", []))' "$model"
grep -Fq 'Commands.settingsFontCommand("mutation-ready", [])' "$model"
grep -Fq 'Commands.checkedCommand(Commands.settingsFontCommand(action, args))' "$model"
grep -Fq 'function previewFont(family, scale)' "$model"
grep -Fq 'function applyFont(family, scale)' "$model"
grep -Fq 'function resetFont()' "$model"
grep -Fq 'Theme.applyFontPreferences(root.fontFamily, root.fontScale)' "$model"
grep -Fq 'root.fontStatusRetryAttempts = 0;' "$model"
grep -Fq 'root.fontStatusRetryAttempts < 3' "$model"
grep -Fq 'fontStatusRetryTimer.restart();' "$model"
grep -Fq 'id: fontStatusRetryTimer' "$model"
grep -Fq 'root.fontMutationReady = false;' "$model"
test "$(grep -Fc '!root.fontMutationReady || fontReadinessProcess.running' "$model")" -eq 3
grep -Fq 'root.fontPreviewToken = root.fontActionToken;' "$model"
grep -Fq 'root.fontPreviewRemaining = 30;' "$model"
finish_font_action=$(sed -n '/function finishFontAction()/,/^    }/p' "$model")
printf '%s\n' "$finish_font_action" |
	grep -Fq 'root.fontActionKind === "keep" || root.fontActionKind === "revert"'
printf '%s\n' "$finish_font_action" | grep -Fq '|| root.fontActionKind === "abandon"'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewState = "none";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewToken = "";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewFamily = "";'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewScale = 1.0;'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewRemaining = 0;'
printf '%s\n' "$finish_font_action" | grep -Fq 'root.fontPreviewDetail = "";'
if sed -n '/function clearFontStatus(detail)/,/^    }/p' "$model" |
	grep -Fq 'Theme.applyFontPreferences'; then
	printf 'Transient font status failure still repaints the shell with fallback preferences\n' >&2
	exit 1
fi
test "$(grep -Fc 'root.refreshFontStatus();' "$model")" -eq 3
grep -Fq 'running: root.settingsVisible && root.fontPreviewState === "active"' "$model"
grep -Fq 'root.fontPreviewRemaining--' "$model"
grep -Fq 'Commands.settingsWallpaperCommand("status", ["--read-only"])' "$model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsWallpaperCommand("status"' "$model"; then
	printf 'Wallpaper status remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'Commands.settingsWallpaperCommand(action === "reconcile" ? "status" : action, args)' "$model"
grep -Fq 'function previewWallpaper(path, fit)' "$model"
grep -Fq 'function resetWallpaper()' "$model"
grep -Fq 'function reconcileWallpaperPreview()' "$model"
grep -Fq 'function clearWallpaperStatus(detail)' "$model"
grep -Fq 'root.wallpaperPath = "";' "$model"
grep -Fq 'const preservePreview = (root.wallpaperPreviewState === "active"' "$model"
grep -Fq '|| root.wallpaperPreviewState === "failed")' "$model"
grep -Fq '&& root.wallpaperPreviewToken.length > 0;' "$model"
grep -Fq 'if (!preservePreview) {' "$model"
grep -Fq 'Installed wallpaper helper does not report reset readiness' "$model"
grep -Fq 'root.clearWallpaperStatus("Wallpaper helper returned an unsupported response")' "$model"
grep -Fq 'provider = { "state": fields[2], "detail": fields[4] }' "$model"
grep -Fq 'root.wallpaperProviderDetail = provider.detail' "$model"
grep -Fq 'root.wallpaperMutationDetail = mutation.detail' "$model"
grep -Fq 'root.wallpaperResetReady = reset.state === "available"' "$model"
grep -Fq 'root.wallpaperStatusPending = true' "$model"
grep -Fq '|| wallpaperActionProcess.running || inventoryProcess.running' "$model"
grep -Fq 'if (wallpaperStatusProcess.running || wallpaperActionProcess.running) {' "$model"
grep -Fq 'if (!running && root.settingsVisible && root.inventoryPending) {' "$model"
grep -Fq '} else if (!running && root.settingsVisible && root.wallpaperStatusPending) {' "$model"
grep -Fq 'if (!running && root.wallpaperStatusPending && root.settingsVisible) {' "$model"
grep -Fq 'readonly property bool wallpaperStatusBusy: wallpaperReadinessProcess.running' "$model"
grep -Fq 'Commands.settingsWallpaperCommand("reset-ready", [])' "$model"
grep -Fq 'if (wallpaperReadinessProcess.running || wallpaperStatusProcess.running' "$model"
if grep -Fq '|| (inventoryWatchProcess.running && !root.inventoryWatchReady)) {' "$model"; then
	printf 'Wallpaper status discovery is still gated on inventory watcher startup\n' >&2
	exit 1
fi
grep -Fq '|| wallpaperReadinessProcess.running || wallpaperStatusProcess.running' "$model"
grep -Fq 'root.wallpaperPreviewState = "active";' "$model"
test "$(grep -Fc 'root.wallpaperPreviewState = "active";' "$model")" -eq 1
grep -Fq 'root.wallpaperPreviewToken = root.wallpaperActionToken;' "$model"
grep -Fq 'action === "reconcile" ? "status" : action' "$model"
grep -Fq 'root.parseWallpaperStatus(text);' "$model"
grep -Fq 'Wallpaper preview expired and reverted automatically' "$model"
grep -Fq 'const previewDecision = root.wallpaperPreviewState === "active"' "$model"
grep -Fq 'if (previewDecision && (inventoryProcess.running || root.inventoryPending' "$model"
grep -Fq '|| root.wallpaperStatusPending' "$model"
grep -Fq '|| (!previewDecision && inventoryWatchProcess.running' "$model"
if grep -Fq '&& !root.wallpaperStatusPending' "$model"; then
	printf 'Queued status work still blocks wallpaper inventory preemption\n' >&2
	exit 1
fi
grep -Fq 'if (inventoryProcess.running) inventoryProcess.running = false;' "$model"
grep -Fq 'root.wallpaperStatusPending = false;' "$model"
if grep -Fq 'wallpaperActionPending' "$model"; then
	printf 'Wallpaper preview decisions still use a pane-scoped pending queue\n' >&2
	exit 1
fi
grep -Fq '&& !root.inventoryWatchFailed) {' "$model"
grep -Fq 'root.inventoryWatchRestartPending = false;' "$model"
grep -Fq 'if (root.inventoryWatchSawEvent) inventoryWatchRestartTimer.restart();' "$model"
grep -Fq 'if (!previewWasActive && preview.state === "active") {' "$model"
grep -Fq 'root.wallpaperPreviewState = "none";' "$model"
grep -Fq 'Qt.callLater(root.refreshWallpaperStatus)' "$model"
grep -Fq 'running: root.settingsVisible && root.wallpaperPreviewState === "active"' "$model"
grep -Fq 'root.wallpaperPreviewRemaining--' "$model"
if grep -Fq 'onTriggered: root.refreshWallpaperStatus()' "$model"; then
	printf 'Wallpaper preview countdown still polls the full status helper every second\n' >&2
	exit 1
fi
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
grep -Fq 'if (root.wallpaperProviderState !== "available"' "$model"
grep -Fq '|| root.wallpaperState !== "available") return "partial"' "$model"
grep -Fq 'root.colorsComplete(colors)' "$model"
grep -Fq 'root.integrationsComplete(integrations)' "$model"
grep -Fq 'Qt.callLater(root.refreshSnapshot)' "$model"
grep -Fq 'onTriggered: root.refreshAll()' "$model"
grep -Fq 'const wasActive = root.previewState === "active"' "$model"
grep -Fq 'Theme preview completed outside Settings' "$model"

grep -Fq 'function applyAppearanceColors(colors, darkMode)' "$theme"
grep -Fq 'function applyFontPreferences(family, scale)' "$theme"
grep -Fq 'readonly property string iconFontFamily: "MesloLGS Nerd Font Mono"' "$theme"
grep -Fq 'readonly property int panelIconFontSize: 13' "$theme"
grep -Fq 'font.pixelSize: Theme.panelIconFontSize + 1' "$icon_text"
test "$(grep -Fc 'Theme.panelIconFontSize' "$panel")" -eq 5
grep -Fq 'Math.round(13 * fontScale)' "$theme"
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$display_pane")" -eq 9
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$input_pane")" -eq 5
grep -Fq 'font.pixelSize: Theme.inputFontSize' "$network_pane"
grep -Fq 'passwordInput.implicitHeight + 2 * Theme.spacingSm' "$network_pane"
grep -Fq 'xPositionInput.implicitHeight + 14' "$display_pane"
grep -Fq 'yPositionInput.implicitHeight + 14' "$display_pane"
grep -Fq 'profileNameInput.implicitHeight + 16' "$display_pane"
grep -Fq 'confirmationRow.implicitHeight + 16' "$display_pane"
grep -Fq 'settingInput.implicitHeight + 14' "$input_pane"
if grep -Eq 'FileView|themes\.toml|function applyThemes' "$theme"; then
	printf 'Theme.qml still owns theme file parsing instead of the shared AppearanceModel\n' >&2
	exit 1
fi

grep -Fq 'Preview for 30 seconds' "$pane"
grep -Fq 'Preview wallpaper for 30 seconds' "$pane"
grep -Fq 'label: "Configured wallpaper"' "$pane"
grep -Fq 'label: "Wallpaper apply and preview unavailable"' "$pane"
grep -Fq 'root.appearanceModel.wallpaperResetReady ? "Reset available" : "Protected"' "$pane"
grep -Fq 'readonly property bool wallpaperControlsBusy: root.appearanceBusy' "$pane"
grep -Fq '|| root.appearanceModel.wallpaperStatusBusy' "$pane"
grep -Fq 'readonly property bool wallpaperPreviewControlsBusy: root.appearanceBusy' "$pane"
grep -Fq '|| root.appearanceModel.wallpaperPreviewActionBusy' "$pane"
grep -Fq 'enabled: !root.wallpaperPreviewControlsBusy' "$pane"
grep -Fq '? !root.wallpaperPreviewControlsBusy : !root.wallpaperControlsBusy' "$pane"
grep -Fq 'label: "Reset wallpaper"' "$pane"
grep -Fq 'label: "Managed shell font"' "$pane"
grep -Fq 'Preview font for 30 seconds' "$pane"
grep -Fq 'onActivated: root.appearanceModel.keepFontPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.revertFontPreview()' "$pane"
grep -Fq 'onActivated: root.appearanceModel.abandonFontPreview()' "$pane"
grep -Fq 'label: "Reset font"' "$pane"
grep -Fq 'label: "Repair wallpaper state"' "$pane"
test "$(grep -Fc 'root.appearanceModel.wallpaperPreviewToken.length > 0' "$pane")" -eq 2
grep -Fq 'root.appearanceModel.wallpaperResetReady' "$pane"
grep -Fq 'detail: root.appearanceModel.wallpaperMutationDetail' "$pane"
grep -Fq 'else root.selectedWallpaperPath = "";' "$pane"
grep -Fq 'function wallpaperSelectionAvailable()' "$pane"
test "$(grep -Fc '&& root.wallpaperSelectionAvailable() && !root.wallpaperControlsBusy' "$pane")" -eq 2
grep -Fq 'function wallpaperEmptyDetail()' "$pane"
grep -Fq 'return root.appearanceModel.inventoryProviderDetail;' "$pane"
grep -Fq 'selection.detail === "Wallpaper candidate discovery did not complete"' "$pane"
grep -Fq 'root.appearanceModel.inventoryWatchDetail' "$pane"
grep -Fq '? " / Saved" : "")' "$pane"
grep -Fq 'detail: root.appearanceModel.wallpaperProviderDetail' "$pane"
grep -Fq 'root.appearanceModel.wallpaperCandidates' "$pane"
grep -Fq 'Component.onCompleted: {' "$pane"
grep -Fq 'root.ensureWallpaperSelection();' "$pane"
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
grep -Fq 'function appearanceWallpaperReconcile(): void' "$shell_qml"
grep -Fq 'function appearanceWallpaperStatusBusy(): bool' "$shell_qml"
grep -Fq 'function appearanceFontFamily(): string' "$shell_qml"
grep -Fq 'function appearanceFontScale(): string' "$shell_qml"
grep -Fq 'function appearanceFontPreviewState(): string' "$shell_qml"
test "$(grep -Fc 'root.selectedTheme.valid && root.selectedTheme.mutable' "$pane")" -eq 2

if grep -ERq 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$model" "$pane"; then
	printf 'Appearance model introduced a forbidden Wayland or Omarchy dependency\n' >&2
	exit 1
fi

printf 'Quickshell shared appearance model contract: PASS\n'
