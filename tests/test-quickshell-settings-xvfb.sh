#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-monitor dbus-run-session glib-compile-schemas \
	gsettings inotifywait quickshell xdotool xprop pgrep getconf; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

test_tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
if [ "$(id -u)" -eq 0 ] && [ "${DWM_SETTINGS_XVFB_UNPRIVILEGED:-0}" != 1 ]; then
	command -v setpriv >/dev/null 2>&1 || {
		printf 'Quickshell Settings Xvfb requires setpriv on a root runner\n' >&2
		exit 1
	}
	unprivileged_uid=$(id -u nobody)
	unprivileged_gid=$(id -g nobody)
	# Root home directories are not traversable by the unprivileged fixture,
	# and Quickshell IPC sockets require a short AF_UNIX path.
	root_runner_work=$(mktemp -d /var/tmp/dwm-settings-xvfb-root.XXXXXX)
	trap 'rm -rf -- "$root_runner_work"' EXIT
	fixture_repo=$root_runner_work/repo
	mkdir -p "$root_runner_work/cache" "$root_runner_work/config" \
		"$root_runner_work/data" "$root_runner_work/runtime" \
		"$root_runner_work/state" "$fixture_repo/tests"
	cp -a "$repo/config" "$repo/scripts" "$fixture_repo/"
	cp "$repo/dwm" "$fixture_repo/dwm"
	cp "$0" "$fixture_repo/tests/test-quickshell-settings-xvfb.sh"
	chown -R "$unprivileged_uid:$unprivileged_gid" "$root_runner_work"
	chmod 700 "$fixture_repo/dwm" "$root_runner_work/runtime"
	if HOME="$root_runner_work" TMPDIR="$root_runner_work" \
		DWM_TEST_TMP_ROOT="$root_runner_work" \
		DWM_SETTINGS_TEST_DWM_BIN="$fixture_repo/dwm" \
		DWM_SETTINGS_TEST_RUNTIME_DIR="$root_runner_work/runtime" \
		DWM_SETTINGS_XVFB_UNPRIVILEGED=1 \
		XDG_CACHE_HOME="$root_runner_work/cache" \
		XDG_CONFIG_HOME="$root_runner_work/config" \
		XDG_DATA_HOME="$root_runner_work/data" \
		XDG_RUNTIME_DIR="$root_runner_work/runtime" \
		XDG_STATE_HOME="$root_runner_work/state" \
		setpriv --reuid "$unprivileged_uid" --regid "$unprivileged_gid" \
		--clear-groups "$fixture_repo/tests/test-quickshell-settings-xvfb.sh" "$@"; then
		root_runner_status=0
	else
		root_runner_status=$?
	fi
	rm -rf -- "$root_runner_work"
	trap - EXIT
	exit "$root_runner_status"
fi
mkdir -p -- "$test_tmp_root"

if [ "${DWM_SETTINGS_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_SETTINGS_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "$test_tmp_root/dwm-settings-xvfb.XXXXXX")
display=":$((($$ % 400) + 700))"
dwm_bin=${DWM_SETTINGS_TEST_DWM_BIN:-$repo/dwm}
runtime_alias_dir=
test_stage='initializing fixture'

capture_process_identity() (
	identity_pid=$1
	[ -r "/proc/$identity_pid/stat" ] || return 1
	IFS= read -r identity_stat <"/proc/$identity_pid/stat" || return 1
	identity_fields=${identity_stat##*) }
	# The remaining proc stat fields are space-delimited by the kernel.
	# shellcheck disable=SC2086
	set -- $identity_fields
	[ "$1" != Z ] || return 1
	[ -n "${20:-}" ] || return 1
	printf '%s:%s\n' "$identity_pid" "${20}"
)

process_identity_alive() (
	identity=$1
	identity_pid=${identity%%:*}
	identity_start=${identity#*:}
	[ -n "$identity_pid" ] && [ "$identity_start" != "$identity" ] || return 1
	current_identity=$(capture_process_identity "$identity_pid") || return 1
	[ "$current_identity" = "$identity" ]
)

terminate_process_identity() {
	terminate_identity=$1
	[ -n "$terminate_identity" ] || return 0
	terminate_pid=${terminate_identity%%:*}
	if process_identity_alive "$terminate_identity"; then
		kill -TERM "$terminate_pid" 2>/dev/null || true
	fi
	terminate_attempt=0
	while [ "$terminate_attempt" -lt 20 ] && process_identity_alive "$terminate_identity"; do
		terminate_attempt=$((terminate_attempt + 1))
		sleep 0.05
	done
	if process_identity_alive "$terminate_identity"; then
		kill -KILL "$terminate_pid" 2>/dev/null || true
	fi
	terminate_attempt=0
	while [ "$terminate_attempt" -lt 20 ] && process_identity_alive "$terminate_identity"; do
		terminate_attempt=$((terminate_attempt + 1))
		sleep 0.05
	done
	wait "$terminate_pid" 2>/dev/null || true
}

scoped_settings_watcher_identities() (
	for watcher_proc in /proc/[0-9]*; do
		watcher_pid=${watcher_proc##*/}
		[ -r "$watcher_proc/cmdline" ] || continue
		watcher_command=$(tr '\0' ' ' <"$watcher_proc/cmdline" 2>/dev/null) || continue
		case $watcher_command in
		*"$work/"*"dwm-settings-display watch "* | *"$work/"*"dwm-settings-input watch "*) ;;
		*) continue ;;
		esac
		capture_process_identity "$watcher_pid" || true
	done
)

cleanup() {
	cleanup_status=$?
	set +e
	if [ "$cleanup_status" -ne 0 ]; then
		printf 'Settings Xvfb failed while %s (status %s)\n' \
			"${test_stage:-stage unknown}" "$cleanup_status" >&2
		if [ -f "${work:-}/quickshell.log" ]; then
			tail -80 "$work/quickshell.log" >&2
		fi
	fi
	terminate_process_identity "${quickshell_identity:-}"
	watcher_identities=$(scoped_settings_watcher_identities)
	for watcher_identity in $watcher_identities; do
		terminate_process_identity "$watcher_identity"
	done
	terminate_process_identity "${dwm_identity:-}"
	terminate_process_identity "${xvfb_identity:-}"
	if [ -n "${runtime_alias_dir:-}" ]; then
		rm -f -- "$runtime_alias_dir/runtime"
		rmdir -- "$runtime_alias_dir" 2>/dev/null || true
	fi
	rm -rf "$work"
	trap - EXIT HUP INT TERM
	exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

home=$work/home
helper_tmp=$work/tmp
runtime_storage=${DWM_SETTINGS_TEST_RUNTIME_DIR:-$work/runtime}
runtime=$runtime_storage
schema_dir=$work/schemas
config_home=$home/.config
data_home=$home/.local/share
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" \
	"$config_home/autostart" "$data_home/applications" \
	"$data_home/dwm-titus/scripts" "$runtime_storage" "$schema_dir" "$helper_tmp"
chmod 700 "$runtime_storage"
if [ "${#runtime}" -gt 64 ]; then
	runtime_alias_dir=$(mktemp -d /tmp/dwm-settings-runtime.XXXXXX)
	ln -s "$runtime_storage" "$runtime_alias_dir/runtime"
	runtime=$runtime_alias_dir/runtime
fi
cat >"$schema_dir/apps.light-locker.gschema.xml" <<'EOF'
<schemalist>
  <schema id="apps.light-locker" path="/apps/light-locker/">
    <key name="lock-after-screensaver" type="u">
      <default>0</default>
    </key>
    <key name="lock-on-suspend" type="b">
      <default>false</default>
    </key>
  </schema>
</schemalist>
EOF
glib-compile-schemas "$schema_dir"
export GSETTINGS_SCHEMA_DIR="$schema_dir"
export GSETTINGS_BACKEND=keyfile
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
# Keep this nested-X11 fixture independent from the host system UPower service
# so versioned helper battery records exercise the fallback parser.
sed -i 's/readonly property var nativeBattery: UPower.displayDevice/readonly property var nativeBattery: null/' \
	"$config_home/quickshell/power/PowerModel.qml"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
cat >"$data_home/applications/kitty.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Kitty Fixture
Exec=kitty
Categories=System;TerminalEmulator;
EOF
cat >"$data_home/applications/Alacritty.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Alacritty Fixture
Exec=alacritty
Categories=System;TerminalEmulator;
EOF
cat >"$config_home/autostart/dwm-test-autostart.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=dwm Test Autostart
Exec=/usr/bin/true
EOF
cat >"$config_home/autostart/picom.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Picom Session Fixture
Exec=/usr/bin/true
EOF
cat >"$config_home/autostart/vendor-app+variant.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plus ID Autostart Fixture
Exec=/usr/bin/true
EOF
cp "$repo/scripts/dwm-settings-provider" "$repo/scripts/dwm-system-health" \
	"$repo/scripts/dwm-settings-display" "$repo/scripts/dwm-settings-input" \
	"$repo/scripts/dwm-display-setup" \
	"$repo/scripts/dwm-quickshell-controlcenter" "$repo/scripts/dwm-quickshell-controls" \
	"$repo/scripts/dwm-quickshell-network" "$repo/scripts/dwm-diagnostics" \
	"$repo/scripts/dwm-default-apps" "$repo/scripts/dwm-xdg-autostart" \
	"$repo/scripts/dwm-terminal" "$repo/scripts/dwm-lock" "$data_home/dwm-titus/scripts/"

malformed_power_snapshot=$work/malformed-power-snapshot
mv "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" \
	"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter.real"
cat >"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" <<'SH'
#!/bin/sh
set -eu
fixture=${DWM_SETTINGS_TEST_MALFORMED_POWER_SNAPSHOT:?}
if [ "${1:-}" = power-snapshot ] && [ -r "$fixture" ]; then
	case $(cat "$fixture") in
	protocol)
		printf 'power-protocol\t1\t\n'
		printf 'provider\tpower\tavailable\tuser-session\tMalformed protocol fixture\n'
		printf 'power-dpms\tavailable\tyes\t600\tuser-session\tValid owning row\n'
		;;
	records)
		printf 'power-protocol\t1\t0\n'
		printf 'provider\tpower\tavailable\tuser-session\tMalformed record fixture\n'
		printf 'power-dpms\tavailable\tyes\t1e2\tuser-session\tExponent timeout\n'
		printf 'power-lock\tavailable\tyes\t0x10\tno\tuser-session\tHex timeout\n'
		;;
	battery)
		printf 'power-protocol\t1\t0\n'
		printf 'provider\tpower\tavailable\tuser-session\tExponent battery-rate fixture\n'
		printf 'power-battery\tavailable\tdischarging\t73\t4200\t0\t1E-7\tValid exponent rate\n'
		;;
	esac
	exit 0
fi
exec "$(dirname -- "$0")/dwm-quickshell-controlcenter.real" "$@"
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter"
cat >"$data_home/dwm-titus/scripts/kitty" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$data_home/dwm-titus/scripts/alacritty" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$data_home/dwm-titus/scripts/kitty" "$data_home/dwm-titus/scripts/alacritty"

cat >"$data_home/dwm-titus/scripts/dbus-monitor" <<'SH'
#!/bin/sh
trap 'exit 0' HUP INT TERM
printf 'signal\n'
while :; do
	sleep 1
done
SH
cat >"$data_home/dwm-titus/scripts/light-locker" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$data_home/dwm-titus/scripts/nmcli" <<'SH'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
	case $1 in
	--terse) shift ;;
	--escape) shift 2 ;;
	--separator | -f) shift 2 ;;
	*) break ;;
	esac
done
case $* in
'device status')
	printf 'lo:loopback:connected:lo\n'
	printf 'enp0s1:ethernet:connected:Wired fixture\n'
	;;
'connection show --active')
	printf 'Wired fixture:uuid-wired:802-3-ethernet:enp0s1\n'
	;;
'connection show')
	printf 'Wired fixture:uuid-wired:802-3-ethernet\n'
	;;
'device wifi list --rescan no') ;;
*) exit 2 ;;
esac
SH
cat >"$data_home/dwm-titus/scripts/bluetoothctl" <<'SH'
#!/bin/sh
set -eu
case $* in
show)
	printf 'Controller 00:11:22:33:44:55\n'
	printf '\tPowered: yes\n'
	;;
'devices Connected') ;;
devices) ;;
*) exit 2 ;;
esac
SH
cat >"$data_home/dwm-titus/scripts/busctl" <<'SH'
#!/bin/sh
set -eu
case $* in
'--system --json=short call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects')
	cat <<'JSON'
{"type":"a{oa{sa{sv}}}","data":[{"/org/bluez/hci0":{"org.bluez.Adapter1":{"Address":{"type":"s","data":"00:11:22:33:44:55"},"Alias":{"type":"s","data":"Test Adapter"},"Powered":{"type":"b","data":true},"Discovering":{"type":"b","data":false},"Pairable":{"type":"b","data":true}}}}]}
JSON
	;;
'--system monitor org.bluez')
	trap 'exit 0' HUP INT TERM
	printf 'signal\n'
	while :; do
		sleep 1
	done
	;;
*) exit 1 ;;
esac
SH
chmod +x "$data_home/dwm-titus/scripts/dbus-monitor" \
	"$data_home/dwm-titus/scripts/light-locker" \
	"$data_home/dwm-titus/scripts/nmcli" \
	"$data_home/dwm-titus/scripts/bluetoothctl" \
	"$data_home/dwm-titus/scripts/busctl"

power_state=$work/power-state
mkdir -p "$power_state"
printf '1\n' >"$power_state/dpms-enabled"
printf '600\n' >"$power_state/dpms-timeout"
printf '600\n' >"$power_state/saver-timeout"
cat >"$data_home/dwm-titus/scripts/xset" <<'SH'
#!/bin/sh
set -eu
state=${DWM_SETTINGS_TEST_POWER_STATE:?}
case ${1:-} in
q)
	enabled=$(cat "$state/dpms-enabled")
	timeout=$(cat "$state/dpms-timeout")
	saver_timeout=$(cat "$state/saver-timeout")
	[ "$enabled" = 1 ] && label=Enabled || label=Disabled
	cat <<EOF
Screen Saver:
  timeout:  $saver_timeout    cycle:  600
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
s)
	case ${2:-} in
	off) printf '0\n' >"$state/saver-timeout" ;;
	noblank) : ;;
	*) printf '%s\n' "$2" >"$state/saver-timeout" ;;
	esac
	;;
*) exit 2 ;;
esac
SH
chmod +x "$data_home/dwm-titus/scripts/xset"

Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
xvfb_identity=$(capture_process_identity "$xvfb_pid")

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
	"$dwm_bin" >"$work/dwm.log" 2>&1 &
dwm_pid=$!
dwm_identity=$(capture_process_identity "$dwm_pid")

HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	gsettings set apps.light-locker lock-after-screensaver 5
HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	gsettings set apps.light-locker lock-on-suspend true

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	TMPDIR="$helper_tmp" \
	DWM_SETTINGS_TEST_POWER_STATE="$power_state" DWM_SETTINGS_TEST_DELAY_POWER=1 \
	DWM_SETTINGS_TEST_MALFORMED_POWER_SNAPSHOT="$malformed_power_snapshot" \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!
quickshell_identity=$(capture_process_identity "$quickshell_pid")
test_stage='waiting for Quickshell IPC'

config=$config_home/quickshell/shell.qml
settings_power_watch_count() {
	watch_count=0
	for monitor_pid in $(pgrep -f '[d]bus-monitor --system.*org.freedesktop.UPower.*org.freedesktop.UPower.PowerProfiles.*org.freedesktop.login1' || true); do
		[ -r "/proc/$monitor_pid/status" ] || continue
		monitor_parent=$(awk '$1 == "PPid:" { print $2; exit }' "/proc/$monitor_pid/status")
		[ -n "$monitor_parent" ] && [ -r "/proc/$monitor_parent/cmdline" ] || continue
		monitor_command=$(tr '\0' ' ' <"/proc/$monitor_parent/cmdline")
		case $monitor_command in
		*"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter power-watch"* | \
			*"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter.real power-watch"*)
			watch_count=$((watch_count + 1))
			;;
		esac
	done
	printf '%s\n' "$watch_count"
}

settings_power_gsettings_watch_count() {
	watch_count=0
	for monitor_pid in $(pgrep -f '[g]settings monitor apps.light-locker' || true); do
		[ -r "/proc/$monitor_pid/status" ] || continue
		monitor_parent=$(awk '$1 == "PPid:" { print $2; exit }' "/proc/$monitor_pid/status")
		[ -n "$monitor_parent" ] && [ -r "/proc/$monitor_parent/cmdline" ] || continue
		monitor_command=$(tr '\0' ' ' <"/proc/$monitor_parent/cmdline")
		case $monitor_command in
		*"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter power-watch"* | \
			*"$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter.real power-watch"*)
			watch_count=$((watch_count + 1))
			;;
		esac
	done
	printf '%s\n' "$watch_count"
}

settings_defaults_watch_count() {
	pgrep -af '[i]notifywait' 2>/dev/null |
		awk -v expected="$data_home/applications" '
			index($0, " -r ") && index($0, expected) { count++ }
			END { print count + 0 }
		'
}

settings_autostart_watch_count() {
	expected="$data_home/dwm-titus/scripts/dwm-xdg-autostart watch"
	count=0
	for watch_pid in $(pgrep -f '[d]wm-xdg-autostart watch$' 2>/dev/null || true); do
		[ -r "/proc/$watch_pid/cmdline" ] || continue
		watch_command=$(tr '\0' ' ' <"/proc/$watch_pid/cmdline")
		case $watch_command in *"$expected"*) ;; *) continue ;; esac
		watch_parent=$(awk '$1 == "PPid:" { print $2; exit }' "/proc/$watch_pid/status" 2>/dev/null || true)
		if [ -n "$watch_parent" ] && [ -r "/proc/$watch_parent/cmdline" ]; then
			watch_parent_command=$(tr '\0' ' ' <"/proc/$watch_parent/cmdline")
			case $watch_parent_command in *"$expected"*) continue ;; esac
		fi
		count=$((count + 1))
	done
	printf '%s\n' "$count"
}

cpu_sample_seconds=${DWM_SETTINGS_POWER_CPU_SECONDS:-30}
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
if ! DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings status >/dev/null 2>&1; then
	printf 'Quickshell Settings IPC did not become ready\n' >&2
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

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
test_stage='validating display and input settings'

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
test_stage='waiting for keyboard navigation to Power'
i=0
while [ "$i" -lt 100 ]; do
	section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection \
		2>/dev/null || true)
	[ "$section" = power ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$section" = power ]
test_stage='validating power settings'

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
i=0
while [ "$i" -lt 100 ]; do
	power_gsettings_watch_count=$(settings_power_gsettings_watch_count)
	[ "$power_gsettings_watch_count" -eq 1 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$power_gsettings_watch_count" -eq 1 ]

power_lock_enabled=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerLockEnabled)
[ "$power_lock_enabled" = true ]
HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	gsettings set apps.light-locker lock-after-screensaver 0
i=0
while [ "$i" -lt 100 ]; do
	power_lock_enabled=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerLockEnabled 2>/dev/null || true)
	[ "$power_lock_enabled" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$power_lock_enabled" = false ]
HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	gsettings set apps.light-locker lock-after-screensaver 5
i=0
while [ "$i" -lt 100 ]; do
	power_lock_enabled=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerLockEnabled 2>/dev/null || true)
	[ "$power_lock_enabled" = true ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$power_lock_enabled" = true ]

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
if ! pgrep -af '[d]wm-quickshell-controlcenter([.]real)? power-dpms off$' |
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

printf 'protocol\n' >"$malformed_power_snapshot"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select power >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	power_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerProviderStatus 2>/dev/null || true)
	[ "$power_status" = unavailable ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_status" = unavailable ]

printf 'records\n' >"$malformed_power_snapshot"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select power >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	power_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerProviderStatus 2>/dev/null || true)
	power_dpms_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsStatus 2>/dev/null || true)
	power_lock_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerLockStatus 2>/dev/null || true)
	[ "$power_status" = available ] && [ "$power_dpms_status" = unavailable ] &&
		[ "$power_lock_status" = unavailable ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_status" = available ]
[ "$power_dpms_status" = unavailable ]
[ "$power_lock_status" = unavailable ]
power_enabled=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsEnabled)
power_timeout=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsTimeout)
[ "$power_enabled" = false ]
[ "$power_timeout" -eq 0 ]

printf 'battery\n' >"$malformed_power_snapshot"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select power >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	power_battery_available=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerBatteryAvailable 2>/dev/null || true)
	power_battery_percent=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerBatteryPercent 2>/dev/null || true)
	[ "$power_battery_available" = true ] && [ "$power_battery_percent" = 73 ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_battery_available" = true ]
[ "$power_battery_percent" = 73 ]

rm -f "$malformed_power_snapshot"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select power >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	power_dpms_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings powerDpmsStatus 2>/dev/null || true)
	[ "$power_dpms_status" = available ] && break
	i=$((i + 1))
	sleep 0.02
done
[ "$power_dpms_status" = available ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select defaults >/dev/null
test_stage='validating defaults and autostart settings'
i=0
while [ "$i" -lt 200 ]; do
	defaults_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsProviderStatus 2>/dev/null || true)
	defaults_role_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleCount 2>/dev/null || true)
	autostart_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartProviderStatus 2>/dev/null || true)
	case $defaults_status:$autostart_status:$defaults_role_count in
	available:ready:3 | available:degraded:3 | partial:ready:3 | partial:degraded:3) break ;;
	esac
	i=$((i + 1))
	sleep 0.05
done
case $defaults_status in available | partial) : ;; *) exit 1 ;; esac
[ "$defaults_role_count" -eq 3 ]
case $autostart_status in ready | degraded) : ;; *) exit 1 ;; esac
[ "$(settings_defaults_watch_count)" -eq 1 ]
[ "$(settings_autostart_watch_count)" -eq 1 ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings \
	autostartEntryName vendor-app+variant.desktop)" = 'Plus ID Autostart Fixture' ]

sed -i 's/Name=dwm Test Autostart/Name=dwm Test Autostart Changed/' \
	"$config_home/autostart/dwm-test-autostart.desktop"
i=0
while [ "$i" -lt 200 ]; do
	autostart_name=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryName dwm-test-autostart.desktop 2>/dev/null || true)
	[ "$autostart_name" = 'dwm Test Autostart Changed' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$autostart_name" = 'dwm Test Autostart Changed' ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryOrigin dwm-test-autostart.desktop)" = user-only ]

sed -i 's/terminal = "alacritty"/terminal = "kitty"/' "$config_home/dwm-titus/hotkeys.toml"
i=0
while [ "$i" -lt 200 ]; do
	terminal_id=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleDesktopId terminal 2>/dev/null || true)
	[ "$terminal_id" = kitty.desktop ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$terminal_id" = kitty.desktop ]
sed -i 's/terminal = "kitty"/terminal = "alacritty"/' "$config_home/dwm-titus/hotkeys.toml"
i=0
while [ "$i" -lt 200 ]; do
	terminal_id=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleDesktopId terminal 2>/dev/null || true)
	[ "$terminal_id" = Alacritty.desktop ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$terminal_id" = Alacritty.desktop ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSetSearch picom >/dev/null
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartFilteredCount)" -eq 1 ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSetSearch '' >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsSetRole terminal kitty.desktop >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	defaults_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsBusy 2>/dev/null || true)
	terminal_id=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleDesktopId terminal 2>/dev/null || true)
	[ "$defaults_busy" = false ] && [ "$terminal_id" = kitty.desktop ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$defaults_busy" = false ]
[ "$terminal_id" = kitty.desktop ]
grep -Fqx 'terminal = "kitty"' "$config_home/dwm-titus/hotkeys.toml"

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsResetRole terminal >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	defaults_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsBusy 2>/dev/null || true)
	terminal_id=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleDesktopId terminal 2>/dev/null || true)
	[ "$defaults_busy" = false ] && [ "$terminal_id" = Alacritty.desktop ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$defaults_busy" = false ]
[ "$terminal_id" = Alacritty.desktop ]
grep -Fqx 'terminal = "alacritty"' "$config_home/dwm-titus/hotkeys.toml"

# A helper that prints the exact success record but exits nonzero must never
# produce a saved message in QML. Snapshot/watch continue through the real
# helper so the pane remains live while this failure boundary is exercised.
defaults_helper=$data_home/dwm-titus/scripts/dwm-default-apps
mv "$defaults_helper" "$defaults_helper.real"
cat >"$defaults_helper" <<'EOF'
#!/bin/sh
case ${1:-} in
snapshot | watch) exec "$0.real" "$@" ;;
set-role)
	printf 'defaults-result\t1\t0\tset-role\t%s\t%s\tok\n' "$2" "$3"
	exit 1
	;;
*) exec "$0.real" "$@" ;;
esac
EOF
chmod +x "$defaults_helper"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsSetRole terminal kitty.desktop >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	defaults_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsBusy 2>/dev/null || true)
	[ "$defaults_busy" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$defaults_busy" = false ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsMessage)" = \
	'Defaults helper did not confirm the requested change' ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings defaultsRoleDesktopId terminal)" = \
	Alacritty.desktop ]
rm "$defaults_helper"
mv "$defaults_helper.real" "$defaults_helper"

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSet dwm-test-autostart.desktop false >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	autostart_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartBusy 2>/dev/null || true)
	autostart_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryState dwm-test-autostart.desktop 2>/dev/null || true)
	[ "$autostart_busy" = false ] && [ "$autostart_state" = disabled ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$autostart_busy" = false ]
[ "$autostart_state" = disabled ]
grep -Eq '^NotShowIn=.*X-DWM' "$config_home/autostart/dwm-test-autostart.desktop"

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSet dwm-test-autostart.desktop true >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	autostart_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartBusy 2>/dev/null || true)
	autostart_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryState dwm-test-autostart.desktop 2>/dev/null || true)
	[ "$autostart_busy" = false ] && [ "$autostart_state" = enabled ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$autostart_busy" = false ]
[ "$autostart_state" = enabled ]
if grep -Eq '^NotShowIn=.*X-DWM' "$config_home/autostart/dwm-test-autostart.desktop"; then
	printf 'Autostart enable retained the dwm exclusion\n' >&2
	exit 1
fi

autostart_helper=$data_home/dwm-titus/scripts/dwm-xdg-autostart
mv "$autostart_helper" "$autostart_helper.real"
cat >"$autostart_helper" <<'EOF'
#!/bin/sh
case ${1:-} in
snapshot | watch) exec "$0.real" "$@" ;;
set)
	printf 'autostart-protocol\t1\t0\n'
	printf 'action\tsuccess\tset\t%s\t%s\t%064d\t\tfixture\n' "$2" "$3" 0
	exit 1
	;;
*) exec "$0.real" "$@" ;;
esac
EOF
chmod +x "$autostart_helper"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSet dwm-test-autostart.desktop false >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	autostart_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartBusy 2>/dev/null || true)
	[ "$autostart_busy" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$autostart_busy" = false ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartMessage)" = \
	'Autostart helper did not confirm the requested change' ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryState dwm-test-autostart.desktop)" = \
	enabled ]
rm "$autostart_helper"
mv "$autostart_helper.real" "$autostart_helper"

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSet picom.desktop false >/dev/null
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartConfirming)" = true ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryState picom.desktop)" = enabled ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartCancel >/dev/null
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartConfirming)" = false ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartSet picom.desktop false >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartConfirm >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	autostart_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartBusy 2>/dev/null || true)
	autostart_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings autostartEntryState picom.desktop 2>/dev/null || true)
	[ "$autostart_busy" = false ] && [ "$autostart_state" = disabled ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$autostart_busy" = false ]
[ "$autostart_state" = disabled ]

DISPLAY=$display xdotool windowactivate --sync "$window"

# These offsets target the first "displays" section entry below the shared
# large-surface header and search field.
DISPLAY=$display xdotool mousemove "$((x + 120))" "$((y + 210))" click 1
section=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings currentSection)
[ "$section" = displays ]
i=0
while [ "$i" -lt 100 ]; do
	[ "$(settings_defaults_watch_count)" -eq 0 ] &&
		[ "$(settings_autostart_watch_count)" -eq 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(settings_defaults_watch_count)" -eq 0 ]
[ "$(settings_autostart_watch_count)" -eq 0 ]
i=0
while [ "$i" -lt 100 ]; do
	if ! pgrep -af '[d]wm-quickshell-controlcenter([.]real)? (power-snapshot|power-watch)$' |
		grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if pgrep -af '[d]wm-quickshell-controlcenter([.]real)? (power-snapshot|power-watch)$' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
	printf 'Settings-owned power work remained active after leaving Power\n' >&2
	exit 1
fi
[ "$(settings_power_gsettings_watch_count)" -eq 0 ]

DISPLAY=$display xdotool windowactivate --sync "$window"
DISPLAY=$display xdotool type --delay 20 network
test_stage='validating network and Bluetooth settings'
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
test_stage='closing Settings and checking lifecycle cleanup'
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
if pgrep -af '[d]wm-settings-display watch [0-9]+ [0-9]+$' |
	grep -F "$data_home/dwm-titus/scripts/dwm-settings-display" >/dev/null; then
	printf 'Settings display watcher remained active after close\n' >&2
	exit 1
fi
if pgrep -af '[d]wm-settings-input watch [0-9]+ [0-9]+$' |
	grep -F "$data_home/dwm-titus/scripts/dwm-settings-input" >/dev/null; then
	printf 'Settings input watcher remained active after close\n' >&2
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
if pgrep -af '[d]wm-quickshell-controlcenter([.]real)? (power-snapshot|power-watch|power-profile-set|power-dpms|power-dpms-timeout|power-lock|power-lock-timeout)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-quickshell-controlcenter" >/dev/null; then
	printf 'Settings-owned power work remained active after close\n' >&2
	exit 1
fi
if pgrep -af '[d]wm-default-apps (snapshot|watch|set-role|set-mime|reset-role|reset-mime)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-default-apps" >/dev/null; then
	printf 'Settings-owned Defaults work remained active after close\n' >&2
	exit 1
fi
if pgrep -af '[d]wm-xdg-autostart (snapshot|watch|set|reset)' |
	grep -F "$data_home/dwm-titus/scripts/dwm-xdg-autostart" >/dev/null; then
	printf 'Settings-owned autostart work remained active after close\n' >&2
	exit 1
fi
if find "$helper_tmp" -mindepth 1 -maxdepth 1 \
	\( -name 'dwm-default-apps-watch.*' -o -name 'dwm-xdg-autostart-watch.*' \) \
	-print -quit | grep -q .; then
	printf 'Settings-owned Defaults or autostart watcher workspace remained after close\n' >&2
	exit 1
fi

idle_sample_seconds=2
test_stage='sampling closed-shell CPU usage'
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
