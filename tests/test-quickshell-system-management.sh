#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo/config/quickshell/systemmanagement/SystemManagementModel.qml
commands=$repo/config/quickshell/core/Commands.qml
settings=$repo/config/quickshell/settings/SettingsModel.qml
shell=$repo/config/quickshell/shell.qml

test -f "$model"
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
grep -Fq 'change.action !== "update"' "$model"
grep -Fq 'else if (change.action === "update") planInvalid = true;' "$model"
grep -Fq '!summaryAvailable && parsedUpdates.length > 0' "$model"
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
[ "$(grep -Fc 'root.updateActionKind(fields[2]).length === 0' "$model")" -eq 2 ]
grep -Fq 'responseGeneration !== root.requestGeneration || !root.settingsVisible' "$model"
grep -Fq 'if (snapshotProcess.running)' "$model"
grep -Fq 'root.snapshotPending = true;' "$model"
grep -Fq 'if (!running && root.snapshotPending && root.settingsVisible)' "$model"
grep -Fq 'snapshotProcess.running = false;' "$model"
grep -Fq 'root.snapshotState === "failure"' "$model"
grep -Fq 'root.parseSnapshot(snapshotOutput.text, snapshotProcess.generation);' "$model"

grep -Fq 'property var systemManagementModel: null' "$settings"
grep -Fq 'root.systemManagementModel.openSettings()' "$settings"
grep -Fq 'root.systemManagementModel.closeSettings()' "$settings"
grep -Fq 'root.systemManagementModel.refresh()' "$settings"
grep -Fq 'import qs.systemmanagement' "$shell"
[ "$(grep -Fc 'SystemManagementModel {' "$shell")" -eq 1 ]
grep -Fq 'systemManagementModel: systemManagementModel' "$shell"
grep -Fq 'function systemManagementProviderStatus(): string' "$shell"
grep -Fq 'function systemManagementUpdateCount(): int' "$shell"
grep -Fq 'function systemManagementPackageChangeCount(): int' "$shell"
grep -Fq 'function systemManagementInstallAvailability(): string' "$shell"
grep -Fq 'function systemManagementErrorCodes(): string' "$shell"
grep -Fq 'function systemManagementSnapshotState(): string' "$shell"

printf 'Quickshell system-management snapshot model contract: PASS\n'
