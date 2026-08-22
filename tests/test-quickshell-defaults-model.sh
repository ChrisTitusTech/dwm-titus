#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
shell_qml=$repo/config/quickshell/shell.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
defaults_model=$repo/config/quickshell/defaults/DefaultAppsModel.qml
autostart_model=$repo/config/quickshell/defaults/AutostartModel.qml
defaults_pane=$repo/config/quickshell/settings/DefaultsSettingsPane.qml
commands=$repo/config/quickshell/core/Commands.qml

test "$(grep -c 'DefaultAppsModel {' "$shell_qml")" -eq 1
test "$(grep -c 'AutostartModel {' "$shell_qml")" -eq 1
grep -Fq 'defaultsModel: defaultsModel' "$shell_qml"
grep -Fq 'autostartModel: autostartModel' "$shell_qml"
grep -Fq 'DefaultsSettingsPane {' "$settings_window"
grep -Fq 'root.settingsModel.selectedSectionId === "defaults"' "$settings_window"
grep -Fq 'root.defaultsModel.openSettings()' "$settings_model"
grep -Fq 'root.defaultsModel.closeSettings()' "$settings_model"
grep -Fq 'root.autostartModel.openSettings()' "$settings_model"
grep -Fq 'root.autostartModel.closeSettings()' "$settings_model"

grep -Fq 'defaults-protocol' "$defaults_model"
grep -Fq 'defaults-result' "$defaults_model"
grep -Fq '/^[A-Za-z0-9][A-Za-z0-9._+-]*\.desktop$/' "$defaults_model"
grep -Fq 'mutationOrigin' "$defaults_model"
grep -Fq 'snapshotGeneration' "$defaults_model"
grep -Fq 'SplitParser' "$defaults_model"
grep -Fq 'Commands.defaultsHelperCommand("watch", [])' "$defaults_model"
grep -Fq 'fields[2] === "0"' "$defaults_model"
grep -Fq 'Commands.checkedCommand(Commands.defaultsHelperCommand(action, args))' "$defaults_model"
grep -Fq 'root.actionSucceeded = this.text.trim() === actionProcess.expectedResult' "$defaults_model"
grep -Fq 'function checkedCommand(command)' "$commands"
# shellcheck disable=SC2016 # The literal shell wrapper is the source contract.
grep -Fq 'output=$("$@"); status=$?' "$commands"
grep -Fq 'root.actionGeneration !== root.mutationGeneration' "$defaults_model"

grep -Fq 'autostart-protocol' "$autostart_model"
grep -Fq '/^[A-Za-z0-9][A-Za-z0-9._+-]*\.desktop$/' "$autostart_model"
grep -Fq 'confirm-session-critical' "$autostart_model"
grep -Fq 'mutationOrigin' "$autostart_model"
grep -Fq 'snapshotGeneration' "$autostart_model"
grep -Fq 'SplitParser' "$autostart_model"
grep -Fq 'Commands.autostartHelperCommand("watch", [])' "$autostart_model"
grep -Fq 'fields.length === 14' "$autostart_model"
grep -Fq '"canEnable": fields[11] === "1"' "$autostart_model"
grep -Fq '"canDisable": fields[12] === "1"' "$autostart_model"
grep -Fq 'lines.length !== 2' "$autostart_model"
grep -Fq 'effective === "enabled" || effective === "conditional"' "$autostart_model"
grep -Fq 'effective === "disabled" || effective === "non-applicable"' "$autostart_model"
grep -Fq 'root.resultStateMatches(actionProcess.expectedState, fields[4])' "$autostart_model"
grep -Fq 'if (!entry || !root.validDesktopId(entry.id) || !root.validRevision(entry.revision)' "$autostart_model"
grep -Fq 'The requested autostart change is no longer available' "$autostart_model"
grep -Fq 'Commands.checkedCommand(Commands.autostartHelperCommand(action, args))' "$autostart_model"
grep -Fq 'if (root.actionGeneration !== root.mutationGeneration) return;' "$autostart_model"
grep -Fq 'function onSearchQueryChanged()' "$defaults_pane"

if grep -Eq 'repeat:[[:space:]]*true' "$defaults_model" "$autostart_model"; then
	printf 'Defaults models must not use repeating timers.\n' >&2
	exit 1
fi

grep -Fq 'Search startup applications' "$defaults_pane"
grep -Fq 'Reset to vendor' "$defaults_pane"
grep -Fq 'Restore previous' "$defaults_pane"
grep -Fq 'Confirm session component change' "$defaults_pane"
grep -Fq 'entryCard.modelData.canEnable || entryCard.modelData.canDisable' "$defaults_pane"

printf 'Quickshell Defaults and autostart model contract: PASS\n'
