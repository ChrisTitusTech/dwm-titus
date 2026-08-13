#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
	for pid_file in "$work"/*/state/flameshot.pid; do
		[ -f "$pid_file" ] || continue
		kill "$(cat "$pid_file")" 2>/dev/null || true
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
if [ "$name" = flameshot ]; then
	printf '%s|%s|%s\n' \
		"${XDG_SESSION_TYPE:-}" \
		"${QT_QPA_PLATFORM:-}" \
		"${WAYLAND_DISPLAY:-}" \
		>"${TEST_STATE:?}/flameshot.env"
	printf '%s\n' "$$" >"${TEST_STATE:?}/flameshot.pid"
	cleanup() {
		rm -f "${TEST_STATE:?}/flameshot.pid"
	}
	trap 'cleanup; exit 0' TERM INT
	trap cleanup EXIT
	while :; do
		sleep 1
	done
fi
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
if [ "$name" = flameshot ]; then
	test -f "${TEST_STATE:?}/flameshot.pid" || exit 1
	pid=$(cat "${TEST_STATE:?}/flameshot.pid")
	kill -0 "$pid" 2>/dev/null || exit 1
	printf '%s\n' "$pid"
	exit 0
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

for name in feh flameshot picom dwm-status dwm-lock-watch light-locker dex dex-autostart; do
	make_mock_command "$name"
done

cat >"$work/bin/quickshell" <<'EOF'
#!/bin/sh
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
	mkdir -p "$home/Pictures/backgrounds" "$home/.config/quickshell" "$state" "$runtime"
	chmod 700 "$runtime"
	: >"$home/Pictures/backgrounds/wallpaper"
	: >"$home/.config/quickshell/shell.qml"

	# Prevent this isolated test from starting a host polkit agent.
	: >"$state/polkit-mate-authentication-agent-1.running"

	for _ in 1 2; do
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
				DWM_AUTOSTART_NO_SETSID=1 \
				sh "$repo_dir/scripts/autostart.sh"
		fi
		wait_for_marker "$state/feh.running"
		wait_for_marker "$state/picom.running"
		wait_for_marker "$state/dwm-status.running"
		wait_for_marker "$state/dwm-lock-watch.running"
		wait_for_marker "$state/quickshell.running"
		wait_for_marker "$state/flameshot.running"
	done

	for name in feh flameshot picom dwm-lock-watch quickshell; do
		expected=1
		# Each startx fixture invocation has a fresh session bus, so the
		# surviving Flameshot daemon must be replaced for the second bus.
		if [ "$mode" = startx ] && [ "$name" = flameshot ]; then
			expected=2
		fi
		test "$(cat "$state/$name.count")" -eq "$expected"
	done
	grep -Fqx 'useX11LegacyScreenshot=true' \
		"$home/.config/flameshot/flameshot.ini"
	grep -Fqx 'useJpgForClipboard=true' \
		"$home/.config/flameshot/flameshot.ini"
	grep -Fqx 'x11|xcb|' "$state/flameshot.env"
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

run_flameshot_setup_failure_case() {
	home="$work/flameshot-failure/home"
	state="$work/flameshot-failure/state"
	config_path="$home/not-a-directory"
	mkdir -p "$home" "$state"
	: >"$config_path"
	: >"$state/polkit-mate-authentication-agent-1.running"

	DISPLAY=:99 \
		HOME=$home \
		TEST_STATE=$state \
		TEST_SYSTEMD_START_FAIL=1 \
		PATH="$work/bin:/usr/bin:/bin" \
		XDG_CONFIG_HOME=$config_path \
		XDG_RUNTIME_DIR="$work/flameshot-failure/runtime" \
		DWM_AUTOSTART_NO_SETSID=1 \
		sh "$repo_dir/scripts/autostart.sh" \
		2>"$state/autostart.err"

	test ! -e "$state/flameshot.count"
	grep -Fq "failed to configure Flameshot's X11 backend" \
		"$state/autostart.err"
}

run_duplicate_case display-manager
run_duplicate_case startx
run_dex_fallback_case
run_missing_optional_case
run_flameshot_setup_failure_case

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
