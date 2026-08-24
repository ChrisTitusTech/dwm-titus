#!/bin/sh

set -eu

DWM_AUTOSTART_NO_INPUT_WATCH=1
export DWM_AUTOSTART_NO_INPUT_WATCH
TEST_REAL_UID=$(id -u)
export TEST_REAL_UID

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)

test_process_starttime() {
	pid=$1
	awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			if (fields[1] != "Z" && fields[20] ~ /^[0-9]+$/) {
				print fields[20]
			}
		}
	' "/proc/$pid/stat" 2>/dev/null
}

test_identity_matches() {
	identity=$1
	pid=${identity%%:*}
	starttime=${identity#*:}
	[ "$(stat -c %u "/proc/$pid" 2>/dev/null)" = "$TEST_REAL_UID" ] || return 1
	[ "$(test_process_starttime "$pid")" = "$starttime" ]
}

record_test_identity() {
	pid=$1
	identity_file=$2
	i=0
	while [ "$i" -lt 50 ]; do
		starttime=$(test_process_starttime "$pid")
		if [ -n "$starttime" ]; then
			printf '%s:%s\n' "$pid" "$starttime" >>"$identity_file"
			return 0
		fi
		i=$((i + 1))
		sleep 0.01
	done
	return 1
}

cleanup() {
	if [ -f "$work/watcher-fallback/state/watcher.pid" ]; then
		watcher_pid=$(cat "$work/watcher-fallback/state/watcher.pid")
		case $watcher_pid in
		'' | *[!0-9]*) ;;
		*) kill "$watcher_pid" 2>/dev/null || true ;;
		esac
	fi
	for identity_file in "$work"/*/state/dwm-status-runtime.identities; do
		[ -f "$identity_file" ] || continue
		while IFS= read -r runtime_identity; do
			test_identity_matches "$runtime_identity" || continue
			runtime_pid=${runtime_identity%%:*}
			kill -TERM "$runtime_pid" 2>/dev/null || true
		done <"$identity_file"
	done
	for identity_file in "$work"/*/state/quickshell-runtime.identities; do
		[ -f "$identity_file" ] || continue
		while IFS= read -r runtime_identity; do
			test_identity_matches "$runtime_identity" || continue
			runtime_pid=${runtime_identity%%:*}
			kill -TERM "$runtime_pid" 2>/dev/null || true
		done <"$identity_file"
	done
	sleep 0.05
	for identity_file in "$work"/*/state/dwm-status-runtime.identities; do
		[ -f "$identity_file" ] || continue
		while IFS= read -r runtime_identity; do
			test_identity_matches "$runtime_identity" || continue
			runtime_pid=${runtime_identity%%:*}
			kill -KILL "$runtime_pid" 2>/dev/null || true
		done <"$identity_file"
	done
	for identity_file in "$work"/*/state/quickshell-runtime.identities; do
		[ -f "$identity_file" ] || continue
		while IFS= read -r runtime_identity; do
			test_identity_matches "$runtime_identity" || continue
			runtime_pid=${runtime_identity%%:*}
			kill -KILL "$runtime_pid" 2>/dev/null || true
			wait "$runtime_pid" 2>/dev/null || true
		done <"$identity_file"
	done
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

make_mock_command() {
	name=$1
	cat >"$work/bin/$name" <<'EOF'
#!/bin/sh
name=$(basename "$0")
count_file="${TEST_STATE:?}/$name.count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
: >"${TEST_STATE:?}/$name.running"
EOF
	chmod +x "$work/bin/$name"
}

wait_for_marker() {
	marker=$1
	i=0
	while [ "$i" -lt 50 ]; do
		[ -f "$marker" ] && return 0
		i=$((i + 1))
		sleep 0.02
	done
	return 1
}

wait_for_quickshell_executable() {
	process_pid=$1
	i=0
	while [ "$i" -lt 50 ]; do
		executable=$(readlink "/proc/$process_pid/exe" 2>/dev/null || :)
		[ "${executable##*/}" = quickshell ] && return 0
		i=$((i + 1))
		sleep 0.01
	done
	return 1
}

mkdir -p "$work/bin" "$work/runtime-bin/normal" "$work/runtime-bin/stubborn"
cp "$(command -v sleep)" "$work/runtime-bin/normal/quickshell"
cp "$(command -v sleep)" "$work/runtime-bin/stubborn/quickshell"

cat >"$work/bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_REAL_UID:?}"
EOF

cat >"$work/bin/pgrep" <<'EOF'
#!/bin/sh
name=
while [ "$#" -gt 0 ]; do
	case $1 in
	-x)
		shift
		name=${1:-}
		break
		;;
	esac
	shift
done
[ -n "$name" ] || exit 1
if [ "$name" = quickshell ] && [ "${TEST_QUICKSHELL_PGREP_RACE:-0}" = 1 ]; then
	count_file="${TEST_STATE:?}/quickshell-pgrep-${TEST_AUTOSTART_ITERATION:?}.count"
	count=0
	[ ! -f "$count_file" ] || count=$(cat "$count_file")
	count=$((count + 1))
	printf '%s\n' "$count" >"$count_file"
	[ "$count" -ne 2 ] || exit 1
fi
if [ "$name" = quickshell ] && [ -f "${TEST_STATE:?}/quickshell.stale" ]; then
	exit 0
fi
test -f "${TEST_STATE:?}/$name.running"
EOF

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\t%s\n' "${XDG_CURRENT_DESKTOP:-}" "$*" >>"${TEST_STATE:?}/systemctl.log"
printf 'systemctl\t%s\n' "$*" >>"${TEST_STATE:?}/events.log"
case $* in
*"start wm-graphical-session.service"*)
	[ "${TEST_SYSTEMD_START_FAIL:-0}" != 1 ] || exit 1
	[ -f "${TEST_STATE:?}/quickshell-tray.ready" ] || exit 1
	;;
esac
exit 0
EOF

cat >"$work/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$work/bin/dbus-run-session" <<'EOF'
#!/bin/sh
if [ "$1" = "--" ]; then
	shift
fi
exec "$@"
EOF

cat >"$work/bin/xset" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$work/bin/setsid" <<'EOF'
#!/bin/sh
if [ "$1" = "-f" ]; then
	shift
fi
"$@" &
EOF

chmod +x "$work/bin/"*

cat >"$work/bin/chmod" <<'EOF'
#!/bin/sh
for argument do target=$argument; done
if [ -n "${TEST_CHMOD_FAILURE_TARGET:-}" ] && [ "$target" = "$TEST_CHMOD_FAILURE_TARGET" ]; then
	exit 1
fi
exec /usr/bin/chmod "$@"
EOF
/usr/bin/chmod +x "$work/bin/chmod"

for name in feh picom dwm-status dwm-lock-watch light-locker dex dex-autostart; do
	make_mock_command "$name"
done

# The production status publisher is a Bash script, so its comm is "bash"
# rather than "dwm-status". Keep a real shebang process alive to exercise the
# /proc command-path and DISPLAY guard instead of the old pgrep-name mock.
cat >"$work/bin/dwm-status" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

name=$(basename "$0")
count_file="${TEST_STATE:?}/$name.count"
count=0
[[ ! -f $count_file ]] || count=$(<"$count_file")
printf '%s\n' "$((count + 1))" >"$count_file"
: >"${TEST_STATE:?}/$name.running"
starttime=$(awk '
	{
		line = $0
		sub(/^.*\) /, "", line)
		split(line, fields, " ")
		print fields[20]
	}
' "/proc/$$/stat")
printf '%s:%s\n' "$$" "$starttime" >>"${TEST_STATE:?}/dwm-status-runtime.identities"
trap 'exit 0' HUP INT TERM
while :; do
	sleep 0.1
done
EOF
chmod +x "$work/bin/dwm-status"

cat >"$work/bin/quickshell" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_STATE:?}/quickshell.args"
if [ "${1:-}" = --version ]; then
	printf '%s\n' 'quickshell 0.3.0'
	exit 0
fi
managed_config=${XDG_CONFIG_HOME:?}/quickshell/shell.qml
selected_path=
selected_pid=
previous=
no_duplicate=0
for argument do
	if [ "$previous" = --path ]; then
		selected_path=$argument
	elif [ "$previous" = --pid ]; then
		selected_pid=$argument
	fi
	[ "$argument" != --no-duplicate ] || no_duplicate=1
	previous=$argument
done
if [ "${1:-}" = kill ]; then
	count_file="${TEST_STATE:?}/quickshell-kill.count"
	count=0
	[ ! -f "$count_file" ] || count=$(cat "$count_file")
	printf '%s\n' "$((count + 1))" >"$count_file"
	if [ -n "$selected_path" ] && [ "$selected_path" != "$managed_config" ]; then
		if [ -f "${TEST_STATE:?}/quickshell-secondary.pid" ]; then
			kill "$(cat "${TEST_STATE:?}/quickshell-secondary.pid")" 2>/dev/null || true
		fi
		rm -f "${TEST_STATE:?}/quickshell.stale" \
			"${TEST_STATE:?}/quickshell.running" \
			"${TEST_STATE:?}/quickshell-secondary.running"
		exit 0
	fi
	printf '%s\n' "$selected_pid" >>"${TEST_STATE:?}/quickshell-kill.pids"
	if [ -z "$selected_pid" ] && [ -f "${TEST_STATE:?}/quickshell-replacement.pid" ]; then
		kill "$(cat "${TEST_STATE:?}/quickshell-replacement.pid")" 2>/dev/null || true
		exit 0
	fi
	if [ -f "${TEST_STATE:?}/quickshell-replacement.pid" ] &&
		[ "$selected_pid" = "$(cat "${TEST_STATE:?}/quickshell-replacement.pid")" ]; then
		kill "$selected_pid" 2>/dev/null || true
		exit 0
	fi
	if [ "${TEST_QUICKSHELL_KILL_HANG:-0}" = 1 ]; then
		if [ -f "${TEST_STATE:?}/quickshell-replacement.pid" ] &&
			[ ! -e "${TEST_STATE:?}/quickshell-replacement.injected" ]; then
			cat "${TEST_STATE:?}/quickshell-replacement.pid" >>\
				"${TEST_STATE:?}/quickshell-managed.pids"
			: >"${TEST_STATE:?}/quickshell-replacement.injected"
		fi
		sleep 10
		exit 1
	fi
	if [ "${TEST_QUICKSHELL_DELAYED_STOP:-0}" = 1 ]; then
		(
			sleep 0.2
			kill -HUP "$selected_pid" 2>/dev/null || true
			rm -f "${TEST_STATE:?}/quickshell.stale" \
				"${TEST_STATE:?}/quickshell.running"
		) </dev/null >/dev/null 2>&1 &
	else
		rm -f "${TEST_STATE:?}/quickshell.stale" "${TEST_STATE:?}/quickshell.running"
	fi
	exit 0
fi
if [ "${1:-}" = list ]; then
	[ "$selected_path" = "$managed_config" ] || exit 2
	if [ -f "${TEST_STATE:?}/quickshell-managed.pids" ]; then
		count_file="${TEST_STATE:?}/quickshell-list.count"
		count=0
		[ ! -f "$count_file" ] || count=$(cat "$count_file")
		printf '%s\n' "$((count + 1))" >"$count_file"
		if [ -n "${TEST_QUICKSHELL_LIST_FAIL_AFTER:-}" ] &&
			[ "$count" -ge "$TEST_QUICKSHELL_LIST_FAIL_AFTER" ]; then
			exit 1
		fi
		separator=
		original_alive=0
		replacement_alive=0
		replacement_pid=
		[ ! -f "${TEST_STATE:?}/quickshell-replacement.pid" ] ||
			replacement_pid=$(cat "${TEST_STATE:?}/quickshell-replacement.pid")
		printf '['
		while IFS= read -r managed_pid; do
			state=$(awk '{ sub(/^.*\) /, ""); print $1 }' "/proc/$managed_pid/stat" 2>/dev/null || :)
			[ -n "$state" ] && [ "$state" != Z ] || continue
			if [ "$managed_pid" = "$replacement_pid" ]; then
				replacement_alive=1
			else
				original_alive=1
			fi
			printf '%s{"pid":%s}' "$separator" "$managed_pid"
			separator=,
		done <"${TEST_STATE:?}/quickshell-managed.pids"
		printf ']\n'
		if [ "$original_alive" -eq 0 ]; then
			rm -f "${TEST_STATE:?}/quickshell.stale"
			if [ "$replacement_alive" -eq 1 ]; then
				: >"${TEST_STATE:?}/quickshell.running"
				: >"${TEST_STATE:?}/quickshell-tray.ready"
				printf '%s\n' 1 >"${TEST_STATE:?}/quickshell.count"
			fi
		fi
		exit 0
	fi
	if [ -f "${TEST_STATE:?}/quickshell.stopping" ]; then
		count_file="${TEST_STATE:?}/quickshell-list.count"
		count=0
		[ ! -f "$count_file" ] || count=$(cat "$count_file")
		count=$((count + 1))
		printf '%s\n' "$count" >"$count_file"
		if [ "$count" -ge 3 ]; then
			rm -f "${TEST_STATE:?}/quickshell.stale" \
				"${TEST_STATE:?}/quickshell.running" \
				"${TEST_STATE:?}/quickshell.stopping"
		fi
	fi
	if [ -f "${TEST_STATE:?}/quickshell.stale" ] ||
		[ -f "${TEST_STATE:?}/quickshell.running" ]; then
		printf '%s\n' '[{"pid":1234}]'
	else
		printf '%s\n' '[]'
	fi
	exit 0
fi
if [ "${1:-}" = ipc ]; then
	printf '%s\n' ipc >>"${TEST_STATE:?}/events.log"
	[ "$selected_path" = "$managed_config" ] || exit 2
	if [ -f "${TEST_STATE:?}/quickshell-managed.pids" ] &&
		[ -f "${TEST_STATE:?}/quickshell-replacement.pid" ]; then
		replacement_pid=$(cat "${TEST_STATE:?}/quickshell-replacement.pid")
		original_alive=0
		while IFS= read -r managed_pid; do
			[ "$managed_pid" = "$replacement_pid" ] && continue
			kill -0 "$managed_pid" 2>/dev/null && original_alive=1
		done <"${TEST_STATE:?}/quickshell-managed.pids"
		if [ "$original_alive" -eq 0 ] && kill -0 "$replacement_pid" 2>/dev/null; then
			rm -f "${TEST_STATE:?}/quickshell.stale"
			: >"${TEST_STATE:?}/quickshell.running"
		fi
	fi
	if [ -f "${TEST_STATE:?}/quickshell.stale" ]; then
		sleep 10
		exit 1
	fi
	if [ -f "${TEST_STATE:?}/quickshell.hang" ]; then
		sleep 10
		exit 1
	fi
	[ -f "${TEST_STATE:?}/quickshell.running" ] || exit 1
	: >"${TEST_STATE:?}/quickshell-tray.ready"
	exit 0
fi

count_file="${TEST_STATE:?}/quickshell.count"
if [ -f "${TEST_STATE:?}/quickshell.running" ] && [ "$no_duplicate" -eq 1 ]; then
	exit 0
fi
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
: >"${TEST_STATE:?}/quickshell.running"
[ "${TEST_QUICKSHELL_LAUNCH_HANG:-0}" != 1 ] || : >"${TEST_STATE:?}/quickshell.hang"
EOF
chmod +x "$work/bin/quickshell"

run_duplicate_case() {
	mode=$1
	case_display=:99
	[ "$mode" != startx ] || case_display=:100
	home="$work/$mode/home"
	state="$work/$mode/state"
	runtime="$work/$mode/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"

	# Prevent this isolated test from starting a host polkit agent.
	: >"$state/polkit-mate-authentication-agent-1.running"

	for iteration in 1 2; do
		if [ "$mode" = startx ]; then
			XDG_RUNTIME_DIR="$runtime" dbus-run-session -- env \
				DISPLAY="$case_display" \
				HOME="$home" \
				QT_QPA_PLATFORM=wayland \
				TEST_STATE="$state" \
				PATH="$work/bin:/usr/bin:/bin" \
				WAYLAND_DISPLAY=wayland-0 \
				XDG_CONFIG_HOME="$home/.config" \
				XDG_SESSION_TYPE=wayland \
				DWM_AUTOSTART_NO_INPUT_WATCH=1 \
				TEST_AUTOSTART_ITERATION="$iteration" \
				TEST_QUICKSHELL_PGREP_RACE="$([ "$iteration" = 1 ] && printf 1 || printf 0)" \
				DWM_AUTOSTART_NO_SETSID=1 \
				sh "$repo_dir/scripts/autostart.sh"
		else
			DISPLAY="$case_display" \
				HOME=$home \
				QT_QPA_PLATFORM=wayland \
				TEST_STATE=$state \
				PATH="$work/bin:/usr/bin:/bin" \
				WAYLAND_DISPLAY=wayland-0 \
				XDG_CONFIG_HOME="$home/.config" \
				XDG_RUNTIME_DIR="$runtime" \
				XDG_SESSION_TYPE=wayland \
				DWM_AUTOSTART_NO_INPUT_WATCH=1 \
				TEST_AUTOSTART_ITERATION="$iteration" \
				TEST_QUICKSHELL_PGREP_RACE="$([ "$mode" = display-manager ] && [ "$iteration" = 1 ] && printf 1 || printf 0)" \
				DWM_AUTOSTART_NO_SETSID=1 \
				sh "$repo_dir/scripts/autostart.sh"
		fi
		wait_for_marker "$state/feh.running"
		wait_for_marker "$state/picom.running"
		wait_for_marker "$state/dwm-status.running"
		wait_for_marker "$state/dwm-lock-watch.running"
		if ! wait_for_marker "$state/quickshell.running"; then
			printf 'Quickshell launch arguments:\n' >&2
			cat "$state/quickshell.args" >&2
			return 1
		fi
	done

	test "$(cat "$state/feh.count")" -eq 2
	for name in picom dwm-status dwm-lock-watch quickshell; do
		test "$(cat "$state/$name.count")" -eq 1
	done
	test ! -e "$state/light-locker.count"
	test ! -e "$state/dex.count"
	test ! -e "$state/dex-autostart.count"
	awk '
		/--user import-environment/ && !imported { imported = NR }
		/--user start wm-graphical-session.service/ && !started { started = NR }
		END { exit !(imported && started && imported < started) }
	' "$state/systemctl.log"
	awk -F '\t' '
		index(":" $1 ":", ":X-DWM:") && index(":" $1 ":", ":dwm:") { found = 1 }
		END { exit !found }
	' "$state/systemctl.log"
}

run_wallpaper_recovery_with_existing_feh_case() {
	home="$work/wallpaper-recovery/home"
	state="$work/wallpaper-recovery/state"
	runtime="$work/wallpaper-recovery/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	: >"$state/feh.running"
	: >"$state/polkit-mate-authentication-agent-1.running"
	cat >"$work/bin/dwm-settings-wallpaper" <<'EOF'
#!/bin/sh
[ "$*" = session-apply ] || exit 2
: >"${TEST_STATE:?}/wallpaper-helper.running"
EOF
	chmod +x "$work/bin/dwm-settings-wallpaper"
	DISPLAY=:199 HOME=$home QT_QPA_PLATFORM=wayland TEST_STATE=$state \
		PATH="$work/bin:/usr/bin:/bin" WAYLAND_DISPLAY=wayland-0 \
		XDG_CONFIG_HOME="$home/.config" XDG_RUNTIME_DIR="$runtime" \
		XDG_SESSION_TYPE=wayland DWM_AUTOSTART_NO_INPUT_WATCH=1 \
		DWM_AUTOSTART_NO_SETSID=1 sh "$repo_dir/scripts/autostart.sh"
	wait_for_marker "$state/wallpaper-helper.running"
	test ! -e "$state/feh.count"
	rm -f "$work/bin/dwm-settings-wallpaper"
}

run_stale_quickshell_case() {
	home="$work/stale/home"
	state="$work/stale/state"
	runtime="$work/stale/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	: >"$state/quickshell.stale"
	: >"$state/polkit-mate-authentication-agent-1.running"
	identity_file="$state/quickshell-runtime.identities"
	: >"$identity_file"
	"$work/runtime-bin/normal/quickshell" 60 &
	managed_pid_one=$!
	record_test_identity "$managed_pid_one" "$identity_file"
	(
		trap '' TERM
		exec "$work/runtime-bin/stubborn/quickshell" 60
	) &
	managed_pid_two=$!
	record_test_identity "$managed_pid_two" "$identity_file"
	printf '%s\n%s\n' "$managed_pid_one" "$managed_pid_two" >"$state/quickshell-managed.pids"
	"$work/runtime-bin/normal/quickshell" 60 &
	secondary_pid=$!
	record_test_identity "$secondary_pid" "$identity_file"
	printf '%s\n' "$secondary_pid" >"$state/quickshell-secondary.pid"
	"$work/runtime-bin/normal/quickshell" 60 &
	replacement_pid=$!
	record_test_identity "$replacement_pid" "$identity_file"
	printf '%s\n' "$replacement_pid" >"$state/quickshell-replacement.pid"
	wait_for_quickshell_executable "$managed_pid_two"
	rm -f "$work/runtime-bin/stubborn/quickshell"

	DISPLAY=:99 \
		HOME=$home \
		TEST_STATE=$state \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" \
		XDG_RUNTIME_DIR="$runtime" \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 \
		DWM_AUTOSTART_NO_SETSID=1 \
		TEST_QUICKSHELL_KILL_HANG=1 \
		TEST_QUICKSHELL_LIST_FAIL_AFTER=1 \
		sh "$repo_dir/scripts/autostart.sh"

	wait "$managed_pid_one" 2>/dev/null || true
	wait "$managed_pid_two" 2>/dev/null || true
	test ! -e "$state/quickshell.stale"
	test -f "$state/quickshell.running"
	kill -0 "$secondary_pid"
	kill -0 "$replacement_pid"
	test -f "$state/quickshell-tray.ready"
	test "$(cat "$state/quickshell.count")" -eq 1
	test "$(cat "$state/quickshell-kill.count")" -eq 2
	grep -Fqx "$managed_pid_one" "$state/quickshell-kill.pids"
	grep -Fqx "$managed_pid_two" "$state/quickshell-kill.pids"
	if grep -Fqx "$replacement_pid" "$state/quickshell-kill.pids"; then
		printf '%s\n' 'Concurrent Quickshell replacement was selected for graceful shutdown' >&2
		exit 1
	fi
	test "$(cat "$state/quickshell-list.count")" -eq 1
	grep -Fq "kill --pid $managed_pid_one" "$state/quickshell.args"
	grep -Fq "kill --pid $managed_pid_two" "$state/quickshell.args"
	grep -Fq "list --path $home/.config/quickshell/shell.qml --json" "$state/quickshell.args"
	grep -Fq -- "--path $home/.config/quickshell/shell.qml --no-duplicate" "$state/quickshell.args"
	kill "$secondary_pid"
	wait "$secondary_pid" 2>/dev/null || true
	kill "$replacement_pid"
	wait "$replacement_pid" 2>/dev/null || true
	rm -f "$state/quickshell-managed.pids" \
		"$state/quickshell-secondary.pid" \
		"$state/quickshell-replacement.pid" \
		"$state/quickshell-replacement.injected" \
		"$state/quickshell-runtime.identities"
}

run_delayed_quickshell_case() {
	home="$work/delayed/home"
	state="$work/delayed/state"
	runtime="$work/delayed/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	: >"$state/quickshell.stale"
	: >"$state/polkit-mate-authentication-agent-1.running"
	identity_file="$state/quickshell-runtime.identities"
	: >"$identity_file"
	"$work/runtime-bin/normal/quickshell" 60 &
	managed_pid=$!
	record_test_identity "$managed_pid" "$identity_file"
	printf '%s\n' "$managed_pid" >"$state/quickshell-managed.pids"

	DISPLAY=:105 \
		HOME=$home \
		TEST_STATE=$state \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" \
		XDG_RUNTIME_DIR="$runtime" \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 \
		DWM_AUTOSTART_NO_SETSID=1 \
		TEST_QUICKSHELL_DELAYED_STOP=1 \
		sh "$repo_dir/scripts/autostart.sh"

	set +e
	wait "$managed_pid"
	wait_status=$?
	set -e
	# The fake graceful IPC path uses HUP after a delay, so 129 is expected.
	# TERM (143) or KILL (137) would mean autostart escalated prematurely.
	test "$wait_status" -eq 129
	test ! -e "$state/quickshell.stale"
	test -f "$state/quickshell.running"
	grep -Fq "kill --pid $managed_pid" "$state/quickshell.args"
	test "$(cat "$state/quickshell.count")" -eq 1
	rm -f "$state/quickshell-managed.pids" "$identity_file"
}

run_status_display_scope_case() {
	home="$work/status-display/home"
	state="$work/status-display/state"
	runtime="$work/status-display/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	: >"$state/polkit-mate-authentication-agent-1.running"

	expected_status_count=0
	for display in :101 :102 :101; do
		DISPLAY=$display \
			HOME=$home \
			TEST_STATE=$state \
			PATH="$work/bin:/usr/bin:/bin" \
			XDG_CONFIG_HOME="$home/.config" \
			XDG_RUNTIME_DIR="$runtime" \
			DWM_AUTOSTART_NO_INPUT_WATCH=1 \
			DWM_AUTOSTART_NO_SETSID=1 \
			sh "$repo_dir/scripts/autostart.sh"
		case $display in
		:101)
			[ "$expected_status_count" -ne 0 ] || expected_status_count=1
			;;
		:102) expected_status_count=2 ;;
		esac
		for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
			[ "$(wc -l <"$state/dwm-status-runtime.identities" 2>/dev/null || printf 0)" -eq "$expected_status_count" ] && break
			sleep 0.02
		done
		test "$(wc -l <"$state/dwm-status-runtime.identities")" -eq "$expected_status_count"
	done

	test "$(cat "$state/dwm-status.count")" -eq 2
	test "$(wc -l <"$state/dwm-status-runtime.identities")" -eq 2
	first_identity=$(sed -n '1p' "$state/dwm-status-runtime.identities")
	second_identity=$(sed -n '2p' "$state/dwm-status-runtime.identities")
	first_pid=${first_identity%%:*}
	second_pid=${second_identity%%:*}
	test_identity_matches "$first_identity"
	test_identity_matches "$second_identity"
	grep -Fqx bash "/proc/$first_pid/comm"
	grep -Fqx bash "/proc/$second_pid/comm"
	test ! -e "/proc/$first_pid/fd/9"
	test ! -e "/proc/$second_pid/fd/9"
	tr '\0' '\n' <"/proc/$first_pid/environ" | grep -Fqx 'DISPLAY=:101'
	tr '\0' '\n' <"/proc/$second_pid/environ" | grep -Fqx 'DISPLAY=:102'
}

run_status_optional_lock_case() {
	home="$work/status-lock/home"
	state="$work/status-lock/state"
	runtime="$work/status-lock/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$state" "$runtime"
	/usr/bin/chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$state/polkit-mate-authentication-agent-1.running"

	DISPLAY=:104 HOME=$home TEST_STATE=$state PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" XDG_RUNTIME_DIR=$runtime \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 DWM_AUTOSTART_NO_SETSID=1 \
		TEST_CHMOD_FAILURE_TARGET="$runtime/dwm-titus" \
		sh "$repo_dir/scripts/autostart.sh"
	wait_for_marker "$state/dwm-status.running"
	test "$(cat "$state/dwm-status.count")" -eq 1
	identity=$(cat "$state/dwm-status-runtime.identities")
	test_identity_matches "$identity"
	test ! -e "/proc/${identity%%:*}/fd/9"
}

run_status_empty_display_case() {
	home="$work/status-empty/home"
	state="$work/status-empty/state"
	runtime="$work/status-empty/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$state/polkit-mate-authentication-agent-1.running"
	DISPLAY='' HOME=$home TEST_STATE=$state PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" XDG_RUNTIME_DIR="$runtime" \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 \
		DWM_AUTOSTART_NO_SETSID=1 sh "$repo_dir/scripts/autostart.sh"
	test ! -e "$state/dwm-status.count"
}

run_status_launch_race_case() {
	home="$work/status-race/home"
	state="$work/status-race/state"
	runtime="$work/status-race/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$state/polkit-mate-authentication-agent-1.running"
	race_pids=

	for _invocation in 1 2; do
		DISPLAY=:103 \
			HOME=$home \
			TEST_STATE=$state \
			PATH="$work/bin:/usr/bin:/bin" \
			XDG_CONFIG_HOME="$home/.config" \
			XDG_RUNTIME_DIR=$runtime \
			DWM_AUTOSTART_NO_INPUT_WATCH=1 \
			DWM_AUTOSTART_NO_SETSID=1 \
			sh "$repo_dir/scripts/autostart.sh" &
		race_pid=$!
		race_pids="$race_pids $race_pid"
	done
	for race_pid in $race_pids; do
		wait "$race_pid"
	done
	wait_for_marker "$state/dwm-status.running"
	for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		[ "$(wc -l <"$state/dwm-status-runtime.identities" 2>/dev/null || printf 0)" -eq 1 ] && break
		sleep 0.02
	done
	test "$(wc -l <"$state/dwm-status-runtime.identities")" -eq 1
	sleep 0.1
	test "$(wc -l <"$state/dwm-status-runtime.identities")" -eq 1
}

run_hung_quickshell_case() {
	home="$work/hung/home"
	state="$work/hung/state"
	runtime="$work/hung/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	: >"$state/polkit-mate-authentication-agent-1.running"

	started=$(date +%s)
	DISPLAY=:99 \
		HOME=$home \
		TEST_STATE=$state \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" \
		XDG_RUNTIME_DIR="$runtime" \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 \
		DWM_AUTOSTART_NO_SETSID=1 \
		TEST_QUICKSHELL_LAUNCH_HANG=1 \
		sh "$repo_dir/scripts/autostart.sh"
	elapsed=$(($(date +%s) - started))

	test "$elapsed" -ge 5
	test "$elapsed" -le 10
	test "$(cat "$state/quickshell.count")" -eq 1
	test "$(grep -c '^ipc$' "$state/events.log")" -ge 4
	awk -F '\t' '
		$1 == "ipc" { ipc_count++ }
		$1 == "systemctl" && $2 ~ /start wm-graphical-session.service/ {
			start_after_ipc = ipc_count
		}
		END { exit !(start_after_ipc >= 4) }
	' "$state/events.log"
}

run_dex_fallback_case() {
	home="$work/fallback/home"
	state="$work/fallback/state"
	mkdir -p "$home" "$state"
	: >"$state/polkit-mate-authentication-agent-1.running"

	HOME=$home \
		TEST_STATE=$state \
		TEST_SYSTEMD_START_FAIL=1 \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" \
		DWM_AUTOSTART_NO_SETSID=1 \
		sh "$repo_dir/scripts/autostart.sh"

	test "$(cat "$state/dex.count")" -eq 1
	test ! -e "$state/dex-autostart.count"
}

run_missing_optional_case() {
	home="$work/missing/home"
	state="$work/missing/state"
	minimal_bin="$work/missing/bin"
	mkdir -p "$home" "$state" "$minimal_bin"

	for name in basename find grep id pgrep; do
		if [ -x "$work/bin/$name" ]; then
			ln -s "$work/bin/$name" "$minimal_bin/$name"
		else
			ln -s "$(command -v "$name")" "$minimal_bin/$name"
		fi
	done
	ln -s "$work/bin/dbus-update-activation-environment" \
		"$minimal_bin/dbus-update-activation-environment"
	: >"$state/polkit-mate-authentication-agent-1.running"

	HOME=$home \
		TEST_STATE=$state \
		PATH=$minimal_bin \
		XDG_CONFIG_HOME="$home/.config" \
		/bin/sh "$repo_dir/scripts/autostart.sh"
}

run_theme_resume_retry_case() {
	case_dir="$work/theme-resume-retry"
	home="$case_dir/home"
	state="$case_dir/state"
	minimal_bin="$case_dir/bin"
	mkdir -p "$case_dir/scripts" "$home" "$state" "$minimal_bin"
	cp "$repo_dir/scripts/autostart.sh" "$case_dir/scripts/autostart.sh"
	cat >"$case_dir/scripts/dwm-settings-theme" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"${TEST_STATE:?}/theme-resume.args.tmp"
mv -f "${TEST_STATE:?}/theme-resume.args.tmp" "${TEST_STATE:?}/theme-resume.args"
EOF
	cat >"$minimal_bin/timeout" <<'EOF'
#!/bin/sh
exit 124
EOF
	cat >"$minimal_bin/setsid" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"${TEST_STATE:?}/setsid.args.tmp"
mv -f "${TEST_STATE:?}/setsid.args.tmp" "${TEST_STATE:?}/setsid.args"
if [ "${1:-}" = -f ]; then
	shift
fi
"$@" &
EOF
	for name in basename find grep id mv pgrep; do
		if [ -x "$work/bin/$name" ]; then
			ln -s "$work/bin/$name" "$minimal_bin/$name"
		else
			ln -s "$(command -v "$name")" "$minimal_bin/$name"
		fi
	done
	ln -s "$work/bin/dbus-update-activation-environment" \
		"$minimal_bin/dbus-update-activation-environment"
	chmod +x "$case_dir/scripts/autostart.sh" "$case_dir/scripts/dwm-settings-theme" \
		"$minimal_bin/setsid" "$minimal_bin/timeout"
	: >"$state/polkit-mate-authentication-agent-1.running"

	HOME=$home \
		TEST_STATE=$state \
		PATH=$minimal_bin \
		XDG_CONFIG_HOME="$home/.config" \
		/bin/sh "$case_dir/scripts/autostart.sh"
	wait_for_marker "$state/theme-resume.args"
	grep -Fqx '_resume-preview' "$state/theme-resume.args"
	wait_for_marker "$state/setsid.args"
	grep -Fqx -- "-f $case_dir/scripts/dwm-settings-theme _resume-preview" "$state/setsid.args"
}

run_input_watcher_fallback_case() {
	case_dir="$work/watcher-fallback"
	home="$case_dir/home"
	state="$case_dir/state"
	mkdir -p "$case_dir/scripts" "$home" "$state"
	cp "$repo_dir/scripts/autostart.sh" "$case_dir/scripts/autostart.sh"
	cat >"$case_dir/scripts/dwm-settings-input" <<'EOF'
#!/bin/sh
case ${1:-} in
apply-saved) exit 0 ;;
watch-apply)
	printf '%s\n' "$$" >"${TEST_STATE:?}/watcher.pid"
	printf '%s\t%s\n' "${DWM_INPUT_SESSION_PID:-}" "${DWM_INPUT_SESSION_START:-}" \
		>"${TEST_STATE:?}/watcher.session"
	trap 'exit 0' HUP INT TERM
	while :; do sleep 10; done
	;;
*) exit 1 ;;
esac
EOF
	chmod +x "$case_dir/scripts/autostart.sh" "$case_dir/scripts/dwm-settings-input"
	: >"$state/polkit-mate-authentication-agent-1.running"

	DWM_AUTOSTART_NO_INPUT_WATCH=0 \
		DWM_AUTOSTART_NO_SETSID=1 \
		DWM_INPUT_SESSION_PID=$$ \
		HOME=$home \
		TEST_STATE=$state \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME="$home/.config" \
		timeout 10 sh "$case_dir/scripts/autostart.sh"
	wait_for_marker "$state/watcher.pid"
	wait_for_marker "$state/watcher.session"
	grep -Eq "^$$[[:space:]]+[1-9][0-9]*$" "$state/watcher.session"
}

run_duplicate_case display-manager
run_duplicate_case startx
run_wallpaper_recovery_with_existing_feh_case
run_status_display_scope_case
run_status_launch_race_case
run_status_optional_lock_case
run_status_empty_display_case
run_stale_quickshell_case
run_delayed_quickshell_case
run_hung_quickshell_case
run_dex_fallback_case
run_missing_optional_case
run_theme_resume_retry_case
run_input_watcher_fallback_case

if grep -q '^WantedBy=default.target$' \
	"$repo_dir/config/systemd/user/wm-graphical-session.service"; then
	printf '%s\n' "Graphical session service must not start before dwm imports DISPLAY" >&2
	exit 1
fi
if grep -q 'systemctl --user enable.*SERVICE_NAME' \
	"$repo_dir/scripts/xdg-enable-autostart.sh"; then
	printf '%s\n' "XDG setup must not enable the graphical session at early boot" >&2
	exit 1
fi
grep -Fq 'start_detached_display_command_once dwm-status' \
	"$repo_dir/scripts/autostart.sh"
grep -Fq 'display_process_script' "$repo_dir/scripts/autostart.sh"
grep -Fq 'display_process_display' "$repo_dir/scripts/autostart.sh"
grep -Fq 'timeout --signal=TERM --kill-after=2 5' "$repo_dir/scripts/autostart.sh"
grep -Fq '_resume-preview >/dev/null' "$repo_dir/scripts/autostart.sh"
# shellcheck disable=SC2016
grep -Fq '"$wallpaper_helper" session-apply >/dev/null 2>&1 ||' \
	"$repo_dir/scripts/autostart.sh"
# shellcheck disable=SC2016
grep -Fq 'feh --no-fehbg --randomize --bg-fill "$HOME/Pictures/backgrounds"' \
	"$repo_dir/scripts/autostart.sh"

printf '%s\n' "Autostart duplicate and missing-optional command guards: PASS"
