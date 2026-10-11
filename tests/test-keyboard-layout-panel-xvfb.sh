#!/bin/sh
# Panel side of keyboard layout switching on a private Xvfb: the built dwm,
# the repo dwm-quickshell-state watcher and the real DwmState and
# PanelSettingsModel QML (tests/qml/KeyboardLayoutPanel.qml), driven over IPC.
# Every X command is bound to the private display explicitly.

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

require_cmd() {
	for cmd; do
		if ! command -v "$cmd" >/dev/null 2>&1; then
			printf '%s\n' "missing required command: $cmd" >&2
			exit 77
		fi
	done
}

fail() {
	printf 'FAIL (step %s): %s\n' "${step:-setup}" "$*" >&2
	[ -f "$work/quickshell.log" ] && tail -n 30 "$work/quickshell.log" >&2
	exit 1
}

X() {
	DISPLAY=$display "$@"
}

session() {
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME="$home/.config" \
		XDG_DATA_HOME="$home/.local/share" XDG_RUNTIME_DIR=$runtime \
		PATH="$work/bin:$repo_dir/scripts:$PATH" QT_QPA_PLATFORMTHEME='' "$@"
}

# For background processes: exec, so $! is the program itself (the test
# stops and resumes dwm by PID).
spawn() {
	exec env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$home/.config" \
		XDG_DATA_HOME="$home/.local/share" XDG_RUNTIME_DIR="$runtime" \
		PATH="$work/bin:$repo_dir/scripts:$PATH" QT_QPA_PLATFORMTHEME='' "$@"
}

ipc() {
	session quickshell ipc --path "$work/shell/shell.qml" call kbdtest "$@" 2>/dev/null || true
}

wait_ipc() {
	expected=$1
	shift
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(ipc "$@")" = "$expected" ] && return 0
		i=$((i + 1))
		sleep 0.1
	done
	fail "kbdtest $* is '$(ipc "$@")', expected '$expected'"
}

wait_group() {
	i=0
	while [ "$i" -lt 100 ]; do
		value=$(X xprop -root _DWM_KEYBOARD_GROUP 2>/dev/null | sed -n 's/^[^=]*= //p')
		[ "$value" = "$1" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "_DWM_KEYBOARD_GROUP is '$value', expected '$1'"
}

require_cmd Xvfb xprop setxkbmap quickshell awk sed grep
[ -x "$repo_dir/dwm" ] || fail "build dwm first (make)"

tmp_root=${DWM_TEST_TMP_ROOT:-$HOME/tmp}
mkdir -p "$tmp_root"
work=$(mktemp -d "$tmp_root/dwm-keyboard-panel-xvfb.XXXXXX")
home="$work/home"
runtime="$work/runtime"
cleanup() {
	set +e
	for pid in ${quickshell_pid:-} ${dwm_pid:-} ${xvfb_pid:-}; do
		kill "$pid" 2>/dev/null
	done
	# Watchers and their xprop -spy children outlive their parents; sweep
	# everything that runs with this test's HOME.
	for dir in /proc/[0-9]*; do
		[ -r "$dir/environ" ] || continue
		{ tr '\0' '\n' <"$dir/environ"; } 2>/dev/null | grep -qx "HOME=$home" &&
			kill "${dir#/proc/}" 2>/dev/null
	done
	wait 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$home/.config/dwm-titus" "$home/.local/share/dwm-titus/config" "$runtime"
chmod 700 "$runtime"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/notify-send"
chmod 755 "$work/bin/notify-send"
# Count the layout requests the panel sends.
cat >"$work/bin/dwm-quickshell-state" <<EOF
#!/bin/sh
[ "\${1:-}" = keyboard-group ] && printf '%s\n' "\${2:-}" >>"$work/requests.log"
exec "$repo_dir/scripts/dwm-quickshell-state" "\$@"
EOF
chmod 755 "$work/bin/dwm-quickshell-state"
cp "$repo_dir/config/"*.toml "$home/.local/share/dwm-titus/config/"
cp "$repo_dir/config/themes.toml" "$repo_dir/config/window-rules.toml" "$home/.config/dwm-titus/"
printf 'keys = [\n]\n' >"$home/.config/dwm-titus/hotkeys.toml"
cp -a "$repo_dir/config/quickshell" "$work/shell"
cp "$repo_dir/tests/qml/KeyboardLayoutPanel.qml" "$work/shell/shell.qml"

exec 3>"$work/displayfd"
Xvfb -displayfd 3 -noreset -nolisten tcp -screen 0 1280x720x24 >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
exec 3>&-
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/displayfd" ]; do
	i=$((i + 1))
	sleep 0.05
done
[ -s "$work/displayfd" ] || fail "Xvfb did not report a display"
display=":$(head -n 1 "$work/displayfd")"
case $display in
:0) fail "refusing to run on :0" ;;
esac

X setxkbmap -layout us,gr -option ''
spawn "$repo_dir/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!
wait_group '0, 2'

spawn quickshell --no-duplicate --path "$work/shell/shell.qml" >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

step=parser
wait_ipc PASS parser

step=initial
wait_ipc '2:US' label
[ "$(ipc widget)" = on ] || fail "keyboard-layout widget not on by default"

step=click
ipc cycle 1 >/dev/null
wait_group '1, 2'
wait_ipc '2:GR' label

# Clicks while a request is still running are queued, not dropped: three
# steps from group 1 of 2 end on group 0.
step=burst
ipc burst 3 >/dev/null
wait_group '0, 2'
wait_ipc '2:US' label
sleep 0.5
wait_group '0, 2'

# dwm not taking requests (stopped): the running helper gives up after about
# a second and the two queued clicks are dropped, not sent. When dwm runs
# again it takes the one request that was written: exactly one step.
step=timeout
X "$repo_dir/scripts/dwm-quickshell-state" keyboard-group 0
wait_ipc '2:US' label
: >"$work/requests.log"
kill -STOP "$dwm_pid"
ipc burst 3 >/dev/null
sleep 4
sent=$(wc -l <"$work/requests.log")
kill -CONT "$dwm_pid"
[ "$sent" -eq 1 ] || fail "panel sent $sent requests while dwm was stopped, expected 1"
wait_group '1, 2'
sleep 1.5
wait_group '1, 2'
wait_ipc '2:GR' label
[ "$(wc -l <"$work/requests.log")" -eq 1 ] || fail "panel retried after the timeout"

step=select
ipc select 1 >/dev/null
wait_ipc '2:GR' label
ipc select 5 >/dev/null
sleep 0.3
wait_ipc '2:GR' label

step=keymap
# The locked group stays 1, which is now German.
X setxkbmap -layout us,de,gr -option ''
wait_ipc '3:DE' label
ipc cycle -1 >/dev/null
wait_ipc '3:US' label

step=single
X setxkbmap -layout us -option ''
wait_ipc '1:US' label

step=fallback
X setxkbmap -layout us,gr -option ''
wait_ipc '2:US' label
X xprop -root -remove _XKB_RULES_NAMES
X xprop -root -remove _DWM_KEYBOARD_SYMBOLS
wait_ipc '2:EN' label

step=widget
session "$repo_dir/scripts/dwm-panel-settings" set keyboard-layout disabled >/dev/null
wait_ipc off widget
session "$repo_dir/scripts/dwm-panel-settings" set keyboard-layout enabled >/dev/null
wait_ipc on widget

kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited"
kill -0 "$quickshell_pid" 2>/dev/null || fail "quickshell exited"
printf '%s\n' "Keyboard layout panel Xvfb test: PASS"
