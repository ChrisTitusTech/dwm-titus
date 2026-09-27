#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
protocol=$repo/config/quickshell/updatecenter/UpdateCenterProtocol.js
model=$repo/config/quickshell/updatecenter/UpdateCenterModel.qml
commands=$repo/config/quickshell/core/Commands.qml

test -f "$protocol"
test -f "$model"
grep -Fq 'function updateCenterCommand(action, args)' "$commands"
grep -Fq 'function updateCenterSettingsCommand(action, args)' "$commands"
grep -Fq 'property var providers: []' "$model"
grep -Fq 'property int totalUpdates: 0' "$model"
grep -Fq 'property var activeOperation: null' "$model"
grep -Fq 'property bool online: true' "$model"
grep -Fq 'interval: 30000' "$model"
grep -Fq 'repeat: false' "$model"
grep -Fq 'root.refresh(false)' "$model"
grep -Fq 'if (!root.online || scanProcess.running)' "$model"
grep -Fq 'root.refresh(true)' "$model"
grep -Fq 'Commands.updateCenterCommand("snapshot", force ? ["--force"] : [])' "$model"
grep -Fq 'Commands.updateCenterCommand("active", [])' "$model"
grep -Fq 'Commands.updateCenterCommand(action, [providerId])' "$model"
grep -Fq 'Commands.updateCenterSettingsCommand("set",' "$model"
grep -Fq 'draftRefreshSeconds < 300 || draftRefreshSeconds > 21600' "$model"
grep -Fq 'root.providers = parsed.providers;' "$model"
grep -Fq 'root.activeOperation = parsed.operationId.length > 0 ? parsed : null;' "$model"
grep -Fq 'readonly property bool busy: root.activeOperation !== null' "$model"
grep -Fq 'action !== "recover" || !recoverable' "$model"
grep -Fq 'return root.busy || root.hasExceptionalState() || root.totalUpdates > 0 || root.savedAlwaysShow;' "$model"
[ "$(grep -Fc 'Process {' "$model")" -eq 4 ]

if grep -Eq '(^|[^A-Za-z])(XMLHttpRequest|LocalStorage|FileDialog|StandardPaths)([^A-Za-z]|$)' "$model"; then
	printf '%s\n' 'Update Center QML must not read or write files directly.' >&2
	exit 1
fi

qml_runner=
for candidate in /usr/lib64/qt6/bin/qml /usr/lib/qt6/bin/qml qml6 qml; do
	if command -v "$candidate" >/dev/null 2>&1; then
		qml_runner=$(command -v "$candidate")
		break
	fi
done
if [ -n "$qml_runner" ]; then
	QT_QPA_PLATFORM=offscreen "$qml_runner" "$repo/tests/quickshell-update-center-model.qml"
else
	printf '%s\n' 'SKIP: Qt 6 qml runner is unavailable; protocol runtime assertions were not run.'
fi

printf '%s\n' 'Quickshell Update Center model contract: PASS'
