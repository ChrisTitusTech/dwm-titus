#!/bin/sh

set -eu

DWM_AUTOSTART_NO_INPUT_WATCH=1
export DWM_AUTOSTART_NO_INPUT_WATCH

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
	if [ -f "$work/watcher-fallback/state/watcher.pid" ]; then
		watcher_pid=$(cat "$work/watcher-fallback/state/watcher.pid")
		case $watcher_pid in
		'' | *[!0-9]*) ;;
		*) kill "$watcher_pid" 2>/dev/null || true ;;
		esac
	fi
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
printf '%s\n' "$*" >"${TEST_STATE:?}/$name.args"
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

mkdir -p "$work/bin"

cat >"$work/bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 1000
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
test -f "${TEST_STATE:?}/$name.running"
EOF

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\t%s\n' "${XDG_CURRENT_DESKTOP:-}" "$*" >>"${TEST_STATE:?}/systemctl.log"
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

for name in feh picom dwm-status dwm-lock-watch light-locker dex dex-autostart; do
	make_mock_command "$name"
done

cat >"$work/bin/quickshell" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
	printf '%s\n' 'quickshell 0.3.0'
	exit 0
fi
if [ "${1:-}" = ipc ]; then
	test -f "${TEST_STATE:?}/quickshell.running"
	: >"${TEST_STATE:?}/quickshell-tray.ready"
	exit 0
fi

count_file="${TEST_STATE:?}/quickshell.count"
count=0
[ ! -f "$count_file" ] || count=$(cat "$count_file")
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
: >"${TEST_STATE:?}/quickshell.running"
EOF
chmod +x "$work/bin/quickshell"

run_duplicate_case() {
	mode=$1
	home="$work/$mode/home"
	state="$work/$mode/state"
	runtime="$work/$mode/runtime"
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/dwm-titus" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"
	if [ "$mode" = display-manager ]; then
		: >"$home/Pictures/selected-wallpaper.png"
		ln -s "$home/Pictures/selected-wallpaper.png" "$home/.config/dwm-titus/wallpaper"
	fi

	# Prevent this isolated test from starting a host polkit agent.
	: >"$state/polkit-mate-authentication-agent-1.running"

	for iteration in 1 2; do
		if [ "$mode" = startx ]; then
			XDG_RUNTIME_DIR="$runtime" dbus-run-session -- env \
				DISPLAY=:99 \
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
			DISPLAY=:99 \
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
		wait_for_marker "$state/quickshell.running"
	done

	for name in feh picom dwm-status dwm-lock-watch quickshell; do
		test "$(cat "$state/$name.count")" -eq 1
	done
	if [ "$mode" = display-manager ]; then
		grep -Fqx -- "--bg-scale $home/.config/dwm-titus/wallpaper" "$state/feh.args"
	else
		grep -Fqx -- "--randomize --bg-fill $home/Pictures/backgrounds" "$state/feh.args"
	fi
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
		timeout 5 sh "$case_dir/scripts/autostart.sh"
	wait_for_marker "$state/watcher.pid"
	wait_for_marker "$state/watcher.session"
	grep -Eq "^$$[[:space:]]+[1-9][0-9]*$" "$state/watcher.session"
}

run_duplicate_case display-manager
run_duplicate_case startx
run_dex_fallback_case
run_missing_optional_case
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

printf '%s\n' "Autostart duplicate and missing-optional command guards: PASS"
