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
grep -Fq 'property bool capabilityRefreshPending: false' "$settings_model"
grep -Fq 'function refreshCapabilities()' "$settings_model"
grep -Fq 'root.capabilityRefreshPending = true;' "$settings_model"
grep -Fq 'if (root.discoveryState !== "ready" || root.capabilityRefreshPending)' "$settings_model"
grep -Fq '"detail": "Capability discovery is still refreshing"' "$settings_model"
awk '
	/id: providerProcess/ { in_provider = 1 }
	in_provider && /onRunningChanged: \{/ {
		in_handler = 1
		depth = 0
	}
	in_handler {
		line = $0
		opens = gsub(/\{/, "", line)
		closes = gsub(/\}/, "", line)
		depth += opens - closes
		if (/root.capabilityRefreshPending = false;/ && !cleared) cleared = NR
		if (/Qt.callLater\(function\(\) \{/ && !deferred) deferred = NR
		if (/if \(!providerProcess.running\) root.refreshCapabilities\(\);/ && !guarded) guarded = NR
		if (depth == 0) {
			in_handler = 0
			verified = cleared && deferred && guarded && cleared < deferred && deferred < guarded
		}
	}
	END {
		exit !verified
	}
' "$settings_model"
grep -Fq 'function onPersonalizationSelectionsChanged()' "$settings_model"
grep -Fq 'root.refreshCapabilities();' "$settings_model"
grep -Fq 'AppearanceSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "appearance"' "$settings_window"
grep -Fq 'capability.id !== "themes"' "$settings_window"
grep -Fq 'textScaleCapability: root.settingsModel.capabilityById(' "$settings_window"
grep -Fq 'function capabilityById(id)' "$settings_model"
grep -Fq 'deviceCard.modelData.kind === "accessibility"' "$input_pane"
grep -Fq 'accessibleDescription: settingRow.modelData.label + ". Starts a timed preview."' "$input_pane"
grep -Fq 'if (settingsModel.previewKind !== "input") return;' "$shell_qml"
grep -Fq 'if (settingsModel.previewOperationLocked) return;' "$shell_qml"

grep -Fq 'function settingsAppearanceCommand(action, args)' "$commands"
grep -Fq 'function settingsFontCommand(action, args)' "$commands"
grep -Fq 'function settingsPersonalizationCommand(action, args)' "$commands"
grep -Fq 'function settingsXsettingsCommand(action, args)' "$commands"
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
grep -Fq 'property bool mutationReadinessPending: false' "$model"
grep -Fq 'root.mutationReady = false;' "$model"
grep -Fq 'if (readinessProcess.running || actionProcess.running) {' "$model"
grep -Fq 'root.mutationReadinessPending = true;' "$model"
grep -Fq 'if (!running && root.mutationReadinessPending && !actionProcess.running) {' "$model"
grep -Fq 'onStreamFinished: root.mutationReady = !root.mutationReadinessPending' "$model"
for mutation_function in startPreview applyTheme resetTheme; do
	sed -n "/function $mutation_function(/,/^    }/p" "$model" |
		grep -Fq 'root.mutationReadinessPending'
done
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
grep -Fq 'function finishInventoryWatcherExit()' "$model"
sed -n '/function startInventoryWatcher(restartIfRunning)/,/^    }/p' "$model" |
	grep -Fq 'if (!root.settingsVisible) return;'
sed -n '/function startInventoryWatcher(restartIfRunning)/,/^    }/p' "$model" |
	grep -Fq 'if (inventoryWatchExitSettleTimer.running) {'
watcher_exit_handler=$(sed -n '/id: inventoryWatchProcess/,/^    }/p' "$model")
printf '%s\n' "$watcher_exit_handler" |
	grep -Fq 'if (root.settingsVisible) inventoryWatchExitSettleTimer.restart();'
if printf '%s\n' "$watcher_exit_handler" | grep -Fq 'root.inventoryWatchFailed = true'; then
	printf 'Inventory watcher still classifies failure before stdout has settled\n' >&2
	exit 1
fi
grep -Fq 'id: inventoryWatchExitSettleTimer' "$model"
grep -Fq 'onTriggered: root.finishInventoryWatcherExit()' "$model"
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
grep -Fq 'candidate.id === "cursor"' "$model"
grep -Fq 'candidate.id === "icon"' "$model"
grep -Fq 'candidate.id === "gtk"' "$model"
grep -Fq 'candidate.id === "qt"' "$model"
grep -Fq 'personalization-protocol' "$model"
grep -Fq 'personalization-action-protocol' "$model"
grep -Fq 'const payload = text.endsWith("\n") ? text.slice(0, -1) : text;' "$model"
grep -Fq 'const lines = payload.split("\n");' "$model"
if sed -n '/function parsePersonalizationAction/,/^    }/p' "$model" | grep -Fq 'text.trim()'; then
	printf 'Personalization action parsing still strips valid payload whitespace\n' >&2
	exit 1
fi
grep -Fq 'fields[0] === "action-readiness"' "$model"
grep -Fq 'function personalizationApplyReady(capability)' "$model"
grep -Fq 'function personalizationResetReady(capability)' "$model"
grep -Fq 'function personalizationEffectiveState(capability)' "$model"
grep -Fq 'function personalizationEffectiveDetail(capability)' "$model"
grep -Fq 'function personalizationCandidates(capability, limit)' "$model"
grep -Fq 'seen.indexOf(token) >= 0' "$model"
grep -Fq 'seen.indexOf(candidate.token) >= 0' "$model"
personalization_candidates=$(sed -n '/function personalizationCandidates(capability, limit)/,/^    }/p' "$model")
if printf '%s\n' "$personalization_candidates" | grep -Fq 'const seen = {};'; then
	printf 'Personalization candidates still use a prototype-bearing token set\n' >&2
	exit 1
fi
if printf '%s\n' "$personalization_candidates" |
	grep -Fq 'token === inventory.value && inventory.state === "available"'; then
	printf 'Personalization candidates still synthesize values outside the helper inventory contract\n' >&2
	exit 1
fi
grep -Fq 'if (!root.personalizationStatusParsed) return "unavailable";' "$model"
grep -Fq '"id": capability, "state": "unavailable"' "$model"
grep -Fq 'root.personalizationEffectiveState(capability) !== "available"' "$model"
grep -Fq 'Commands.settingsPersonalizationCommand("status", [])' "$model"
if grep -Fq 'Commands.checkedCommand(Commands.settingsPersonalizationCommand("status"' "$model"; then
	printf 'Personalization status remained behind the orphan-prone checked-command wrapper\n' >&2
	exit 1
fi
grep -Fq 'fields[0] === "complete"' "$model"
grep -Fq '["personalization-protocol", "provider", "mutation", "repair", "watch-readiness", "selection",' "$model"
grep -Fq '].indexOf(fields[0]) >= 0' "$model"
grep -Fq 'invalid || !protocolValid || !completeSeen' "$model"
grep -Fq 'Commands.settingsPersonalizationCommand(action, args)' "$model"
grep -Fq 'function applyPersonalization(capability, value)' "$model"
grep -Fq 'function resetPersonalization(capability)' "$model"
grep -Fq 'function delegatePersonalization(capability)' "$model"
grep -Fq 'editor launch requested' "$model"
if grep -Fq 'settings opened' "$model"; then
	printf 'Delegated editor handoff claims the asynchronous editor opened\n' >&2
	exit 1
fi
grep -Fq 'function repairPersonalization()' "$model"
grep -Fq 'root.personalizationActionKind === "repair")' "$model"
grep -Fq 'Commands.settingsPersonalizationCommand("repair", [])' "$model"
grep -Fq 'preferred = personalizationControl.inventorySelection.value;' "$pane"
grep -Fq 'personalizationControl.selectedValue = "";' "$pane"
grep -Fq 'property bool selectionDirty: false' "$pane"
grep -Fq 'personalizationControl.selectionDirty && !savedOptionChanged' "$pane"
grep -Fq 'personalizationControl.selectionDirty = true;' "$pane"
grep -Fq 'text: personalizationControl.readiness.detail' "$pane"
grep -Fq 'function onPersonalizationBusyChanged()' "$pane"
if grep -Fq 'personalizationControl.candidates[0].token' "$pane"; then
	printf 'Desktop personalization still preselects an unrelated fallback candidate\n' >&2
	exit 1
fi
grep -Fq 'statusState: personalizationControl.effectiveState' "$pane"
grep -Fq 'detail: personalizationControl.effectiveDetail + " / "' "$pane"
test "$(grep -Fc 'personalizationCandidates(' "$pane")" -eq 5
if grep -Eq '(cursor|icon|gtk|qt)Candidates[.]slice[(]0, 24[)]' "$pane" ||
	[ "$(grep -Fc 'fontCandidates.slice(0, 24)' "$pane")" -ne 1 ]; then
	printf 'Desktop personalization still truncates active choices before selection\n' >&2
	exit 1
fi
grep -Fq 'function appearancePersonalizationEffectiveState(capability: string)' "$shell_qml"
grep -Fq 'root.previewState !== "none" || root.recoveryState !== "none"' "$model"
test "$(grep -Fc 'root.previewState !== "none" || root.recoveryState !== "none"' "$model")" -eq 4
grep -Fq 'const candidates = root.personalizationCandidates(capability, 24);' "$model"
grep -Fq 'function personalizationSavedAssetState(capability)' "$model"
grep -Fq 'Saved override asset is unavailable; reset or choose an installed option' "$model"
application_state=$(sed -n '/readonly property string applicationState:/,/^    }/p' "$model")
if printf '%s\n' "$application_state" | grep -Fq 'personalizationMutationState'; then
	printf 'Read-only appearance application state still includes mutation readiness\n' >&2
	exit 1
fi
grep -Fq 'root.personalizationActionKind === "delegate")' "$model"
grep -Fq 'if (!root.settingsVisible) return;' "$model"
grep -Fq 'personalizationStatusProcess.running = false;' "$model"
grep -Fq 'root.configHome + "/dwm-titus/personalization.conf"' "$model"
grep -Fq 'root.personalizationMutationState !== "available"' "$model"
grep -Fq 'action === "apply" && !root.personalizationApplyReady(capability)' "$model"
grep -Fq 'action === "reset" && !root.personalizationResetReady(capability)' "$model"
grep -Fq 'root.personalizationCandidateAvailable(capability, value)' "$model"
grep -Fq 'value === "follow-theme" || value === "gtk3"' "$model"
grep -Fq 'property bool xsettingsWatchReady: false' "$model"
grep -Fq 'property bool xsettingsWatchProtocolSeen: false' "$model"
grep -Fq 'property bool xsettingsWatchSawEvent: false' "$model"
grep -Fq 'property bool xsettingsWatchFailed: false' "$model"
grep -Fq 'command: Commands.settingsXsettingsCommand("watch", [])' "$model"
grep -Fq 'fields[0] === "watch-readiness"' "$model"
grep -Fq 'root.xsettingsWatchReady = xsettingsWatch.state === "available"' "$model"
grep -Fq '&& !root.xsettingsWatchFailed;' "$model"
grep -Fq 'line === "changed" && root.xsettingsWatchProtocolSeen' "$model"
grep -Fq 'root.xsettingsWatchSawEvent = true;' "$model"
grep -Fq 'root.xsettingsWatchFailed = true;' "$model"
if grep -Fq 'id: xsettingsWatchRestartTimer' "$model"; then
	printf 'XSETTINGS lifecycle failure still has an unbounded retry timer\n' >&2
	exit 1
fi
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
watcher_exit_finalizer=$(sed -n '/function finishInventoryWatcherExit()/,/^    }/p' "$model")
printf '%s\n' "$watcher_exit_finalizer" |
	grep -Fq 'if (root.inventoryWatchRestartPending && !root.inventoryWatchFailed) {'
printf '%s\n' "$watcher_exit_finalizer" |
	grep -Fq 'root.inventoryWatchRestartPending = false;'
printf '%s\n' "$watcher_exit_finalizer" |
	grep -Fq 'if (root.inventoryWatchSawEvent) inventoryWatchRestartTimer.restart();'
printf '%s\n' "$watcher_exit_finalizer" |
	grep -Fq '} else if (!root.inventoryWatchSawEvent && !root.inventoryWatchFailed) {'
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
grep -Fq 'if (root.previewStatusManualOnly && force !== true) return;' "$model"
grep -Fq 'root.previewStatusManualOnly = true;' "$model"
grep -Fq 'root.previewStatusManualOnly = false;' "$model"
grep -Fq 'root.appearanceModel.refreshAll(true)' "$pane"
finish_action=$(sed -n '/function finishAction()/,/^    }/p' "$model")
test "$(printf '%s\n' "$finish_action" | grep -Fc 'root.previewStatusManualOnly = false;')" -eq 2
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
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$display_pane")" -eq 13
test "$(grep -Ec 'font\.pixelSize: Theme\.(bodyFontSize|inputFontSize)' "$input_pane")" -eq 5
grep -Fq 'font.pixelSize: Theme.inputFontSize' "$network_pane"
grep -Fq 'passwordInput.implicitHeight + 2 * Theme.spacingSm' "$network_pane"
grep -Fq 'xPositionInput.implicitHeight + 10' "$display_pane"
grep -Fq 'yPositionInput.implicitHeight + 10' "$display_pane"
grep -Fq 'Math.max(88, outputContent.implicitHeight + 12)' "$display_pane"
grep -Fq 'profileNameInput.implicitHeight + 12' "$display_pane"
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
grep -Fq 'label: "Desktop applications"' "$pane"
grep -Fq 'component PersonalizationControl: ColumnLayout' "$pane"
grep -Fq 'capability: "text-size"' "$pane"
grep -Fq 'capability: "cursor"' "$pane"
grep -Fq 'capability: "icon"' "$pane"
grep -Fq 'capability: "gtk"' "$pane"
grep -Fq 'capability: "qt"' "$pane"
grep -Fq 'root.appearanceModel.applyPersonalization(' "$pane"
grep -Fq 'root.appearanceModel.resetPersonalization(' "$pane"
grep -Fq 'root.appearanceModel.delegatePersonalization(' "$pane"
grep -Fq 'root.appearanceModel.repairPersonalization()' "$pane"
grep -Fq 'label: "Repair personalization state"' "$pane"
grep -Fq 'root.appearanceModel.personalizationActionKind !== "delegate"' "$pane"
grep -Fq 'readonly property bool personalizationActionsReady:' "$pane"
grep -Fq '&& !root.appearanceModel.personalizationStatusBusy' "$pane"
test "$(grep -Fc 'enabled: root.personalizationActionsReady' "$pane")" -eq 2
grep -Fq 'readonly property bool personalizationDelegatesReady:' "$pane"
grep -Fq 'enabled: root.personalizationDelegatesReady && !root.appearanceBusy' "$pane"
grep -Fq 'The managed shell font above remains independent' "$pane"
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
grep -Fq 'SectionLabel { label: "Accessibility" }' "$pane"
grep -Fq 'readonly property var accessibilityCapabilities:' "$pane"
grep -Fq 'capability.id !== "accessibility-text-scale"' "$pane"
grep -Fq 'capability.id !== "accessibility-contrast"' "$pane"
grep -Fq 'capability.id !== "accessibility-reduced-motion"' "$pane"
grep -Fq 'required property var textScaleCapability' "$pane"
grep -Fq 'property var capabilityGate: null' "$pane"
grep -Fq 'readonly property bool gateAllowsActions:' "$pane"
grep -Fq 'personalizationControl.capabilityGate.status === "partial"' "$pane"
grep -Fq 'capabilityGate: root.textScaleCapability' "$pane"
test "$(grep -Fc '&& personalizationControl.gateAllowsActions' "$pane")" -eq 2
grep -Fq 'enabled: personalizationControl.gateAllowsActions && !root.appearanceBusy' "$pane"
grep -Fq 'model: root.accessibilityCapabilities' "$pane"
grep -Fq 'model: root.additionalCapabilities' "$pane"
grep -Fq 'text: "Managed-shell contrast and motion choices apply immediately' "$pane"
grep -Fq '|| !root.accessibilityModel.mutationReady' "$pane"
grep -Fq ': root.accessibilityModel.mutationState' "$pane"
grep -Fq ': root.accessibilityModel.mutationDetail' "$pane"
if grep -Fq 'Text scaling is available now' "$pane"; then
	printf 'Accessibility summary makes an unconditional text-scale availability claim\n' >&2
	exit 1
fi
test "$(grep -Fc 'component PersonalizationControl: ColumnLayout' "$pane")" -eq 1
personalization_actions=$(sed -n '/component PersonalizationControl: ColumnLayout/,/^    }/p' "$pane")
printf '%s\n' "$personalization_actions" | grep -Fq 'Flow {'
if printf '%s\n' "$personalization_actions" | grep -Fq 'RowLayout {'; then
	printf 'Personalization actions do not wrap at compact display sizes\n' >&2
	exit 1
fi
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
grep -Fq 'function appearancePersonalizationStatus(): string' "$shell_qml"
grep -Fq 'function appearancePersonalizationOption(capability: string): string' "$shell_qml"
grep -Fq 'function appearanceRefresh(): void' "$shell_qml"
grep -Fq 'function capabilityStatus(capabilityId: string): string' "$shell_qml"
test "$(grep -Fc 'root.selectedTheme.valid && root.selectedTheme.mutable' "$pane")" -eq 2

if grep -ERq 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$model" "$pane"; then
	printf 'Appearance model introduced a forbidden Wayland or Omarchy dependency\n' >&2
	exit 1
fi

printf 'Quickshell shared appearance model contract: PASS\n'
