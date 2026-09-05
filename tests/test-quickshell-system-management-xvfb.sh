#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell xprop pgrep; do
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
		for helper_pid in $(pgrep -f "$helper snapshot" 2>/dev/null || true); do
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

[ "${1:-}" = snapshot ] || exit 2
fixture=${DWM_SYSTEM_MANAGEMENT_TEST_FIXTURE:?}
mode=$(sed -n '1p' "$fixture/mode")

snapshot() {
	printf '%b\n' \
		'system-management-protocol	1	0' \
		'snapshot-generation	aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
		'provider	updates	partial	delegated	PackageKit	Read-only update state' \
		'provider	recovery	unsupported	user-session	dwm-system-management	Recovery unavailable' \
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
valid)
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
regional-handoff)
	snapshot | sed '/^complete\t/i\terminal-handoff\top-11111111111111111111111111111111\ttimezone-set\ttimezone'
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
		[ "$state" != "$expected" ] || return 0
		i=$((i + 1))
		sleep 0.05
	done
	printf 'System-management state did not become %s\n' "$expected" >&2
	tail -60 "$work/quickshell.log" >&2
	return 1
}

wait_state ready
[ "$(ipc systemManagementUpdateCount)" -eq 1 ]

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
