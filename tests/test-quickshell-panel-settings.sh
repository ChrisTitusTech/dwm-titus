#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
helper=$repo/scripts/dwm-panel-settings
model=$repo/config/quickshell/panel/PanelSettingsModel.qml
shell=$repo/config/quickshell/shell.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
control_model=$repo/config/quickshell/controlcenter/ControlCenterModel.qml
control_window=$repo/config/quickshell/controlcenter/ControlCenterWindow.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
appearance_pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
commands=$repo/config/quickshell/core/Commands.qml
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

home=$work/home
config=$work/config
runtime=$work/runtime
mkdir -p "$home" "$config" "$runtime"

run_helper() {
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime "$helper" "$@"
}

status=$(run_helper status)
printf '%s\n' "$status" | grep -Fqx 'panel-settings-protocol	1	1'
printf '%s\n' "$status" | grep -Fqx 'option	clock-seconds	disabled'
test "$(printf '%s\n' "$status" | wc -l)" -eq 10
printf '%s\n' "$status" | grep -Fqx \
	'state	defaults	Using safe all-on defaults; the first change creates persistent state'
for widget in workspaces volume bluetooth network power keyboard-layout; do
	printf '%s\n' "$status" | grep -Fqx "widget	$widget	enabled"
done
printf '%s\n' "$status" | grep -Fqx 'complete	status'

lock_ready=$work/lock.ready
lock_release=$work/lock.release
(
	exec 8>"$runtime/dwm-panel-settings.lock"
	flock 8
	: >"$lock_ready"
	while [ ! -e "$lock_release" ]; do
		sleep 0.01
	done
) &
lock_holder_pid=$!
for _ in $(seq 1 200); do
	test -e "$lock_ready" && break
	sleep 0.01
done
test -e "$lock_ready"
set +e
HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	timeout 7 "$helper" reset >"$work/lock.out" 2>"$work/lock.err"
lock_status=$?
set -e
: >"$lock_release"
wait "$lock_holder_pid"
test "$lock_status" -eq 1
grep -Fqx 'dwm-panel-settings: another panel settings operation is still running' "$work/lock.err"

run_helper set volume disabled | grep -Fqx 'result	set	volume	disabled'
state_file=$config/dwm-titus/panel-widgets.conf
test "$(stat -c %a "$state_file")" = 600
grep -Fqx 'panel-settings-protocol	1	0' "$state_file"
grep -Fqx 'volume	disabled' "$state_file"
persisted=$(run_helper status)
printf '%s\n' "$persisted" | grep -Fqx 'widget	volume	disabled'
printf '%s\n' "$persisted" | grep -Fqx \
	'state	available	Persistent panel visibility is active for every monitor'

# Options at their defaults keep the 1.0 file format for older helpers.
test "$(wc -l <"$state_file")" -eq 6
run_helper set clock-seconds enabled | grep -Fqx 'result	set	clock-seconds	enabled'
grep -Fqx 'panel-settings-protocol	1	1' "$state_file"
grep -Fqx 'option	clock-seconds	enabled' "$state_file"
grep -Fqx 'volume	disabled' "$state_file"
seconds_status=$(run_helper status)
printf '%s\n' "$seconds_status" | grep -Fqx 'option	clock-seconds	enabled'
printf '%s\n' "$seconds_status" | grep -Fqx 'widget	volume	disabled'
printf '%s\n' "$seconds_status" | grep -Fqx \
	'state	available	Persistent panel visibility is active for every monitor'
run_helper set volume enabled >/dev/null
grep -Fqx 'option	clock-seconds	enabled' "$state_file"
run_helper set volume disabled >/dev/null
run_helper set clock-seconds disabled | grep -Fqx 'result	set	clock-seconds	disabled'
grep -Fqx 'panel-settings-protocol	1	0' "$state_file"
if grep -Fq 'option' "$state_file"; then
	printf 'Default options were not written as a 1.0 file\n' >&2
	exit 1
fi
if run_helper set clock-seconds maybe >/dev/null 2>&1; then
	printf 'Panel settings accepted an invalid option value\n' >&2
	exit 1
fi
if run_helper set clock-minutes enabled >/dev/null 2>&1; then
	printf 'Panel settings accepted an unknown option\n' >&2
	exit 1
fi

# A legacy 1.0 file (header plus five records) keeps its widget choices.
printf 'panel-settings-protocol\t1\t0\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tdisabled\nnetwork\tenabled\npower\tenabled\n' \
	>"$state_file"
legacy=$(run_helper status)
printf '%s\n' "$legacy" | grep -Fqx \
	'state	available	Persistent panel visibility is active for every monitor'
printf '%s\n' "$legacy" | grep -Fqx 'widget	volume	disabled'
printf '%s\n' "$legacy" | grep -Fqx 'widget	bluetooth	disabled'
printf '%s\n' "$legacy" | grep -Fqx 'option	clock-seconds	disabled'
run_helper set clock-seconds enabled >/dev/null
grep -Fqx 'bluetooth	disabled' "$state_file"
grep -Fqx 'volume	disabled' "$state_file"
run_helper set clock-seconds disabled >/dev/null
run_helper set bluetooth enabled >/dev/null

# keyboard-layout: the sixth widget. Files from before it list exactly the five
# legacy widgets; it is then on, and other choices and options are kept.
printf 'panel-settings-protocol\t1\t1\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\noption\tclock-seconds\tenabled\n' \
	>"$state_file"
legacy_kbd=$(run_helper status)
printf '%s\n' "$legacy_kbd" | grep -Fqx \
	'state	available	Persistent panel visibility is active for every monitor'
printf '%s\n' "$legacy_kbd" | grep -Fqx 'widget	keyboard-layout	enabled'
printf '%s\n' "$legacy_kbd" | grep -Fqx 'widget	volume	disabled'
printf '%s\n' "$legacy_kbd" | grep -Fqx 'option	clock-seconds	enabled'
run_helper set keyboard-layout disabled | grep -Fqx 'result	set	keyboard-layout	disabled'
grep -Fqx 'keyboard-layout	disabled' "$state_file"
grep -Fqx 'option	clock-seconds	enabled' "$state_file"
grep -Fqx 'volume	disabled' "$state_file"
test "$(wc -l <"$state_file")" -eq 8
kbd_off=$(run_helper status)
printf '%s\n' "$kbd_off" | grep -Fqx 'widget	keyboard-layout	disabled'
printf '%s\n' "$kbd_off" | grep -Fqx 'option	clock-seconds	enabled'
printf '%s\n' "$kbd_off" | grep -Fqx \
	'state	available	Persistent panel visibility is active for every monitor'
# Reset turns it back on and keeps the seconds option.
run_helper reset >/dev/null
if grep -Fq 'keyboard-layout' "$state_file"; then
	printf 'An enabled keyboard-layout was written to the file\n' >&2
	exit 1
fi
grep -Fqx 'option	clock-seconds	enabled' "$state_file"
run_helper status | grep -Fqx 'widget	keyboard-layout	enabled'
# Enabled again is not written, so older helpers still read the file.
run_helper set clock-seconds disabled >/dev/null
run_helper set keyboard-layout disabled >/dev/null
grep -Fqx 'panel-settings-protocol	1	0' "$state_file"
grep -Fqx 'keyboard-layout	disabled' "$state_file"
run_helper set keyboard-layout enabled >/dev/null
test "$(wc -l <"$state_file")" -eq 6
if grep -Fq 'keyboard-layout' "$state_file"; then
	printf 'An enabled keyboard-layout was written to the file\n' >&2
	exit 1
fi
# Exactly the five legacy widgets are required; keyboard-layout cannot stand
# in for a missing one, and duplicates are rejected.
for broken_widgets in \
	'workspaces	enabled\nvolume	enabled\nbluetooth	enabled\nnetwork	enabled\nkeyboard-layout	enabled' \
	'workspaces	enabled\nvolume	enabled\nbluetooth	enabled\nnetwork	enabled' \
	'workspaces	enabled\nvolume	enabled\nbluetooth	enabled\nnetwork	enabled\npower	enabled\nkeyboard-layout	enabled\nkeyboard-layout	disabled' \
	'workspaces	enabled\nvolume	enabled\nbluetooth	enabled\nnetwork	enabled\npower	enabled\nkeyboard	disabled'; do
	# shellcheck disable=SC2059
	printf "panel-settings-protocol\t1\t0\n$broken_widgets\n" >"$state_file"
	broken=$(run_helper status)
	printf '%s\n' "$broken" | grep -Fq 'state	partial	'
	printf '%s\n' "$broken" | grep -Fqx 'widget	keyboard-layout	enabled'
done
printf 'panel-settings-protocol\t1\t0\nworkspaces\tenabled\nvolume\tenabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\n' \
	>"$state_file"
if run_helper set keyboard maybe >/dev/null 2>&1; then
	printf 'Panel settings accepted an unknown widget\n' >&2
	exit 1
fi

# Option lines are only valid in 1.1 files; malformed option lines fall back.
printf 'panel-settings-protocol\t1\t0\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\noption\tclock-seconds\tenabled\n' \
	>"$state_file"
run_helper status | grep -Fqx \
	'state	partial	Malformed panel settings were preserved; using all-on defaults'
for bad_option in "option	clock-seconds	on" "option	clock-minutes	enabled" "option	clock-seconds" \
	"option	clock-seconds	enabled	x"; do
	printf 'panel-settings-protocol\t1\t1\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\n%s\n' \
		"$bad_option" >"$state_file"
	bad=$(run_helper status)
	printf '%s\n' "$bad" | grep -Fqx \
		'state	partial	Malformed panel settings were preserved; using all-on defaults'
	printf '%s\n' "$bad" | grep -Fqx 'option	clock-seconds	disabled'
done
printf 'panel-settings-protocol\t1\t1\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\noption\tclock-seconds\tenabled\noption\tclock-seconds\tenabled\n' \
	>"$state_file"
run_helper status | grep -Fqx \
	'state	partial	Malformed panel settings were preserved; using all-on defaults'
printf 'panel-settings-protocol\t1\t1\nworkspaces\tenabled\nvolume\tdisabled\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\n' \
	>"$state_file"
run_helper status | grep -Fqx 'widget	volume	disabled'

chmod 640 "$state_file"
run_helper set network disabled >/dev/null
test "$(stat -c %a "$state_file")" = 640
grep -Fqx 'volume	disabled' "$state_file"
grep -Fqx 'network	disabled' "$state_file"

chmod 666 "$state_file"
unsafe_mode=$(run_helper status)
printf '%s\n' "$unsafe_mode" | grep -Fqx \
	'state	unavailable	Persistent panel state is unsafe; using all-on defaults'
if run_helper set network enabled >"$work/unsafe-mode.out" 2>"$work/unsafe-mode.err"; then
	printf 'Panel settings accepted a writable-by-others state file\n' >&2
	exit 1
fi
test "$(stat -c %a "$state_file")" = 666
chmod 640 "$state_file"

printf 'panel-settings-protocol\t2\t0\nvolume\tdisabled\n' >"$state_file"
future=$(run_helper status)
printf '%s\n' "$future" | grep -Fqx \
	'state	partial	Unsupported panel settings version was preserved; using all-on defaults'
for widget in workspaces volume bluetooth network power keyboard-layout; do
	printf '%s\n' "$future" | grep -Fqx "widget	$widget	enabled"
done
grep -Fqx 'panel-settings-protocol	2	0' "$state_file"

printf 'broken\n' >"$state_file"
malformed=$(run_helper status)
printf '%s\n' "$malformed" | grep -Fqx \
	'state	partial	Malformed panel settings were preserved; using all-on defaults'
grep -Fqx broken "$state_file"

for malformed_record in "volume		disabled" "	volume	disabled" "volume	disabled	"; do
	{
		printf 'panel-settings-protocol\t1\t0\n'
		printf 'workspaces\tenabled\n%s\nbluetooth\tenabled\nnetwork\tenabled\npower\tenabled\n' \
			"$malformed_record"
	} >"$state_file"
	malformed=$(run_helper status)
	printf '%s\n' "$malformed" | grep -Fqx \
		'state	partial	Malformed panel settings were preserved; using all-on defaults'
	for widget in workspaces volume bluetooth network power; do
		printf '%s\n' "$malformed" | grep -Fqx "widget	$widget	enabled"
	done
done

run_helper set power disabled >/dev/null
grep -Fqx 'power	disabled' "$state_file"
for widget in workspaces volume bluetooth network; do
	grep -Fqx "$widget	enabled" "$state_file"
done

ready=$work/publish.ready
release=$work/publish.release
DWM_TEST_PANEL_PUBLISH_READY=$ready DWM_TEST_PANEL_PUBLISH_RELEASE=$release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set bluetooth disabled >"$work/race.out" 2>"$work/race.err" &
race_pid=$!
for _ in $(seq 1 200); do
	test -e "$ready" && break
	sleep 0.01
done
test -e "$ready"
printf 'external edit\n' >"$state_file"
: >"$release"
if wait "$race_pid"; then
	printf 'Panel settings transaction overwrote a concurrent edit\n' >&2
	exit 1
fi
grep -Fq 'panel state changed during the transaction' "$work/race.err"
grep -Fqx 'external edit' "$state_file"

# "Show all widgets" (reset) brings every widget back but keeps the seconds option.
run_helper set clock-seconds enabled >/dev/null
run_helper set network disabled >/dev/null
run_helper reset >/dev/null
reset_status=$(run_helper status)
printf '%s\n' "$reset_status" | grep -Fqx 'option	clock-seconds	enabled'
run_helper set clock-seconds disabled >/dev/null
for widget in workspaces volume bluetooth network power keyboard-layout; do
	printf '%s\n' "$reset_status" | grep -Fqx "widget	$widget	enabled"
done

exchange_ready=$work/exchange.ready
exchange_release=$work/exchange.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set bluetooth disabled >"$work/exchange-race.out" 2>"$work/exchange-race.err" &
exchange_race_pid=$!
for _ in $(seq 1 200); do
	test -e "$exchange_ready" && break
	sleep 0.01
done
test -e "$exchange_ready"
printf 'last-moment external edit\n' >"$state_file"
: >"$exchange_release"
if wait "$exchange_race_pid"; then
	printf 'Panel settings exchange overwrote a last-moment concurrent edit\n' >&2
	exit 1
fi
grep -Fq 'panel state changed during the transaction' "$work/exchange-race.err"
grep -Fqx 'last-moment external edit' "$state_file"

run_helper reset >/dev/null

exchange_ready=$work/two-edit-exchange.ready
exchange_release=$work/two-edit-exchange.release
rollback_ready=$work/two-edit-rollback.ready
rollback_release=$work/two-edit-rollback.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	DWM_TEST_PANEL_ROLLBACK_READY=$rollback_ready DWM_TEST_PANEL_ROLLBACK_RELEASE=$rollback_release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set bluetooth disabled >"$work/two-edit-race.out" 2>"$work/two-edit-race.err" &
two_edit_race_pid=$!
for _ in $(seq 1 200); do
	test -e "$exchange_ready" && break
	sleep 0.01
done
test -e "$exchange_ready"
printf 'first last-moment edit\n' >"$state_file"
: >"$exchange_release"
for _ in $(seq 1 200); do
	test -e "$rollback_ready" && break
	sleep 0.01
done
test -e "$rollback_ready"
printf 'second last-moment edit\n' >"$state_file"
: >"$rollback_release"
if wait "$two_edit_race_pid"; then
	printf 'Panel settings exchange overwrote a two-edit race\n' >&2
	exit 1
fi
grep -Fq 'panel state changed during the transaction' "$work/two-edit-race.err"
grep -Fqx 'second last-moment edit' "$state_file"

run_helper reset >/dev/null

unsafe_target=$work/exchange-symlink-target
printf 'unsafe replacement target\n' >"$unsafe_target"
exchange_ready=$work/symlink-exchange.ready
exchange_release=$work/symlink-exchange.release
DWM_TEST_PANEL_EXCHANGE_READY=$exchange_ready DWM_TEST_PANEL_EXCHANGE_RELEASE=$exchange_release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set bluetooth disabled >"$work/symlink-race.out" 2>"$work/symlink-race.err" &
symlink_race_pid=$!
for _ in $(seq 1 200); do
	test -e "$exchange_ready" && break
	sleep 0.01
done
test -e "$exchange_ready"
mv "$state_file" "$work/pre-symlink-state"
ln -s "$unsafe_target" "$state_file"
: >"$exchange_release"
if wait "$symlink_race_pid"; then
	printf 'Panel settings exchange replaced a concurrent symlink\n' >&2
	exit 1
fi
grep -Fq 'panel state changed during the transaction' "$work/symlink-race.err"
test -L "$state_file"
test "$(readlink "$state_file")" = "$unsafe_target"

unlink "$state_file"
mv "$work/pre-symlink-state" "$state_file"
run_helper reset >/dev/null

baseline_ready=$work/baseline.ready
baseline_release=$work/baseline.release
DWM_TEST_PANEL_BASELINE_READY=$baseline_ready DWM_TEST_PANEL_BASELINE_RELEASE=$baseline_release \
	HOME=$home XDG_CONFIG_HOME=$config XDG_RUNTIME_DIR=$runtime \
	"$helper" set network disabled >"$work/baseline-race.out" 2>"$work/baseline-race.err" &
baseline_race_pid=$!
for _ in $(seq 1 200); do
	test -e "$baseline_ready" && break
	sleep 0.01
done
test -e "$baseline_ready"
sed -i 's/^power	enabled$/power	disabled/' "$state_file"
: >"$baseline_release"
if wait "$baseline_race_pid"; then
	printf 'Panel settings transaction overwrote an edit made before parsing\n' >&2
	exit 1
fi
grep -Fq 'panel state changed during the transaction' "$work/baseline-race.err"
grep -Fqx 'network	enabled' "$state_file"
grep -Fqx 'power	disabled' "$state_file"

mv "$state_file" "$work/real-state"
ln -s "$work/real-state" "$state_file"
unsafe=$(run_helper status)
printf '%s\n' "$unsafe" | grep -Fqx \
	'state	unavailable	Persistent panel state is unsafe; using all-on defaults'
if run_helper set volume disabled >"$work/unsafe.out" 2>"$work/unsafe.err"; then
	printf 'Panel settings accepted an unsafe state file\n' >&2
	exit 1
fi
test -L "$state_file"

unsafe_config=$work/unsafe-config
unsafe_target=$work/unsafe-target
mkdir -p "$unsafe_config" "$unsafe_target"
ln -s "$unsafe_target" "$unsafe_config/dwm-titus"
unsafe_dir=$(HOME=$home XDG_CONFIG_HOME=$unsafe_config XDG_RUNTIME_DIR=$runtime "$helper" status)
printf '%s\n' "$unsafe_dir" | grep -Fqx \
	'state	unavailable	Persistent panel state directory is unsafe; using all-on defaults'

writable_config=$work/writable-config
mkdir -p "$writable_config/dwm-titus"
chmod 777 "$writable_config/dwm-titus"
writable_dir=$(HOME=$home XDG_CONFIG_HOME=$writable_config XDG_RUNTIME_DIR=$runtime "$helper" status)
printf '%s\n' "$writable_dir" | grep -Fqx \
	'state	unavailable	Persistent panel state directory is unsafe; using all-on defaults'
if HOME=$home XDG_CONFIG_HOME=$writable_config XDG_RUNTIME_DIR=$runtime \
	"$helper" set volume disabled >"$work/writable-dir.out" 2>"$work/writable-dir.err"; then
	printf 'Panel settings accepted a writable-by-others state directory\n' >&2
	exit 1
fi
test ! -e "$writable_config/dwm-titus/panel-widgets.conf"

grep -Fq 'function panelSettingsCommand(action, args)' "$commands"
grep -Fq 'readonly max_restore_attempts=8' "$helper"
grep -Fq 'while ((attempt < max_restore_attempts)); do' "$helper"
grep -Fq 'Give that edit one final guarded' "$helper"
grep -Fq "current_fingerprint == \"\$expected_fingerprint\"" "$helper"
grep -Fq 'panel-settings-protocol\t1\t0' "$model"
grep -Fq 'panel-settings-protocol\t1\t1' "$model"
grep -Fq 'function optionEnabled(id)' "$model"
grep -Fq 'function toggleOption(id)' "$model"
grep -Fq '{ "id": "clock-seconds", "label": "Clock: show seconds" }' "$model"
grep -Fq 'showSeconds: panelSettingsModel.optionEnabled("clock-seconds")' "$shell"
grep -Fq 'function panelOptionEnabled(option: string): bool' "$shell"
grep -Fq 'function panelOptionSet(option: string, enabled: bool): void' "$shell"
grep -Fq 'label: "Clock seconds"' "$control_window"
grep -Fq 'root.controlCenterModel.toggleOption("clock-seconds")' "$control_window"
grep -Fq 'root.panelSettingsModel.toggleOption(id)' "$control_model"
grep -Fq 'model: root.panelSettingsModel.options' "$appearance_pane"
grep -Fq 'onToggled: root.panelSettingsModel.toggleOption(panelOptionRow.modelData.id)' \
	"$appearance_pane"
grep -Fq 'Component.onCompleted: root.refresh()' "$model"
grep -Fq 'watchChanges: true' "$model"
grep -Fq 'property bool refreshPending: false' "$model"
grep -Fq 'property bool mutationRefreshPending: false' "$model"
grep -Fq 'root.mutationRefreshPending = true;' "$model"
grep -Fq '} else if (root.mutationRefreshPending) {' "$model"
grep -Fq 'function useDefaults()' "$model"
grep -Fq 'root.useDefaults();' "$model"
grep -Fq 'configuredConfigHome.startsWith("/")' "$model"
grep -Fq 'readonly property bool mutationReady:' "$model"
grep -Fq 'PanelSettingsModel {' "$shell"
test "$(grep -Fc 'PanelSettingsModel {' "$shell")" -eq 1
grep -Fq 'panelSettingsModel: panelSettingsModel' "$shell"
grep -Fq 'function panelWidgetEnabled(widget: string): bool' "$shell"
grep -Fq 'function panelWidgetSet(widget: string, enabled: bool): void' "$shell"
grep -Fq 'required property var panelSettingsModel' "$panel"
for widget in workspaces volume bluetooth network power keyboard-layout; do
	grep -Fq "root.panelSettingsModel.widgetEnabled(\"$widget\")" "$panel"
done
grep -Fq 'property var panelSettingsModel: null' "$control_model"
grep -Fq 'readonly property var widgetIds:' "$control_model"
grep -Fq '"Volume": "volume"' "$control_model"
test "$(grep -Fc 'const id = root.widgetIds[name];' "$control_model")" -eq 2
grep -Fq 'root.panelSettingsModel.widgetEnabled(id)' "$control_model"
grep -Fq 'root.panelSettingsModel.toggleWidget(id)' "$control_model"
grep -Fq 'enabled: !root.controlCenterModel.panelSettingsModel' "$control_window"
grep -Fq 'function pageMessage()' "$control_window"
grep -Fq 'return panelModel.providerDetail;' "$control_window"
grep -Fq 'if (panelModel.message.length > 0 && !panelModel.actionSucceeded)' "$control_window"
provider_detail_line=$(grep -nF 'return panelModel.providerDetail;' "$control_window" | cut -d: -f1)
action_message_line=$(grep -nF 'if (panelModel.message.length > 0) return panelModel.message;' \
	"$control_window" | cut -d: -f1)
test "$provider_detail_line" -lt "$action_message_line"
grep -Fq 'required property var panelSettingsModel' "$settings_window"
test "$(grep -Fc 'root.panelSettingsModel.refresh();' "$settings_model")" -eq 2
grep -Fq 'required property var panelSettingsModel' "$appearance_pane"
grep -Fq 'SectionLabel { label: "Panel widgets" }' "$appearance_pane"
grep -Fq 'root.panelSettingsModel.providerState !== "available"' "$appearance_pane"
grep -Fq '&& !root.panelSettingsModel.actionSucceeded' "$appearance_pane"
grep -Fq 'onToggled: root.panelSettingsModel.toggleWidget(panelWidgetRow.modelData.id)' \
	"$appearance_pane"

printf 'Quickshell panel settings persistence: PASS\n'
grep -Fq '"Keyboard layout": "keyboard-layout"' "$control_model"
grep -Fq 'model: ["Volume", "Bluetooth", "Network", "Power", "Keyboard layout", "Workspaces"]' "$control_window"
grep -Fq '{ "id": "keyboard-layout", "label": "Keyboard layout" }' "$model"
grep -Fq 'onSettingsSectionRequested: (panel, section) => root.runCommandMenuAction("settings", "select", section, panel.screen)' "$shell"
