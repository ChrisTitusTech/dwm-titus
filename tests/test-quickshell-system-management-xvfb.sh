#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell xprop pgrep timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_SYSTEM_MANAGEMENT_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_SYSTEM_MANAGEMENT_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

test_tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
mkdir -p -- "$test_tmp_root"
work=$(mktemp -d "$test_tmp_root/dwm-system-management-xvfb.XXXXXX")
stop_process() {
	stop_pid=$1
	[ -n "$stop_pid" ] || return 0
	kill -TERM "$stop_pid" 2>/dev/null || true
	stop_i=0
	while kill -0 "$stop_pid" 2>/dev/null; do
		stop_state=$(ps -o stat= -p "$stop_pid" 2>/dev/null || true)
		case $stop_state in
		Z*) break ;;
		esac
		[ "$stop_i" -lt 50 ] || {
			kill -KILL "$stop_pid" 2>/dev/null || true
			break
		}
		stop_i=$((stop_i + 1))
		sleep 0.05
	done
	wait "$stop_pid" 2>/dev/null || true
}
cleanup() {
	cleanup_status=$?
	set +e
	stop_process "${quickshell_pid:-}"
	if [ -n "${helper:-}" ]; then
		for helper_pid in $(pgrep -f "$helper " 2>/dev/null || true); do
			stop_process "$helper_pid"
		done
	fi
	if [ -n "${discovery_helper:-}" ]; then
		for helper_pid in $(pgrep -f "$discovery_helper " 2>/dev/null || true); do
			stop_process "$helper_pid"
		done
	fi
	if [ -n "${update_action_helper:-}" ]; then
		for helper_pid in $(pgrep -f "$update_action_helper " 2>/dev/null || true); do
			stop_process "$helper_pid"
		done
	fi
	if [ -n "${update_ui_helper:-}" ]; then
		for helper_pid in $(pgrep -f "$update_ui_helper " 2>/dev/null || true); do
			stop_process "$helper_pid"
		done
	fi
	stop_process "${dwm_pid:-}"
	stop_process "${xvfb_pid:-}"
	if [ "$cleanup_status" -ne 0 ]; then
		if command -v strings >/dev/null 2>&1 && [ -d "${runtime:-}" ]; then
			find "$runtime" -type f -name 'log.qslog' -exec strings {} \; 2>/dev/null |
				tail -120 || true
		fi
	fi
	if [ "${DWM_KEEP_TEST_WORK:-0}" = 1 ]; then
		printf 'Preserved test workspace: %s\n' "$work" >&2
	else
		rm -rf -- "$work"
	fi
	exit "$cleanup_status"
}
trap cleanup EXIT HUP INT TERM

home=$work/home
runtime=$work/runtime
config_home=$home/.config
data_home=$home/.local/share
fixture=$work/fixture
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" \
	"$data_home/dwm-titus/scripts" "$runtime" "$fixture"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
cp "$repo/scripts/dwm-settings-provider" "$repo/scripts/dwm-quickshell-controlcenter" \
	"$repo/scripts/dwm-quickshell-controls" "$repo/scripts/dwm-quickshell-launcher" \
	"$repo/scripts/dwm-quickshell-network" "$repo/scripts/dwm-quickshell-pointer" \
	"$data_home/dwm-titus/scripts/"

helper=$data_home/dwm-titus/scripts/dwm-system-management
cat >"$helper" <<'HELPER'
#!/bin/sh
set -eu

fixture=${DWM_SYSTEM_MANAGEMENT_TEST_FIXTURE:?}
mode=$(sed -n '1p' "$fixture/mode")
case ${1:-} in
watch-updates)
	[ "$mode" != monitor-failure ] || exit 1
	printf '%s\n' "$$" >"$fixture/monitor-pid"
	exec /usr/bin/python3 -c 'import signal; print("update-event\tready", flush=True); signal.pause()' "$0" watch-updates
	;;
watch-operation | ack-operation)
	case ${2:-} in
	op-11111111111111111111111111111111) action=timezone-set; kind=timezone ;;
	op-22222222222222222222222222222222) action=updates-refresh; kind=refresh ;;
	op-33333333333333333333333333333333) action=locale-set; kind=locale ;;
	op-44444444444444444444444444444444) action=printers-open; kind=delegate ;;
	*) exit 3 ;;
	esac
	if [ "$1" = ack-operation ]; then
		: >"$fixture/ack-$2"
		exit 0
	fi
	printf 'system-management-protocol\t1\t0\n'
	printf 'operation\t%s\t%s\t%s\tpending\tunknown\tno\tRestoring operation\n' "$2" "$action" "$kind"
	printf 'operation\t%s\t%s\t%s\trunning\t50\tno\tObserving operation\n' "$2" "$action" "$kind"
	sleep 0.1
	: >"$fixture/finished-$2"
	printf 'operation\t%s\t%s\t%s\tsucceeded\t100\tno\tVerified fixture result\n' "$2" "$action" "$kind"
	printf 'audit\t%s\t%s\t%s\tsucceeded\t2026-09-05T12:00:00Z\t2026-09-05T12:01:00Z\tFixture result\n' "$2" "$action" "$kind"
	printf 'complete\toperation\n'
	exit 0
	;;
snapshot) ;;
*) exit 2 ;;
esac

snapshot() {
	printf '%b\n' \
		'system-management-protocol	1	0' \
		'snapshot-generation	aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
		'provider	updates	partial	delegated	PackageKit	Read-only update state' \
		'provider	recovery	available	user-session	dwm-system-management	Isolated journal recovery' \
		'state	update-summary	available	1	One update' \
		'state	update-last-refresh	available	10	Recently refreshed' \
		'state	update-restart	available	system	Restart required' \
		'action	updates-refresh	unavailable	delegated	updates	Refresh updates	Unavailable in fixture' \
		'action	updates-install-all	unavailable	delegated	updates	Install all updates	Unavailable in fixture' \
		'action	updates-cancel	unavailable	delegated	updates	Cancel update	No operation' \
		'update	alpha;1;x86_64;updates	security	installable	alpha	1	Security update' \
		'package-change	alpha;1;x86_64;updates	update	alpha	1	Security update' \
		'complete	snapshot'
}

case $mode in
valid | monitor-failure)
	snapshot
	;;
requested-install)
	snapshot | sed \
		-e 's/action\tupdates-install-all\tunavailable/action\tupdates-install-all\tavailable/' \
		-e 's/package-change\talpha;1;x86_64;updates\tupdate/package-change\talpha;1;x86_64;updates\tinstall/'
	;;
requested-remove)
	snapshot | sed \
		-e 's/action\tupdates-install-all\tunavailable/action\tupdates-install-all\tavailable/' \
		-e 's/package-change\talpha;1;x86_64;updates\tupdate/package-change\talpha;1;x86_64;updates\tremove/'
	;;
partial-restart)
	snapshot | sed 's/state\tupdate-restart\tavailable\tsystem/state\tupdate-restart\tpartial\tsecurity-session/'
	;;
cancelable-active)
	if [ -f "$fixture/ack-op-22222222222222222222222222222222" ]; then
		snapshot
	elif [ -f "$fixture/finished-op-22222222222222222222222222222222" ]; then
		snapshot | sed '/^complete\t/i\terminal-handoff\top-22222222222222222222222222222222\tupdates-refresh\trefresh'
	else
		snapshot | sed \
			-e 's/action\tupdates-cancel\tunavailable/action\tupdates-cancel\tavailable/' \
			-e '/^complete\t/i\active-operation\top-22222222222222222222222222222222\tupdates-refresh\trefresh\trunning\t45\tyes\tCancelable fixture'
	fi
	;;
regional-handoff)
	if [ -f "$fixture/ack-op-11111111111111111111111111111111" ]; then
		snapshot
	else
		snapshot | sed '/^complete\t/i\terminal-handoff\top-11111111111111111111111111111111\ttimezone-set\ttimezone'
	fi
	;;
regional-active | delegate-active)
	if [ "$mode" = regional-active ]; then
		operation=op-33333333333333333333333333333333
		action=locale-set
		kind=locale
	else
		operation=op-44444444444444444444444444444444
		action=printers-open
		kind=delegate
	fi
	if [ -f "$fixture/ack-$operation" ]; then
		snapshot
	elif [ -f "$fixture/finished-$operation" ]; then
		snapshot | sed "/^complete\t/i\terminal-handoff\t$operation\t$action\t$kind"
	else
		snapshot | sed "/^complete\t/i\active-operation\t$operation\t$action\t$kind\trunning\tunknown\tno\tNative fixture"
	fi
	;;
invalid-native-cancel)
	snapshot | sed '/^complete\t/i\active-operation\top-55555555555555555555555555555555\ttimezone-set\ttimezone\trunning\tunknown\tyes\tInvalid cancellation'
	;;
invalid-handoff)
	snapshot | sed '/^complete\t/i\terminal-handoff\top-11111111111111111111111111111111\ttimezone-set\tdelegate'
	;;
bad-plan)
	snapshot | sed \
		-e 's/action\tupdates-install-all\tunavailable/action\tupdates-install-all\tavailable/' \
		-e 's/package-change\talpha;1;x86_64;updates\tupdate\talpha\t1/package-change\tbeta;1;x86_64;updates\tinstall\tbeta\t1/'
	;;
unsafe-empty)
	snapshot | sed \
		-e 's/state\tupdate-summary\tavailable\t1/state\tupdate-summary\tavailable\t0/' \
		-e 's/action\tupdates-install-all\tunavailable/action\tupdates-install-all\tavailable/' \
		-e '/^update\t/d' -e '/^package-change\t/d'
	;;
unsafe-reinstall)
	snapshot | awk 'BEGIN { FS = OFS = "\t" }
		$1 == "action" && $2 == "updates-install-all" { $3 = "available" }
		$1 == "complete" { print "package-change", "beta;1;x86_64;updates", "reinstall", "beta", "1", "Reinstall" }
		{ print }'
	;;
future-record)
	snapshot | sed '/^complete\t/i\future-list-record\tfuture-value'
	;;
unexpected-update)
	snapshot | awk 'BEGIN { FS = OFS = "\t" }
		$1 == "action" && $2 == "updates-install-all" { $3 = "available" }
		$1 == "complete" { print "package-change", "beta;1;x86_64;updates", "update", "beta", "1", "Unexpected update" }
		{ print }'
	;;
unavailable-summary)
	snapshot | sed \
		-e 's/state\tupdate-summary\tavailable\t1/state\tupdate-summary\tpartial\tunknown/' \
		-e 's/action\tupdates-install-all\tunavailable/action\tupdates-install-all\tavailable/'
	;;
unsafe-cancel)
	snapshot | sed \
		's/action\tupdates-cancel\tunavailable/action\tupdates-cancel\tavailable/'
	;;
too-many-errors)
	snapshot | sed '/^complete\t/d'
	i=0
	while [ "$i" -le 4096 ]; do
		printf 'error\tupdates\tinternal\tRepeated diagnostic\n'
		i=$((i + 1))
	done
	printf 'complete\tsnapshot\n'
	;;
oversized)
	dd if=/dev/zero bs=1048576 count=9 2>/dev/null | tr '\0' x
	;;
noisy-stderr)
	snapshot
	dd if=/dev/zero bs=1048576 count=9 2>/dev/null | tr '\0' x >&2
	;;
fail-after-output)
	snapshot
	printf 'fixture failure after output\n' >&2
	exit 1
	;;
delay-once)
	count=0
	if [ -r "$fixture/count" ]; then
		IFS= read -r count <"$fixture/count" || count=0
	fi
	count=$((count + 1))
	printf '%s\n' "$count" >"$fixture/count"
	if [ "$count" -eq 1 ]; then
		printf '%s\n' "$$" >"$fixture/delayed-pid"
		exec sleep 30
	fi
	snapshot
	;;
*)
	exit 2
	;;
esac
HELPER
chmod 755 "$helper"
printf 'valid\n' >"$fixture/mode"

display_file=$work/display
Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$display_file" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ "$i" -lt 100 ]; do
	[ -s "$display_file" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -s "$display_file" ]
display_number=$(sed -n '1p' "$display_file")
case $display_number in
'' | *[!0-9]*)
	printf 'Xvfb returned an invalid display number\n' >&2
	exit 1
	;;
esac
display=:$display_number
i=0
while [ "$i" -lt 100 ]; do
	DISPLAY=$display xprop -root >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

# Exercise pane-scoped events and atomic dirty-cycle handoffs on a private bus.
mkdir -p "$work/discovery" "$work/discovery-data/dwm-titus/scripts" "$work/discovery-state"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/systemmanagement" "$work/discovery/"
cp "$repo/tests/qml/SystemDiscovery.qml" "$work/discovery/shell.qml"
discovery_helper=$work/discovery-data/dwm-titus/scripts/dwm-system-management
cp "$repo/tests/fixtures/system-discovery-provider.py" "$discovery_helper"
chmod +x "$discovery_helper"
for pipe_case in absent regular no-reader; do
	pipe_fixture=$work/discovery-pipe-$pipe_case
	mkdir -p "$pipe_fixture"
	case $pipe_case in
	regular) : >"$pipe_fixture/events" ;;
	no-reader) mkfifo "$pipe_fixture/events" ;;
	esac
	pipe_status=0
	timeout --kill-after=1s 2s env DWM_DISCOVERY_FIXTURE="$pipe_fixture" \
		"$discovery_helper" fixture-control events >"$pipe_fixture/log" 2>&1 || pipe_status=$?
	if [ "$pipe_status" -eq 0 ] || [ "$pipe_status" -eq 124 ] || [ "$pipe_status" -eq 137 ]; then
		printf 'Fixture event writer did not fail promptly for %s\n' "$pipe_case" >&2
		exit 1
	fi
	[ ! -s "$pipe_fixture/events" ]
	[ "$pipe_case" != absent ] || [ ! -e "$pipe_fixture/events" ]
done
printf 'Discovery fixture event-writer failure cases: PASS\n'
timeout --foreground --kill-after=2s 50s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/discovery-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_DISCOVERY_FIXTURE="$work/discovery-state" \
	quickshell --no-duplicate --path "$work/discovery/shell.qml" >"$work/discovery.log" 2>&1 &
quickshell_pid=$!
discovery_status=0
wait "$quickshell_pid" || discovery_status=$?
quickshell_pid=
if [ "$discovery_status" -ne 0 ] || ! grep -F 'Discovery native tests: PASS' "$work/discovery.log" ||
	grep -Fq 'Discovery FAILED:' "$work/discovery.log" || [ -e "$work/discovery-state/overlap" ] ||
	[ -e "$work/discovery-state/unmonitored-read" ]; then
	[ ! -e "$work/discovery-state/unmonitored-read" ] || printf 'Discovery snapshot preceded replacement readiness\n' >&2
	cat "$work/discovery.log" >&2
	exit 1
fi

# Run the isolated operation parser on the same nested display before loading
# the managed shell. This fixture never connects to host PackageKit.
mkdir -p "$work/update-ui" "$work/update-ui-data/dwm-titus/scripts" "$work/update-ui-state"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/settings" \
	"$repo/config/quickshell/systemmanagement" "$repo/config/quickshell/network" "$work/update-ui/"
cp "$repo/tests/qml/SystemUpdateUi.qml" "$work/update-ui/shell.qml"
update_ui_helper=$work/update-ui-data/dwm-titus/scripts/dwm-system-management
cp "$repo/tests/fixtures/system-update-ui-provider.py" "$update_ui_helper"
chmod +x "$update_ui_helper"
timeout --foreground --kill-after=2s 35s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/update-ui-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_UPDATE_UI_FIXTURE="$work/update-ui-state" \
	quickshell --no-duplicate --path "$work/update-ui/shell.qml" >"$work/update-ui.log" 2>&1 &
quickshell_pid=$!
ui_status=0
wait "$quickshell_pid" || ui_status=$?
quickshell_pid=
if [ "$ui_status" -ne 0 ] || ! grep -F 'Update UI native tests: PASS' "$work/update-ui.log" ||
	grep -Fq 'Update UI FAILED:' "$work/update-ui.log" ||
	[ "$(sed -n '1p' "$work/update-ui-state/origins" 2>/dev/null)" != 3 ] ||
	[ -e "$work/update-ui-state/invalid-arguments" ] || [ -e "$work/update-ui-state/overlap" ]; then
	cat "$work/update-ui.log" >&2
	exit 1
fi

mkdir -p "$work/operation-parser"
cp "$repo/tests/qml/SystemOperationParser.qml" "$work/operation-parser/shell.qml"
cp "$repo/config/quickshell/systemmanagement/SystemOperationProtocol.js" "$work/operation-parser/"
timeout --foreground --kill-after=2s 20s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	quickshell --no-duplicate --path "$work/operation-parser/shell.qml" \
	>"$work/operation-parser.log" 2>&1 &
quickshell_pid=$!
parser_status=0
wait "$quickshell_pid" || parser_status=$?
quickshell_pid=
if [ "$parser_status" -ne 0 ]; then
	cat "$work/operation-parser.log" >&2
	exit "$parser_status"
fi
if ! grep -F 'Operation parser native tests: PASS' "$work/operation-parser.log"; then
	cat "$work/operation-parser.log" >&2
	exit 1
fi

# Exercise the real root-owned Process lifecycle with a private fixed helper.
mkdir -p "$work/update-action" "$work/update-action-data/dwm-titus/scripts"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/systemmanagement" "$work/update-action/"
cp "$repo/tests/qml/SystemUpdateActionOwner.qml" "$work/update-action/shell.qml"
update_action_helper=$work/update-action-data/dwm-titus/scripts/dwm-system-management
cp "$repo/tests/fixtures/system-update-action-provider.py" "$update_action_helper"
chmod +x "$update_action_helper"
quickshell_binary=$(command -v quickshell)
assert_action_counter() {
	counter_name=$1
	counter_expected=$2
	counter_file=$action_state/$counter_name
	if [ "$counter_expected" = absent ]; then
		[ -e "$counter_file" ] || return 0
		counter_actual=present
	else
		counter_actual=$(sed -n '1p' "$counter_file" 2>/dev/null) || counter_actual=missing
		[ "$counter_actual" -eq "$counter_expected" ] 2>/dev/null && return 0
	fi
	printf 'Update action counter FAILED: %s / %s: expected %s, got %s\n' \
		"$action_scenario" "$counter_name" "$counter_expected" "$counter_actual" >&2
	cat "$action_state/log" >&2
	return 1
}
action_scenario=counter-diagnostic
action_state=$work/counter-diagnostic
mkdir -p "$action_state"
printf 'Scenario-specific counter fixture log\n' >"$action_state/log"
if assert_action_counter updates-refresh 1 >"$action_state/output" 2>&1; then
	printf 'Missing action counter was accepted\n' >&2
	exit 1
fi
grep -Fq 'counter-diagnostic / updates-refresh: expected 1, got missing' "$action_state/output"
grep -Fq 'Scenario-specific counter fixture log' "$action_state/output"
printf 'Update action counter diagnostics: PASS\n'
for action_scenario in refresh install rejected denied uncertain wrong-exit revoked \
	cancel-accepted cancel-race cancel-denied cancel-conflict cancel-output \
	cancel-error-overflow cancel-timeout cancel-recovery cancel-recovery-denied cancel-recovery-failure \
	cancel-uncertain-recover cancel-pending-snapshot failed-start; do
	action_state=$work/update-action-$action_scenario
	mkdir -p "$action_state"
	action_path=$PATH
	[ "$action_scenario" != failed-start ] || action_path=$work/no-executables
	timeout --foreground --kill-after=2s 20s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
		XDG_DATA_HOME="$work/update-action-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
		DWM_UPDATE_ACTION_FIXTURE="$action_state" DWM_UPDATE_ACTION_SCENARIO="$action_scenario" PATH="$action_path" \
		"$quickshell_binary" --no-duplicate --path "$work/update-action/shell.qml" \
		>"$action_state/log" 2>&1 &
	quickshell_pid=$!
	action_status=0
	wait "$quickshell_pid" || action_status=$?
	quickshell_pid=
	if [ "$action_status" -ne 0 ] || ! grep -F 'Update action owner native tests: PASS' "$action_state/log" ||
		grep -Fq 'Update action owner FAILED:' "$action_state/log" || [ -e "$action_state/invalid-arguments" ] ||
		[ -e "$action_state/control-overlap" ]; then
		cat "$action_state/log" >&2
		exit 1
	fi
	[ "$action_scenario" != failed-start ] || continue
	action_command=updates-refresh
	[ "$action_scenario" != install ] || action_command=updates-install-all
	assert_action_counter "$action_command" 1
	if [ "$action_scenario" = rejected ] || [ "$action_scenario" = cancel-recovery-failure ]; then
		assert_action_counter ack-operation absent
	else
		assert_action_counter ack-operation 1
	fi
	case $action_scenario in
	uncertain | wrong-exit | cancel-uncertain-recover) assert_action_counter watch-operation 1 ;;
	*) assert_action_counter watch-operation absent ;;
	esac
	case $action_scenario in
	cancel-*) assert_action_counter updates-cancel 1 ;;
	*) assert_action_counter updates-cancel absent ;;
	esac
done

mkdir -p "$work/operation-owner" "$work/owner-data/dwm-titus/scripts" "$work/owner-state"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/systemmanagement" "$work/operation-owner/"
cp "$repo/tests/qml/SystemOperationOwner.qml" "$work/operation-owner/shell.qml"
cp "$repo/tests/fixtures/system-operation-provider.py" "$work/owner-data/dwm-titus/scripts/dwm-system-management"
chmod +x "$work/owner-data/dwm-titus/scripts/dwm-system-management"
timeout --foreground --kill-after=2s 60s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OPERATION_FIXTURE="$work/owner-state" \
	quickshell --no-duplicate --path "$work/operation-owner/shell.qml" \
	>"$work/operation-owner.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-owner.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation owner native tests: PASS' "$work/operation-owner.log" || grep -Fq 'Operation owner FAILED:' "$work/operation-owner.log"; then
	cat "$work/operation-owner.log" >&2
	exit 1
fi
[ "$(sed -n '1p' "$work/owner-state/watch-operation-10")" -eq 2 ]
[ "$(sed -n '1p' "$work/owner-state/ack-operation-10")" -eq 1 ]
quickshell_binary=$(command -v quickshell)
timeout --foreground --kill-after=2s 15s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OWNER_FAILED_START=1 PATH="$work/no-executables" \
	"$quickshell_binary" --no-duplicate --path "$work/operation-owner/shell.qml" \
	>"$work/operation-owner-start-failure.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-owner-start-failure.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation owner native tests: PASS' "$work/operation-owner-start-failure.log" || grep -Fq 'Operation owner FAILED:' "$work/operation-owner-start-failure.log"; then
	cat "$work/operation-owner-start-failure.log" >&2
	exit 1
fi
timeout --foreground --kill-after=2s 15s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OPERATION_FIXTURE="$work/owner-state" DWM_OWNER_INCOMPLETE_RECOVERY=1 \
	"$quickshell_binary" --no-duplicate --path "$work/operation-owner/shell.qml" \
	>"$work/operation-owner-incomplete-recovery.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-owner-incomplete-recovery.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation owner native tests: PASS' "$work/operation-owner-incomplete-recovery.log" || grep -Fq 'Operation owner FAILED:' "$work/operation-owner-incomplete-recovery.log"; then
	cat "$work/operation-owner-incomplete-recovery.log" >&2
	exit 1
fi
[ "$(sed -n '1p' "$work/owner-state/incomplete-snapshots")" -eq 4 ]
timeout --foreground --kill-after=2s 15s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OPERATION_FIXTURE="$work/owner-state" DWM_OWNER_CLOSE_RETRY=1 \
	"$quickshell_binary" --no-duplicate --path "$work/operation-owner/shell.qml" \
	>"$work/operation-owner-close-retry.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-owner-close-retry.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation owner native tests: PASS' "$work/operation-owner-close-retry.log" || grep -Fq 'Operation owner FAILED:' "$work/operation-owner-close-retry.log"; then
	cat "$work/operation-owner-close-retry.log" >&2
	exit 1
fi
[ "$(sed -n '1p' "$work/owner-state/retry-snapshots")" -eq 3 ]
[ "$(sed -n '1p' "$work/owner-state/watch-operation-15")" -eq 2 ]
[ "$(sed -n '1p' "$work/owner-state/ack-operation-15")" -eq 1 ]
timeout --foreground --kill-after=2s 15s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OPERATION_FIXTURE="$work/owner-state" DWM_OWNER_DELAYED_SNAPSHOT=1 \
	"$quickshell_binary" --no-duplicate --path "$work/operation-owner/shell.qml" \
	>"$work/operation-owner-delayed-snapshot.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-owner-delayed-snapshot.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation owner native tests: PASS' "$work/operation-owner-delayed-snapshot.log" || grep -Fq 'Operation owner FAILED:' "$work/operation-owner-delayed-snapshot.log"; then
	cat "$work/operation-owner-delayed-snapshot.log" >&2
	exit 1
fi
[ "$(sed -n '1p' "$work/owner-state/delayed-snapshots")" -eq 3 ]
[ "$(sed -n '1p' "$work/owner-state/ack-operation-16")" -eq 1 ]
cp "$repo/tests/qml/SystemOperationHandoff.qml" "$work/operation-owner/handoff.qml"
timeout --foreground --kill-after=2s 10s env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$work/owner-data" XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORMTHEME= \
	DWM_OPERATION_FIXTURE="$work/owner-state" \
	"$quickshell_binary" --no-duplicate --path "$work/operation-owner/handoff.qml" \
	>"$work/operation-handoff.log" 2>&1 &
quickshell_pid=$!
owner_status=0
wait "$quickshell_pid" || owner_status=$?
quickshell_pid=
if [ "$owner_status" -ne 0 ]; then
	cat "$work/operation-handoff.log" >&2
	exit "$owner_status"
fi
if ! grep -F 'Operation handoff native tests: PASS' "$work/operation-handoff.log" || grep -Fq 'Operation handoff FAILED:' "$work/operation-handoff.log"; then
	cat "$work/operation-handoff.log" >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	DWM_SYSTEM_MANAGEMENT_TEST_FIXTURE="$fixture" QT_QPA_PLATFORMTHEME= \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!
config=$config_home/quickshell/shell.qml

ipc() {
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings "$@"
}

i=0
while [ "$i" -lt 200 ]; do
	ipc currentSection >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
ipc currentSection >/dev/null
ipc open >/dev/null
ipc select system >/dev/null

wait_state() {
	expected=$1
	i=0
	while [ "$i" -lt 200 ]; do
		if ! kill -0 "$quickshell_pid" 2>/dev/null; then
			printf 'Quickshell exited while waiting for system-management state\n' >&2
			wait "$quickshell_pid" || true
			quickshell_pid=
			return 1
		fi
		state=$(ipc systemManagementSnapshotState 2>/dev/null || true)
		if [ "$state" = "$expected" ]; then
			case $(ipc systemManagementDiscoveryStatus) in
			idle:* | blocked:*) return 0 ;;
			esac
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf 'System-management state did not become %s (mode=%s, state=%s, operation=%s)\n' \
		"$expected" "$(sed -n '1p' "$fixture/mode")" "$state" "$(ipc systemManagementOperationState 2>/dev/null || true)" >&2
	tail -60 "$work/quickshell.log" >&2
	return 1
}

wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(pgrep -f "$helper watch-updates")" = "$(sed -n '1p' "$fixture/monitor-pid")" ]

printf 'monitor-failure\n' >"$fixture/mode"
ipc close >/dev/null
ipc open >/dev/null
ipc select system >/dev/null
wait_state ready
[ "$(ipc systemManagementDiscoveryStatus)" = idle:failed ]
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
if [ -n "${DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR:-}" ]; then
	mkdir -p -- "$DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR"
	DISPLAY=$display import -window root "$DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR/discovery-unavailable.png"
fi

printf 'requested-install\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(ipc systemManagementPackageChangeCount)" -eq 1 ]
[ "$(ipc systemManagementInstallAvailability)" = available ]
[ -z "$(ipc systemManagementErrorCodes)" ]

printf 'requested-remove\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(ipc systemManagementPackageChangeCount)" -eq 0 ]
[ "$(ipc systemManagementInstallAvailability)" = unavailable ]

printf 'bad-plan\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]

printf 'unsafe-empty\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]

printf 'unsafe-reinstall\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(ipc systemManagementPackageChangeCount)" -eq 2 ]
[ "$(ipc systemManagementInstallAvailability)" = unavailable ]
[ "$(ipc systemManagementErrorCodes)" = unsupported ]

printf 'future-record\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]

printf 'partial-restart\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(ipc systemManagementRestartState)" = partial:security-session ]

printf 'regional-handoff\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc systemManagementOperationState)" = result ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc systemManagementOperationResult)" = timezone-set:succeeded ]
[ -f "$fixture/ack-op-11111111111111111111111111111111" ]
if [ -n "${DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR:-}" ]; then
	mkdir -p -- "$DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR"
	DISPLAY=$display import -window root "$DWM_SYSTEM_MANAGEMENT_CAPTURE_DIR/verified-operation.png"
fi

printf 'cancelable-active\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ -z "$(ipc systemManagementErrorCodes)" ]
i=0
while [ "$i" -lt 100 ]; do
	[ -f "$fixture/ack-op-22222222222222222222222222222222" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -f "$fixture/ack-op-22222222222222222222222222222222" ]

for native_mode in regional-active delegate-active; do
	if [ "$native_mode" = regional-active ]; then
		native_id=op-33333333333333333333333333333333
		native_result=locale-set:succeeded
	else
		native_id=op-44444444444444444444444444444444
		native_result=printers-open:succeeded
	fi
	printf '%s\n' "$native_mode" >"$fixture/mode"
	ipc refresh >/dev/null
	wait_state ready
	[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
	i=0
	while [ "$i" -lt 100 ]; do
		[ -f "$fixture/ack-$native_id" ] && break
		i=$((i + 1))
		sleep 0.05
	done
	[ -f "$fixture/ack-$native_id" ]
	[ "$(ipc systemManagementOperationResult)" = "$native_result" ]
done

printf 'invalid-native-cancel\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]

printf 'invalid-handoff\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]

printf 'unexpected-update\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementPackageChangeCount)" -eq 0 ]
[ "$(ipc systemManagementInstallAvailability)" = unavailable ]

printf 'unavailable-summary\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]
[ "$(ipc systemManagementInstallAvailability)" = missing ]

printf 'unsafe-cancel\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state partial
[ "$(ipc systemManagementInstallAvailability)" = missing ]

printf 'too-many-errors\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]

printf 'oversized\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]
if find "$runtime" -type f -name 'dwm-checked-command.*' -print -quit | grep -q .; then
	printf 'Bounded command capture left a temporary output file\n' >&2
	exit 1
fi

printf 'noisy-stderr\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
if find "$runtime" -type f -name 'dwm-checked-command*' -print -quit | grep -q .; then
	printf 'Bounded command capture left a temporary diagnostic file\n' >&2
	exit 1
fi

printf 'fail-after-output\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state failure
[ "$(ipc systemManagementUpdateCount)" -eq 0 ]

# Finish the preceding recovery before testing cancellation of a pane-only
# read. A replacement recovery snapshot must survive closure (tested above).
printf 'valid\n' >"$fixture/mode"
ipc refresh >/dev/null
wait_state ready
[ "$(ipc systemManagementOperationState)" = result ]

printf 'delay-once\n' >"$fixture/mode"
printf '0\n' >"$fixture/count"
ipc refresh >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ -s "$fixture/delayed-pid" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -s "$fixture/delayed-pid" ]
delayed_pid=$(sed -n '1p' "$fixture/delayed-pid")
kill -0 "$delayed_pid"
ipc select audio >/dev/null
ipc select system >/dev/null
wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]
[ "$(sed -n '1p' "$fixture/count")" -ge 2 ]
if kill -0 "$delayed_pid" 2>/dev/null; then
	printf 'System-management helper survived pane closure\n' >&2
	exit 1
fi

ipc close >/dev/null
if pgrep -af "$helper snapshot" >/dev/null 2>&1; then
	printf 'System-management helper remained after Settings closure\n' >&2
	exit 1
fi
if grep -E 'System(ManagementModel|SettingsPane)\.qml' "$work/quickshell.log" | grep -Fq 'ERROR'; then
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

printf 'Quickshell system-management Xvfb lifecycle: PASS\n'
