#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo/config/quickshell/systemmanagement/SystemManagementModel.qml
pane=$repo/config/quickshell/settings/SystemSettingsPane.qml
commands=$repo/config/quickshell/core/Commands.qml
discovery=$repo/config/quickshell/systemmanagement/SystemUpdateDiscovery.qml
settings=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
shell=$repo/config/quickshell/shell.qml

test -f "$model"
test -f "$pane"
grep -Fq 'function systemManagementCommand(action, args)' "$commands"
grep -Fq 'function terminatingCheckedCommand(command)' "$commands"
grep -Fq 'trap terminate HUP INT TERM' "$commands"
grep -Fq "kill -TERM \"\$child\"" "$commands"
grep -Fq 'terminate_requested=0' "$commands"
grep -Fq 'ulimit -f 16384' "$commands"
grep -Fq "error_file=\$(mktemp" "$commands"
grep -Fq "2>\"\$error_file\" &" "$commands"
grep -Fq "head -c 512 \"\$error_file\" >&2" "$commands"
grep -Fq 'command: Commands.terminatingCheckedCommand(' "$model"
[ "$(grep -Fc 'Process {' "$model")" -eq 1 ]
[ "$(grep -Fc 'Process {' "$discovery")" -eq 1 ]
grep -Fq 'Commands.systemManagementCommand("watch-updates", [])' "$discovery"
grep -Fq 'stdout: SplitParser' "$discovery"
if grep -Fq 'repeat: true' "$discovery"; then
	printf 'Update discovery must not poll.\n' >&2
	exit 1
fi
if grep -Fq 'repeat: true' "$model"; then
	printf 'System-management model must not poll.\n' >&2
	exit 1
fi

grep -Fq 'recordIndex === 0 && type !== "system-management-protocol"' "$model"
grep -Fq 'fields[1] !== "1" || fields[2] !== "0"' "$model"
grep -Fq 'System management provider emitted records after completion' "$model"
grep -Fq '!headerSeen || !completeSeen || parsedGeneration.length === 0' "$model"
grep -Fq 'return /^[0-9a-f]{64}$/.test(value);' "$model"
grep -Fq 'root.utf8Bytes(text) > 8 * 1024 * 1024' "$model"
grep -Fq 'updateRecordCount > 4096' "$model"
grep -Fq 'updateBytes + recordBytes > 3 * 1024 * 1024' "$model"
grep -Fq 'changeRecordCount > 4096' "$model"
grep -Fq 'changeBytes + recordBytes > 3 * 1024 * 1024' "$model"
grep -Fq 'errorRecordCount > 4096 || errorBytes + recordBytes > 1024 * 1024' "$model"

for identifier in updates recovery update-summary update-last-refresh update-restart \
	updates-refresh updates-install-all updates-cancel; do
	grep -Fq "$identifier" "$model"
done
for tracker in seenProviders seenStates seenActions seenUpdates seenChanges; do
	grep -Fq "const $tracker = {};" "$model"
done
grep -Fq 'root.updateProvider = { "status": "partial"' "$model"
grep -Fq 'let planInvalid = false;' "$model"
grep -Fq 'let planUnsupported = false;' "$model"
grep -Fq "requestedUpdates[\"\$\" + update.packageId] = false;" "$model"
grep -Fq 'change.action !== "update" && change.action !== "install"' "$model"
grep -Fq 'else if (change.action === "update") planInvalid = true;' "$model"
grep -Fq '!summaryAvailable && parsedUpdates.length > 0' "$model"
grep -Fq 'cancelAvailable !== canCancelActive' "$model"
grep -Fq 'let planRequiresUnsupportedFlags = false;' "$model"
grep -Fq 'planUnsupported = planRequiresUnsupportedFlags;' "$model"
grep -Fq 'if (planUnsupported) {' "$model"
grep -Fq '} else if (planInvalid) {' "$model"
grep -Fq '"availability": "unavailable"' "$model"
grep -Fq 'root.packageChanges = [];' "$model"
grep -Fq 'root.packageChanges = parsedChanges;' "$model"
grep -Fq 'root.recoveryProvider = recoveryInvalid' "$model"
grep -Fq 'property var recoveryProvider: root.recoveryFallback(' "$model"
grep -Fq '"providerClass": "user-session"' "$model"
grep -Fq "Number(states[\"\$update-summary\"].value) !== parsedUpdates.length" "$model"
grep -Fq 'parsedActive !== null || parsedHandoff !== null' "$model"
[ "$(grep -Fc 'root.updateActionKind(fields[2]).length === 0' "$model")" -eq 1 ]
grep -Fq 'root.operationActionKind(fields[2]).length === 0' "$model"
grep -Fq 'responseGeneration !== root.requestGeneration' "$model"
grep -Fq 'if (root.snapshotOwned)' "$model"
grep -Fq 'root.requiredPending = root.requiredPending || required;' "$model"
grep -Fq 'root.snapshotPending && root.settingsVisible' "$model"
grep -Fq 'snapshotProcess.running = false;' "$model"
grep -Fq 'root.snapshotState = "failure"' "$model"
grep -Fq 'root.parseSnapshot(snapshotOutput.text, snapshotProcess.generation)' "$model"
grep -Fq 'onExited: (exitCode, exitStatus) => root.finishSnapshot(exitCode, exitStatus === 0)' "$model"

grep -Fq 'required property var systemManagementModel' "$pane"
grep -Fq 'required property var capabilities' "$pane"
grep -Fq 'SYSTEM STATUS' "$pane"
grep -Fq 'component PlainText: UiText {' "$pane"
grep -Fq 'textFormat: Text.PlainText' "$pane"
[ "$(grep -Fc 'UiText {' "$pane")" -eq 1 ]
grep -Fq 'activeFocusOnTab: true' "$pane"
grep -Fq 'Keys.onPressed: event =>' "$pane"
for key_name in Down Up PageDown PageUp Home End; do
	grep -Fq "Qt.Key_$key_name" "$pane"
done
grep -Fq 'Math.max(0, Math.min(position, Math.max(0, root.contentHeight - root.height)))' "$pane"
grep -Fq 'columns: root.width < 720 ? 1 : 3' "$pane"
grep -Fq 'model: root.systemManagementModel.updates' "$pane"
grep -Fq 'model: root.systemManagementModel.packageChanges' "$pane"
grep -Fq 'model: root.systemManagementModel.errors' "$pane"
grep -Fq 'errorRow.modelData.provider.toUpperCase()' "$pane"
grep -Fq 'Metadata refresh and update installation require visible confirmation.' "$pane"
grep -Fq 'SystemUpdateControls {' "$pane"
grep -Fq 'onRevealRequested: target => root.reveal(target)' "$pane"
controls=$repo/config/quickshell/settings/SystemUpdateControls.qml
grep -Fq 'root.model.prepareUpdate("updates-refresh")' "$controls"
grep -Fq 'root.model.prepareUpdate("updates-install-all")' "$controls"
grep -Fq 'root.model.confirmUpdate()' "$controls"
grep -Fq 'root.model.operation.requestCancel()' "$controls"
grep -Fq 'root.confirmation.changes' "$controls"
grep -Fq 'change.modelData.packageId' "$controls"
grep -Fq 'textFormat: Text.PlainText' "$controls"
grep -Fq 'pending.generation !== root.generation' "$model"
grep -Fq 'pending.epoch !== discoveryModel.cycle.epoch' "$model"
if grep -Eq 'Quickshell\.Io|\bProcess\b|\bCommands\.' "$controls"; then
	printf 'Update controls must not construct or run commands.\n' >&2
	exit 1
fi
if grep -Eq 'Quickshell\.Io|\bProcess\b|\bCommands\.|systemManagementCommand' "$pane"; then
	printf 'System Settings pane must not construct or run commands.\n' >&2
	exit 1
fi
pane_model_members=$(grep -Eo 'systemManagementModel\.[A-Za-z][A-Za-z0-9]*' "$pane" |
	sort -u)
expected_pane_model_members=$(printf '%s\n' \
	'systemManagementModel.activeOperation' \
	'systemManagementModel.busy' \
	'systemManagementModel.discoveryDetail' \
	'systemManagementModel.errors' \
	'systemManagementModel.message' \
	'systemManagementModel.operation' \
	'systemManagementModel.packageChanges' \
	'systemManagementModel.providerDetail' \
	'systemManagementModel.providerState' \
	'systemManagementModel.recoveryProvider' \
	'systemManagementModel.refresh' \
	'systemManagementModel.snapshotState' \
	'systemManagementModel.terminalHandoff' \
	'systemManagementModel.updateLastRefresh' \
	'systemManagementModel.updateRestart' \
	'systemManagementModel.updateSummary' \
	'systemManagementModel.updates')
if [ "$pane_model_members" != "$expected_pane_model_members" ]; then
	printf 'System Settings pane accessed a non-read-only model member.\n' >&2
	exit 1
fi
[ "$(grep -Fc 'onActivated: root.systemManagementModel.refresh()' "$pane")" -eq 1 ]

grep -Fq 'property var systemManagementModel: null' "$settings"
grep -Fq 'root.systemManagementModel.openSettings()' "$settings"
grep -Fq 'root.systemManagementModel.closeSettings()' "$settings"
grep -Fq 'root.systemManagementModel.refresh()' "$settings"
grep -Fq 'import qs.systemmanagement' "$shell"
[ "$(grep -Fc 'SystemManagementModel {' "$shell")" -eq 1 ]
grep -Fq 'systemManagementModel: systemManagementModel' "$shell"
grep -Fq 'SystemSettingsPane {' "$settings_window"
grep -Fq 'function systemManagementProviderStatus(): string' "$shell"
grep -Fq 'function systemManagementUpdateCount(): int' "$shell"
grep -Fq 'function systemManagementPackageChangeCount(): int' "$shell"
grep -Fq 'function systemManagementInstallAvailability(): string' "$shell"
grep -Fq 'function systemManagementErrorCodes(): string' "$shell"
grep -Fq 'function systemManagementSnapshotState(): string' "$shell"

printf 'Quickshell system-management snapshot model contract: PASS\n'
