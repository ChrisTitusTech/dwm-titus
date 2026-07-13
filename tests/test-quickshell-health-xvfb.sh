#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell xdotool xprop; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 400) + 300))"
cleanup() {
	set +e
	[ -n "${quickshell_pid:-}" ] && kill "$quickshell_pid" 2>/dev/null
	[ -n "${dwm_pid:-}" ] && kill "$dwm_pid" 2>/dev/null
	[ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

home=$work/home
runtime=$work/runtime
config_home=$home/.config
data_home=$home/.local/share
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" "$data_home/dwm-titus/scripts" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
# Simulate an existing preserved rule file. The generic control-center title
# rule must also cover the newly added utility window.
sed -i '/title="dwm control center utility"/d' "$config_home/dwm-titus/window-rules.toml"
cp "$repo/scripts/dwm-system-health" "$repo/scripts/dwm-diagnostics" \
	"$repo/scripts/dwm-quickshell-controlcenter" "$data_home/dwm-titus/scripts/"

Xvfb "$display" -screen 0 1024x768x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!

i=0
while [ "$i" -lt 100 ]; do
	if DISPLAY=$display xprop -root >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

config=$config_home/quickshell/shell.qml
i=0
while [ "$i" -lt 200 ]; do
	if DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call systemhealth open >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done

window=
i=0
while [ "$i" -lt 200 ]; do
	window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' 2>/dev/null | head -1 || true)
	[ -n "$window" ] && break
	i=$((i + 1))
	sleep 0.05
done

if [ -z "$window" ]; then
	printf 'System Health window did not open\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi

DISPLAY=$display xprop -id "$window" _NET_WM_STATE | grep -q '_NET_WM_STATE_FULLSCREEN'
geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window")
width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
[ "$width" = 1024 ]
[ "$height" = 768 ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call systemhealth close >/dev/null

i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' >/dev/null 2>&1; then
	printf 'System Health window did not close\n' >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter openKeybinds >/dev/null

window=
i=0
while [ "$i" -lt 200 ]; do
	window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' 2>/dev/null | head -1 || true)
	[ -n "$window" ] && break
	i=$((i + 1))
	sleep 0.05
done

if [ -z "$window" ]; then
	printf 'Control-center utility window did not open\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi

geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window")
width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
[ "$width" = 680 ]
[ "$height" = 500 ]

DISPLAY=$display xdotool windowactivate --sync "$window"
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' >/dev/null 2>&1; then
	printf 'Control-center utility window did not close\n' >&2
	exit 1
fi
kill -0 "$quickshell_pid"

ticks_before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
ticks_per_second=$(getconf CLK_TCK)
sleep 2
ticks_after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
if ! awk -v delta="$((ticks_after - ticks_before))" -v hz="$ticks_per_second" \
	'BEGIN { exit !((delta * 100 / (hz * 2)) <= 5) }'; then
	printf 'Quickshell exceeded 5%% CPU while the dashboard was closed\n' >&2
	exit 1
fi

printf 'Quickshell System Health Xvfb: PASS\n'
