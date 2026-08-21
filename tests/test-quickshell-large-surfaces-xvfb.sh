#!/bin/sh
set -eu

test_repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
repo=${DWM_LARGE_SURFACE_REPO:-$test_repo}

for command_name in Xvfb dbus-run-session dbus-send quickshell xdotool xprop getconf; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_LARGE_SURFACE_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_LARGE_SURFACE_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 300) + 1100))"
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
bin=$work/bin
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" "$home/.cache" \
	"$data_home/dwm-titus/scripts" "$data_home/applications" "$runtime" "$bin"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
cp "$repo/scripts/dwm-settings-provider" "$repo/scripts/dwm-system-health" \
	"$repo/scripts/dwm-settings-display" "$repo/scripts/dwm-settings-input" \
	"$repo/scripts/dwm-display-setup" "$repo/scripts/dwm-quickshell-controlcenter" \
	"$repo/scripts/dwm-quickshell-controls" "$repo/scripts/dwm-quickshell-network" \
	"$repo/scripts/dwm-quickshell-launcher" "$repo/scripts/dwm-diagnostics" \
	"$repo/scripts/dwm-lock" "$data_home/dwm-titus/scripts/"

cat >"$data_home/applications/dwm-large-surface-test.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Nested Surface Test
GenericName=Validation App
Comment=Launcher pointer and keyboard fixture
Exec=nested-surface-test
Icon=utilities-terminal
Categories=Utility;
DESKTOP

cat >"$bin/dex" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >>"$DWM_LARGE_SURFACE_DEX_LOG"
SH
chmod +x "$bin/dex"

Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!

i=0
while [ "$i" -lt 100 ]; do
	DISPLAY=$display xprop -root >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_AUTOSTART_NO_INPUT_WATCH=1 \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$runtime" \
	QSG_RHI_BACKEND=software QT_QUICK_BACKEND=software \
	DWM_LARGE_SURFACE_DEX_LOG="$work/dex.log" PATH="$bin:$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!
config=$config_home/quickshell/shell.qml

ipc() {
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_CACHE_HOME=$home/.cache \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call "$@"
}

wait_window() {
	pattern=$1
	i=0
	while [ "$i" -lt 200 ]; do
		window=$(DISPLAY=$display xdotool search --onlyvisible --name "$pattern" 2>/dev/null | head -1 || true)
		[ -n "$window" ] && {
			printf '%s\n' "$window"
			return 0
		}
		i=$((i + 1))
		sleep 0.05
	done
	return 1
}

capture_window() {
	name=$1
	window_id=$2
	evidence_dir=${DWM_LARGE_SURFACE_EVIDENCE_DIR:-}
	[ -n "$evidence_dir" ] || return 0
	mkdir -p "$evidence_dir"
	if command -v maim >/dev/null 2>&1; then
		DISPLAY=$display maim -i "$window_id" "$evidence_dir/$name.png"
	fi
	DISPLAY=$display xdotool getwindowgeometry --shell "$window_id" >"$evidence_dir/$name.geometry"
	DISPLAY=$display xprop -id "$window_id" >"$evidence_dir/$name.xprop"
}

capture_root() {
	name=$1
	evidence_dir=${DWM_LARGE_SURFACE_EVIDENCE_DIR:-}
	[ -n "$evidence_dir" ] || return 0
	command -v maim >/dev/null 2>&1 || return 0
	mkdir -p "$evidence_dir"
	DISPLAY=$display maim -u "$evidence_dir/$name.png"
}

send_test_notification() {
	if [ "${DWM_LARGE_SURFACE_FORCE_DBUS_SEND:-0}" != 1 ] &&
		command -v notify-send >/dev/null 2>&1; then
		DISPLAY=$display HOME=$home XDG_CACHE_HOME=$home/.cache XDG_RUNTIME_DIR=$runtime notify-send \
			--app-name='Large Surface Test' 'Nested notification' 'Pointer dismissal and history fixture'
		return
	fi

	DISPLAY=$display HOME=$home XDG_CACHE_HOME=$home/.cache XDG_RUNTIME_DIR=$runtime \
		dbus-send --session --print-reply --dest=org.freedesktop.Notifications \
		/org/freedesktop/Notifications org.freedesktop.Notifications.Notify \
		string:'Large Surface Test' uint32:0 string:'' string:'Nested notification' \
		string:'Pointer dismissal and history fixture' array:string: dict:string:variant: int32:6000 >/dev/null
}

i=0
while [ "$i" -lt 200 ]; do
	ipc launcher open >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
launcher_window=$(wait_window '^dwm launcher$')
capture_window launcher "$launcher_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc launcher close >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$launcher_window"
	DISPLAY=$display xdotool type --delay 20 'Nested Surface Test'
	sleep 0.1
	DISPLAY=$display xdotool mousemove --window "$launcher_window" 380 250 click 1
	i=0
	while [ "$i" -lt 100 ]; do
		[ -s "$work/dex.log" ] && break
		i=$((i + 1))
		sleep 0.05
	done
	grep -Fqx "$data_home/applications/dwm-large-surface-test.desktop" "$work/dex.log"

	ipc launcher open >/dev/null
	launcher_window=$(wait_window '^dwm launcher$')
	DISPLAY=$display xdotool windowactivate --sync "$launcher_window"
	DISPLAY=$display xdotool type --delay 20 'Nested Surface Test'
	DISPLAY=$display xdotool key Return
	i=0
	while [ "$i" -lt 100 ]; do
		if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm launcher$' >/dev/null 2>&1; then break; fi
		i=$((i + 1))
		sleep 0.05
	done
	[ "$(ipc launcher applicationConsumers)" = 0 ]
fi

ipc settings open >/dev/null
settings_window=$(wait_window '^dwm settings$')
capture_window settings "$settings_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc settings close >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$settings_window"
	DISPLAY=$display xdotool key Down
	[ "$(ipc settings currentSection)" = input ]
	DISPLAY=$display xdotool key Escape
fi

ipc systemhealth open >/dev/null
health_window=$(wait_window '^dwm system health$')
DISPLAY=$display xprop -id "$health_window" _NET_WM_STATE | grep -q '_NET_WM_STATE_FULLSCREEN'
capture_window system-health "$health_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc systemhealth close >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$health_window"
	DISPLAY=$display xdotool key Escape
fi

send_test_notification
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications count)" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications count)" -gt 0 ]
capture_root notification-popup
ipc notifications openHistory >/dev/null
history_window=$(wait_window '^dwm notification history$')
capture_window notification-history "$history_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc notifications closeHistory >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$history_window"
	DISPLAY=$display xdotool key Escape
fi
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm notification history$' >/dev/null 2>&1; then break; fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm notification history$' >/dev/null 2>&1; then
	printf 'Notification history did not close on Escape\n' >&2
	exit 1
fi
ipc notifications clear >/dev/null
[ "$(ipc notifications count)" = 0 ]

clock_ticks=$(getconf CLK_TCK)
before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
sleep 2
after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
cpu_percent=$(awk -v delta="$((after - before))" -v ticks="$clock_ticks" \
	'BEGIN { printf "%.2f", (delta * 100) / (ticks * 2) }')
awk -v cpu="$cpu_percent" 'BEGIN { exit !(cpu < 10.0) }'

if ! kill -0 "$dwm_pid" 2>/dev/null; then
	printf 'dwm exited before large-surface validation completed\n' >&2
	tail -40 "$work/dwm.log" >&2
	exit 1
fi
if ! kill -0 "$quickshell_pid" 2>/dev/null; then
	printf 'Quickshell exited before large-surface validation completed\n' >&2
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

printf 'Quickshell large surfaces Xvfb: PASS (%s%% closed CPU)\n' "$cpu_percent"
