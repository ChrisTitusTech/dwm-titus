#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell xdotool xprop pgrep getconf; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_SETTINGS_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_SETTINGS_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 400) + 700))"
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
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" \
	"$data_home/dwm-titus/scripts" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
cp "$repo/scripts/dwm-settings-provider" "$repo/scripts/dwm-system-health" \
	"$repo/scripts/dwm-settings-display" "$repo/scripts/dwm-settings-input" \
	"$repo/scripts/dwm-display-setup" \
	"$repo/scripts/dwm-quickshell-controlcenter" "$repo/scripts/dwm-quickshell-controls" \
	"$repo/scripts/dwm-quickshell-network" "$repo/scripts/dwm-diagnostics" \
	"$repo/scripts/dwm-lock" "$data_home/dwm-titus/scripts/"

power_state=$work/power-state
mkdir -p "$power_state"
printf '1\n' >"$power_state/dpms-enabled"
printf '600\n' >"$power_state/dpms-timeout"
cat >"$data_home/dwm-titus/scripts/xset" <<'SH'
#!/bin/sh
set -eu
state=${DWM_SETTINGS_TEST_POWER_STATE:?}
case ${1:-} in
q)
	enabled=$(cat "$state/dpms-enabled")
	timeout=$(cat "$state/dpms-timeout")
	[ "$enabled" = 1 ] && label=Enabled || label=Disabled
	cat <<EOF
Screen Saver:
  timeout:  0    cycle:  600
DPMS (Display Power Management Signaling):
  Standby: $timeout    Suspend: $timeout    Off: $timeout
  DPMS is $label
EOF
	;;
+dpms)
	[ "${DWM_SETTINGS_TEST_DELAY_POWER:-0}" != 1 ] || sleep 1
	printf '1\n' >"$state/dpms-enabled"
	;;
-dpms)
	[ "${DWM_SETTINGS_TEST_DELAY_POWER:-0}" != 1 ] || sleep 1
	printf '0\n' >"$state/dpms-enabled"
	;;
dpms)
	printf '%s\n' "$4" >"$state/dpms-timeout"
	;;
s) ;;
*) exit 2 ;;
esac
SH
chmod +x "$data_home/dwm-titus/scripts/xset"

Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
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
	XDG_RUNTIME_DIR=$runtime DWM_AUTOSTART_NO_INPUT_WATCH=1 \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	DWM_SETTINGS_TEST_POWER_STATE="$power_state" DWM_SETTINGS_TEST_DELAY_POWER=1 \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

config=$config_home/quickshell/shell.qml
settings_power_watch_count() {
	watch_count=0
	for monitor_pid in $(pgrep -f '[d]bus-monitor --system.*org.freedesktop.UPower.*org.freedesktop.UPower.PowerProfiles.*org.freedesktop.login1' || true); do
		[ -r "/proc/$monitor_pid/status" ] || continue
		monitor_parent=$(awk '$1 == "PPid:" { print $2; exit }' "/proc/$monitor_pid/status")
		[ -n "$monitor_parent" ] && [ -r "/proc/$monitor_parent/cmdline" ] || continue
		if tr '\0' ' ' <"/proc/$monitor_parent/cmdline" |
			grep -Fq "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter power-watch"; then
			watch_count=$((watch_count + 1))
		fi
	done
	printf '%s\n' "$watch_count"
}

cpu_sample_seconds=${DWM_SETTINGS_POWER_CPU_SECONDS:-0}
case $cpu_sample_seconds in
'' | *[!0-9]*)
	printf 'Invalid power CPU sample duration: %s\n' "$cpu_sample_seconds" >&2
	exit 2
	;;
esac
if [ "$cpu_sample_seconds" -gt 0 ] && [ "$cpu_sample_seconds" -lt 30 ]; then
	printf 'Power CPU sample duration must be 0 or at least 30 seconds: %s\n' \
		"$cpu_sample_seconds" >&2
	exit 2
fi
i=0
while [ "$i" -lt 200 ]; do
	if DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings status >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done

clock_ticks=$(getconf CLK_TCK)
baseline_cpu_percent=
if [ "$cpu_sample_seconds" -gt 0 ]; then
	before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
	sleep "$cpu_sample_seconds"
	after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
	baseline_cpu_percent=$(awk -v delta="$((after - before))" -v ticks="$clock_ticks" \
		-v seconds="$cpu_sample_seconds" 'BEGIN { printf "%.3f", (delta * 100) / (ticks * seconds) }')
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings open >/dev/null

window=
i=0
while [ "$i" -lt 200 ]; do
	window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm settings$' 2>/dev/null | head -1 || true)
	[ -n "$window" ] && break
	i=$((i + 1))
	sleep 0.05
done

if [ -z "$window" ]; then
	printf 'Settings window did not open\n' >&2
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window")
width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
x=$(printf '%s\n' "$geometry" | awk -F= '$1 == "X" { print $2 }')
y=$(printf '%s\n' "$geometry" | awk -F= '$1 == "Y" { print $2 }')
[ "$width" = 980 ]
[ "$height" = 620 ]

i=0
while [ "$i" -lt 100 ]; do
	status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings status 2>/dev/null || true)
	[ "$status" = ready ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$status" = ready ]

i=0
while [ "$i" -lt 100 ]; do
	display_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings displayStatus 2>/dev/null || true)
	[ "$display_status" = ready ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$display_status" = ready ]
display_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings displayCount)
[ "$display_count" -ge 1 ]

section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = displays ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = audio ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select input >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	input_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings inputStatus 2>/dev/null || true)
	[ "$input_status" = ready ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$input_status" = ready ]
input_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings inputCount)
[ "$input_count" -ge 1 ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null

DISPLAY=$display xdotool windowactivate --sync "$window"
DISPLAY=$display xdotool key Down
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = power ]

i=0
while [ "$i" -lt 100 ]; do
	power_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerProviderStatus 2>/dev/null || true)
	[ "$power_status" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$power_status" = available ]
power_dpms_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsStatus)
case $power_dpms_status in
available | partial | restricted | unavailable) ;;
*)
	printf 'Power DPMS IPC returned invalid state: %s\n' "$power_dpms_status" >&2
	exit 1
	;;
esac

i=0
while [ "$i" -lt 100 ]; do
	power_watch_count=$(settings_power_watch_count)
	[ "$power_watch_count" -eq 1 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$power_watch_count" -eq 1 ]

power_enabled=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsEnabled)
[ "$power_enabled" = true ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerSetDpms false >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	power_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerBusy 2>/dev/null || true)
	[ "$power_busy" = true ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_busy" = true ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings close >/dev/null
sleep 0.1
if ! pgrep -af '[d]wm-quickshell-controlcenter power-dpms off$' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
	printf 'Power mutation did not survive Settings closure\n' >&2
	exit 1
fi
i=0
while [ "$i" -lt 200 ]; do
	power_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerBusy 2>/dev/null || true)
	[ "$power_busy" = false ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_busy" = false ]
[ "$(cat "$power_state/dpms-enabled")" = 0 ]
power_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerMessage)
[ "$power_message" = 'Power setting updated' ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings open >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select power >/dev/null
power_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerMessage)
[ "$power_message" = 'Power setting updated' ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerSetDpms true >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	power_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerBusy 2>/dev/null || true)
	[ "$power_busy" = false ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_busy" = false ]
[ "$(cat "$power_state/dpms-enabled")" = 1 ]
DISPLAY=$display xdotool windowactivate --sync "$window"

# These offsets target the first "displays" section entry below the shared
# large-surface header and search field.
DISPLAY=$display xdotool mousemove "$((x + 120))" "$((y + 210))" click 1
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = displays ]
i=0
while [ "$i" -lt 100 ]; do
	if ! pgrep -af '[d]wm-quickshell-controlcenter (power-snapshot|power-watch)$' |
		grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if pgrep -af '[d]wm-quickshell-controlcenter (power-snapshot|power-watch)$' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
	printf 'Settings-owned power work remained active after leaving Power\n' >&2
	exit 1
fi

DISPLAY=$display xdotool windowactivate --sync "$window"
DISPLAY=$display xdotool type --delay 20 network
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = network ]

i=0
while [ "$i" -lt 100 ]; do
	network_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings networkProviderStatus 2>/dev/null || true)
	[ "$network_status" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$network_status" = available ]
network_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings networkDeviceCount)
[ "$network_count" -ge 1 ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select bluetooth >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	bluetooth_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings bluetoothProviderStatus 2>/dev/null || true)
	[ "$bluetooth_status" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$bluetooth_status" = available ]

# IPC selection clears a search that hides the requested section.
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = audio ]

DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm settings$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm settings$' >/dev/null 2>&1; then
	printf 'Settings window did not close on Escape\n' >&2
	exit 1
fi

if pgrep -f '[d]wm-settings-provider discover$' >/dev/null; then
	printf 'Settings capability provider remained active after close\n' >&2
	exit 1
fi

if pgrep -af '[d]wm-quickshell-network (snapshot|wifi-scan|wifi-connect|connect|disconnect|forget)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-network" >/dev/null; then
	printf 'Settings-owned network work remained active after close\n' >&2
	exit 1
fi
if pgrep -af '[d]wm-quickshell-controls (bluetooth-snapshot|bluetooth-scan|bluetooth-power|bluetooth-pair|bluetooth-trust|bluetooth-connect|bluetooth-disconnect|bluetooth-remove)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controls" >/dev/null; then
	printf 'Settings-owned Bluetooth work remained active after close\n' >&2
	exit 1
fi
if pgrep -af '[d]wm-quickshell-controlcenter (power-snapshot|power-watch|power-profile-set|power-dpms|power-dpms-timeout|power-lock|power-lock-timeout)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
	printf 'Settings-owned power work remained active after close\n' >&2
	exit 1
fi

idle_sample_seconds=2
[ "$cpu_sample_seconds" -gt 0 ] && idle_sample_seconds=$cpu_sample_seconds
before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
sleep "$idle_sample_seconds"
after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
cpu_percent=$(awk -v delta="$((after - before))" -v ticks="$clock_ticks" \
	-v seconds="$idle_sample_seconds" 'BEGIN { printf "%.3f", (delta * 100) / (ticks * seconds) }')
awk -v cpu="$cpu_percent" 'BEGIN { exit !(cpu < 10.0) }'

if [ "$cpu_sample_seconds" -gt 0 ]; then
	cpu_delta=$(awk -v baseline="$baseline_cpu_percent" -v after="$cpu_percent" \
		'BEGIN { delta = after - baseline; if (delta < 0) delta = -delta; printf "%.3f", delta }')
	awk -v delta="$cpu_delta" 'BEGIN { exit !(delta <= 0.5) }'
	printf 'Power lifecycle CPU baseline %s%%, after %s%%, delta %s points\n' \
		"$baseline_cpu_percent" "$cpu_percent" "$cpu_delta"
fi

printf 'Quickshell Settings Xvfb and closed-idle sample: PASS (%s%% CPU)\n' "$cpu_percent"
