#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
	for pid_file in "$work"/daemon-state/pid.*; do
		[ -f "$pid_file" ] || continue
		kill -KILL "$(cat "$pid_file")" 2>/dev/null || true
	done
	[ -z "${zombie_mock_pid:-}" ] ||
		kill -KILL "$zombie_mock_pid" 2>/dev/null || true
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home/.config/flameshot" "$work/home/Pictures"

cat >"$work/home/flameshot-target.ini" <<'EOF'
[General]
showHelp=false

[Shortcuts]
TYPE_COPY=Ctrl+C
EOF
chmod 640 "$work/home/flameshot-target.ini"
ln -s "$work/home/flameshot-target.ini" \
	"$work/home/.config/flameshot/flameshot.ini"
config_inode=$(stat -Lc %i "$work/home/flameshot-target.ini")
config_mode=$(stat -Lc %a "$work/home/flameshot-target.ini")

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
printf 'dbus:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/flameshot" <<'EOF'
#!/bin/sh
printf 'flameshot:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/xdg-user-dir" <<EOF
#!/bin/sh
printf '%s\n' '$work/home/Pictures'
EOF

cat >"$work/bin/xrandr" <<'EOF'
#!/bin/sh
cat <<'MONITORS'
Monitors: 2
 0: +LEFT 1920/520x1080/290+0+0 LEFT
 1: +*RIGHT 2560/600x1440/340+1920+0 RIGHT
MONITORS
EOF

cat >"$work/bin/xdotool" <<'EOF'
#!/bin/sh
printf '%s\n' 'X=2400' 'Y=720' 'SCREEN=0' 'WINDOW=1'
EOF

chmod +x "$work/bin/"*

log=$work/calls.log
env -u XDG_CURRENT_DESKTOP -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XAUTHORITY="$work/Xauthority" \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/home/.config" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" clip

grep -Fqx 'systemctl:--user unset-environment WAYLAND_DISPLAY' "$log"
grep -Fqx 'systemctl:--user import-environment DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'dbus:WAYLAND_DISPLAY=' "$log"
grep -Fqx 'dbus:--systemd DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'flameshot:gui --clipboard' "$log"
grep -Fqx 'useJpgForClipboard=true' \
	"$work/home/.config/flameshot/flameshot.ini"
grep -Fqx 'useX11LegacyScreenshot=true' \
	"$work/home/.config/flameshot/flameshot.ini"
grep -Fqx 'showHelp=false' "$work/home/.config/flameshot/flameshot.ini"
grep -Fqx 'TYPE_COPY=Ctrl+C' "$work/home/.config/flameshot/flameshot.ini"
test -L "$work/home/.config/flameshot/flameshot.ini"
test "$(stat -Lc %i "$work/home/flameshot-target.ini")" = "$config_inode"
test "$(stat -Lc %a "$work/home/flameshot-target.ini")" = "$config_mode"
test -d "$work/home/Pictures/Screenshots"

: >"$log"
env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/home/.config" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" screen
grep -Fqx "flameshot:screen -n 1 -p $work/home/Pictures/Screenshots" "$log"

: >"$log"
env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/home/.config" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup
if grep -q '^flameshot:' "$log"; then
	printf '%s\n' "Flameshot setup must not start a capture" >&2
	exit 1
fi

mkdir -p "$work/explicit/.config/flameshot"
cat >"$work/explicit/.config/flameshot/flameshot.ini" <<'EOF'
[General]
useJpgForClipboard=true
useJpgForClipboard=false
useX11LegacyScreenshot=false
EOF
env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/explicit/.config" \
	HOME="$work/explicit" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup
grep -Fqx 'useX11LegacyScreenshot=false' \
	"$work/explicit/.config/flameshot/flameshot.ini" && {
	printf '%s\n' "Flameshot setup must replace a portal backend preference" >&2
	exit 1
}
grep -Fqx 'useX11LegacyScreenshot=true' \
	"$work/explicit/.config/flameshot/flameshot.ini"
grep -Fqx 'useJpgForClipboard=true' \
	"$work/explicit/.config/flameshot/flameshot.ini"
test "$(grep -Fxc 'useJpgForClipboard=true' \
	"$work/explicit/.config/flameshot/flameshot.ini")" -eq 1
if grep -Fq 'useJpgForClipboard=false' \
	"$work/explicit/.config/flameshot/flameshot.ini"; then
	printf '%s\n' "Flameshot setup must remove duplicate JPEG preferences" >&2
	exit 1
fi

failure_home=$work/failure
failure_bin=$work/failure-bin
mkdir -p "$failure_home/.config/flameshot" "$failure_bin"
cat >"$failure_home/flameshot-target.ini" <<'EOF'
[General]
showHelp=false

[Shortcuts]
TYPE_COPY=Ctrl+C
EOF
cp "$failure_home/flameshot-target.ini" \
	"$failure_home/flameshot-expected.ini"
ln -s "$failure_home/flameshot-target.ini" \
	"$failure_home/.config/flameshot/flameshot.ini"
failure_inode=$(stat -Lc %i "$failure_home/flameshot-target.ini")

cat >"$failure_bin/cat" <<'EOF'
#!/bin/sh
case ${1:-} in
*.tmp.*)
	printf '%s\n' "partial update"
	exit 1
	;;
esac
exec /usr/bin/cat "$@"
EOF
chmod +x "$failure_bin/cat"

if env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$failure_home/.config" \
	HOME="$failure_home" \
	PATH="$failure_bin:$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup; then
	printf '%s\n' "Flameshot setup must report an in-place update failure" >&2
	exit 1
fi
cmp "$failure_home/flameshot-expected.ini" \
	"$failure_home/.config/flameshot/flameshot.ini"
test -L "$failure_home/.config/flameshot/flameshot.ini"
test "$(stat -Lc %i "$failure_home/flameshot-target.ini")" = "$failure_inode"

concurrent_bin=$work/concurrent-bin
concurrent_home=$work/concurrent-home
concurrent_state=$work/concurrent-state
mkdir -p "$concurrent_bin" "$concurrent_home/.config/flameshot" \
	"$concurrent_home/runtime" "$concurrent_state"
cat >"$concurrent_home/.config/flameshot/flameshot.ini" <<'EOF'
[General]
showHelp=false

[Shortcuts]
TYPE_COPY=Ctrl+C
EOF

cat >"$concurrent_bin/cat" <<'EOF'
#!/bin/sh
case ${1:-} in
*.tmp.*)
	if (
		set -C
		: >"${CONCURRENCY_STATE:?}/writer-entered"
	) 2>/dev/null; then
		while [ ! -f "${CONCURRENCY_STATE:?}/release-writer" ]; do
			sleep 0.01
		done
	else
		: >"${CONCURRENCY_STATE:?}/second-writer-entered"
	fi
	;;
esac
exec /usr/bin/cat "$@"
EOF
chmod +x "$concurrent_bin/cat"

env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$concurrent_home/.config" \
	XDG_RUNTIME_DIR="$concurrent_home/runtime" \
	HOME="$concurrent_home" \
	PATH="$concurrent_bin:$work/bin:/usr/bin:/bin" \
	CONCURRENCY_STATE="$concurrent_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup &
first_setup_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -f "$concurrent_state/writer-entered" ]; do
	i=$((i + 1))
	sleep 0.05
done
test -f "$concurrent_state/writer-entered"

env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$concurrent_home/.config" \
	XDG_RUNTIME_DIR="$concurrent_home/runtime" \
	HOME="$concurrent_home" \
	PATH="$concurrent_bin:$work/bin:/usr/bin:/bin" \
	CONCURRENCY_STATE="$concurrent_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup &
second_setup_pid=$!
sleep 0.2
test ! -e "$concurrent_state/second-writer-entered"
: >"$concurrent_state/release-writer"
wait "$first_setup_pid"
wait "$second_setup_pid"
test ! -e "$concurrent_state/second-writer-entered"
grep -Fqx 'useX11LegacyScreenshot=true' \
	"$concurrent_home/.config/flameshot/flameshot.ini"
grep -Fqx 'useJpgForClipboard=true' \
	"$concurrent_home/.config/flameshot/flameshot.ini"
grep -Fqx 'showHelp=false' \
	"$concurrent_home/.config/flameshot/flameshot.ini"
grep -Fqx 'TYPE_COPY=Ctrl+C' \
	"$concurrent_home/.config/flameshot/flameshot.ini"

daemon_bin=$work/daemon-bin
daemon_home=$work/daemon-home
daemon_state=$work/daemon-state
mkdir -p "$daemon_bin" "$daemon_home" "$daemon_state"

cat >"$daemon_bin/id" <<'EOF'
#!/bin/sh
printf '%s\n' 1000
EOF

cat >"$daemon_bin/flock" <<'EOF'
#!/bin/sh
exit 0
EOF

cat >"$daemon_bin/pgrep" <<'EOF'
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
test "$name" = flameshot
for pid_file in "${DAEMON_STATE:?}"/pid.*; do
	test -f "$pid_file" || continue
	pid=$(cat "$pid_file")
	if kill -0 "$pid" 2>/dev/null; then
		printf '%s\n' "$pid"
	else
		rm -f "$pid_file"
	fi
done
EOF

cat >"$daemon_bin/setsid" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-f" ]; then
	shift
fi
"$@" &
EOF

cat >"$daemon_bin/ps" <<'EOF'
#!/bin/sh
last=
for arg; do
	last=$arg
done
if [ -n "${TEST_ZOMBIE_PID:-}" ] && [ "$last" = "$TEST_ZOMBIE_PID" ]; then
	printf 'Z\n'
	exit 0
fi
exec /usr/bin/ps "$@"
EOF

cat >"$daemon_bin/flameshot" <<'EOF'
#!/bin/sh
pid_file="${DAEMON_STATE:?}/pid.$$"
cleanup() {
	rm -f "$pid_file"
}
if [ "${TEST_IGNORE_TERM:-0}" = 1 ]; then
	trap '' TERM
else
	trap 'cleanup; exit 0' TERM INT
fi
trap cleanup EXIT

count=0
test ! -f "${DAEMON_STATE:?}/count" ||
count=$(cat "${DAEMON_STATE:?}/count")
count=$((count + 1))
printf '%s\n' "$count" >"${DAEMON_STATE:?}/count"
printf 'daemon-env:%s:%s:%s:%s:%s\n' \
	"${DISPLAY-unset}" \
	"${WAYLAND_DISPLAY-unset}" \
	"${XDG_SESSION_TYPE-unset}" \
	"${QT_QPA_PLATFORM-unset}" \
	"${DBUS_SESSION_BUS_ADDRESS-unset}" >>"${TEST_LOG:?}"
for descriptor in /proc/$$/fd/*; do
	case $(readlink "$descriptor" 2>/dev/null || true) in
	*/flameshot.lock)
		printf 'inherited-lock:%s\n' "$descriptor" >>"${TEST_LOG:?}"
		;;
	esac
done
printf '%s\n' "$$" >"$pid_file"
while :; do
	sleep 0.1
done
EOF
chmod +x "$daemon_bin/"*

: >"$log"
test_bus=${DBUS_SESSION_BUS_ADDRESS-unset}
DISPLAY=:98 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" daemon

test "$(cat "$daemon_state/count")" -eq 1
grep -Fqx "daemon-env::98:unset:x11:xcb:$test_bus" "$log"

DISPLAY=:99 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" daemon
test "$(cat "$daemon_state/count")" -eq 2
grep -Fqx "daemon-env::99:unset:x11:xcb:$test_bus" "$log"
test "$(find "$daemon_state" -name 'pid.*' -type f | wc -l)" -eq 1

DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" daemon
test "$(cat "$daemon_state/count")" -eq 2

DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" restart-daemon
test "$(cat "$daemon_state/count")" -eq 3
test "$(find "$daemon_state" -name 'pid.*' -type f | wc -l)" -eq 1
if grep -q '^inherited-lock:' "$log"; then
	printf '%s\n' "Flameshot daemon inherited the serialization lock" >&2
	exit 1
fi

for pid_file in "$daemon_state"/pid.*; do
	[ -f "$pid_file" ] || continue
	daemon_pid=$(cat "$pid_file")
	kill "$daemon_pid"
	wait "$daemon_pid" 2>/dev/null || true
done

DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	QT_QPA_PLATFORM=xcb \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	TEST_IGNORE_TERM=1 \
	"$daemon_bin/flameshot" &
zombie_mock_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -f "$daemon_state/pid.$zombie_mock_pid" ]; do
	i=$((i + 1))
	sleep 0.05
done
test -f "$daemon_state/pid.$zombie_mock_pid"

DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	TEST_ZOMBIE_PID="$zombie_mock_pid" \
	"$repo_dir/scripts/dwm-screenshot" daemon
test "$(cat "$daemon_state/count")" -eq 5
test -f "$daemon_state/pid.$zombie_mock_pid"
kill -KILL "$zombie_mock_pid"
wait "$zombie_mock_pid" 2>/dev/null || true
rm -f "$daemon_state/pid.$zombie_mock_pid"
zombie_mock_pid=

replacement_bus="unix:path=$work/replacement-bus"
DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	DBUS_SESSION_BUS_ADDRESS="$replacement_bus" \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" daemon
test "$(cat "$daemon_state/count")" -eq 6
grep -Fqx "daemon-env::99:unset:x11:xcb:$replacement_bus" "$log"

DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	DBUS_SESSION_BUS_ADDRESS="$replacement_bus" \
	XDG_CONFIG_HOME="$daemon_home/.config" \
	XDG_RUNTIME_DIR="$daemon_home/runtime" \
	HOME="$daemon_home" \
	PATH="$daemon_bin:$work/bin:/usr/bin:/bin" \
	DAEMON_STATE="$daemon_state" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" daemon
test "$(cat "$daemon_state/count")" -eq 6

theme_bin=$work/theme-bin
theme_home=$work/theme-home
mkdir -p "$theme_bin" "$theme_home/.config/dwm-titus"
cp "$repo_dir/config/themes.toml" \
	"$theme_home/.config/dwm-titus/themes.toml"

cat >"$theme_bin/pgrep" <<'EOF'
#!/bin/sh
test "$1" = "-u" && test "$3" = "-x" && test "$4" = "flameshot"
EOF

cat >"$theme_bin/dwm-screenshot" <<'EOF'
#!/bin/sh
printf 'dwm-screenshot:%s:%s\n' \
	"$*" "${QT_QPA_PLATFORMTHEME-unset}" >>"${TEST_LOG:?}"
test "${TEST_SETUP_FAIL:-0}" != "1"
EOF

for command_name in dbus-update-activation-environment gsettings qt6ct \
	systemctl xfconf-query xrdb; do
	cat >"$theme_bin/$command_name" <<'EOF'
#!/bin/sh
:
EOF
done
chmod +x "$theme_bin/"*

: >"$log"
DISPLAY=:99 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$theme_home/.config" \
	HOME="$theme_home" \
	PATH="$theme_bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/theme-apply.sh"

grep -Fqx 'dwm-screenshot:restart-daemon:qt6ct' "$log"

: >"$log"
DISPLAY=:99 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$theme_home/.config" \
	HOME="$theme_home" \
	PATH="$theme_bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	TEST_SETUP_FAIL=1 \
	"$repo_dir/scripts/theme-apply.sh" 2>/dev/null

grep -Fqx 'dwm-screenshot:restart-daemon:qt6ct' "$log"

printf '%s\n' "Flameshot X11 backend, environment, and clipboard command: PASS"
