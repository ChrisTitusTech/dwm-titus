#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
screen_geometry=${DWM_SETTINGS_TEST_SCREEN_GEOMETRY:-1280x800x24}
expected_window_width=${DWM_SETTINGS_EXPECTED_WINDOW_WIDTH:-1180}
expected_window_height=${DWM_SETTINGS_EXPECTED_WINDOW_HEIGHT:-760}

for command_name in Xvfb dbus-monitor dbus-run-session glib-compile-schemas \
	gsettings inotifywait quickshell xdotool xinput xprop pgrep getconf; do
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
	IFS= read -r identity_stat 2>/dev/null <"/proc/$identity_pid/stat" || return 1
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
		if [ -n "${quickshell_pid:-}" ] && [ -n "${quickshell_identity:-}" ] &&
			! process_identity_alive "$quickshell_identity"; then
			wait "$quickshell_pid" 2>/dev/null
			printf 'Quickshell exited before teardown with status %s\n' "$?" >&2
		fi
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
fixture_feh=$work/feh
config_home=$home/.config
data_home=$home/.local/share
state_home=$home/.local/state
export XDG_STATE_HOME="$state_home"
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" \
	"$config_home/autostart" "$data_home/applications" \
	"$data_home/dwm-titus/config" "$data_home/dwm-titus/scripts" \
	"$state_home/dwm-titus/appearance" \
	"$home/Pictures/backgrounds" \
	"$runtime_storage" "$schema_dir" "$helper_tmp"
chmod 700 "$runtime_storage"
cat >"$fixture_feh" <<'EOF'
#!/bin/sh
set -eu

loadable=false
for argument in "$@"; do
	[ "$argument" != --loadable ] || loadable=true
done

if [ "$loadable" = true ]; then
	for argument in "$@"; do
		case $argument in
		-- | -*) continue ;;
		esac
		if [ -f "$argument" ]; then
			printf '%s\n' "$argument"
		elif [ -d "$argument" ]; then
			find -L "$argument" -type f -print
		fi
	done
fi
EOF
chmod 700 "$fixture_feh"
export DWM_WALLPAPER_FEH="$fixture_feh"
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
cp "$repo/config/quickshell/assets/ctt_logo.png" "$home/Pictures/backgrounds/test-wallpaper.png"
# Keep this nested-X11 fixture independent from the host system UPower service
# so versioned helper battery records exercise the fallback parser.
sed -i 's/readonly property var nativeBattery: UPower.displayDevice/readonly property var nativeBattery: null/' \
	"$config_home/quickshell/power/PowerModel.qml"
cp "$repo/config/"*.toml "$config_home/dwm-titus/"
cp "$repo/config/themes.toml" "$data_home/dwm-titus/config/themes.toml"
printf '# inactive integration watch fixture\n' >"$config_home/dwm-titus/theme-env.sh"
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
	"$repo/scripts/dwm-settings-appearance" "$repo/scripts/dwm-settings-wallpaper" \
	"$repo/scripts/dwm-settings-font" "$repo/scripts/dwm-settings-personalization" \
	"$repo/scripts/dwm-settings-theme" "$repo/scripts/dwm-xsettings" \
	"$repo/scripts/dwm-panel-settings" \
	"$repo/scripts/theme-apply.sh" \
	"$repo/scripts/dwm-terminal" "$repo/scripts/dwm-lock" "$data_home/dwm-titus/scripts/"

appearance_failure_fixture=$work/appearance-snapshot-failure
mv "$data_home/dwm-titus/scripts/dwm-settings-appearance" \
	"$data_home/dwm-titus/scripts/dwm-settings-appearance.real"
cat >"$data_home/dwm-titus/scripts/dwm-settings-appearance" <<'SH'
#!/bin/sh
set -eu
fixture=${DWM_SETTINGS_TEST_APPEARANCE_FAILURE:?}
if [ "${1:-}" = inventory ] && [ -f "$fixture" ] &&
	[ "$(cat "$fixture")" = optional-loss ]; then
	"$(dirname -- "$0")/dwm-settings-appearance.real" "$@" | awk -F '\t' 'BEGIN { OFS = "\t" }
		$1 == "candidate" && ($2 == "wallpaper" || $2 == "cursor" || $2 == "icon" ||
			$2 == "gtk" || $2 == "qt" || $2 == "compositor") { next }
		$1 == "selection" && $2 == "wallpaper" {
			$3 = "unavailable"; $6 = "Wallpaper folder is unavailable";
		}
		$1 == "selection" && ($2 == "cursor" || $2 == "icon" || $2 == "gtk") {
			$3 = "unavailable"; $6 = "Configured selection is not installed";
		}
		$1 == "selection" && $2 == "qt" {
			$3 = "partial"; $4 = "qt6ct"; $5 = "";
			$6 = "Configured Qt platform theme backend is not installed";
		}
		$1 == "selection" && $2 == "compositor" {
			$3 = "unavailable"; $4 = ""; $5 = "missing";
			$6 = "Picom is optional and not installed";
		}
		{ print }'
	exit 0
fi
if [ "${1:-}" = snapshot ] && [ -f "$fixture" ]; then
	case $(cat "$fixture") in
	silent) exit 1 ;;
	truncated)
		"$(dirname -- "$0")/dwm-settings-appearance.real" "$@" | awk 'NR <= 5'
		exit 1
		;;
	inventory-only)
		"$(dirname -- "$0")/dwm-settings-appearance.real" "$@" | awk -F '\t' 'BEGIN { OFS = "\t" }
			$1 == "provider" { $3 = "partial" }
			$1 == "integration" {
				$3 = "available"; $5 = "Integration is applied";
			}
			$1 == "error" && ($2 == "gtk" || $2 == "qt" || $2 == "cursor" ||
				$2 == "alacritty" || $2 == "kitty" || $2 == "compositor") { next }
			{ print }
			END {
				print "theme", "unused-broken", "available", "invalid", "true", "automatic", "Unused theme is incomplete";
				print "error", "theme:unused-broken", "missing-key", "Unused theme is missing required keys";
			}'
		exit 0
		;;
	esac
fi
exec "$(dirname -- "$0")/dwm-settings-appearance.real" "$@"
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-settings-appearance"

mv "$data_home/dwm-titus/scripts/dwm-settings-personalization" \
	"$data_home/dwm-titus/scripts/dwm-settings-personalization.real"
cat >"$data_home/dwm-titus/scripts/dwm-settings-personalization" <<'SH'
#!/bin/sh
set -eu
fixture=${DWM_SETTINGS_TEST_APPEARANCE_FAILURE:?}
if [ "${1:-}" = status ] && [ -f "$fixture" ] &&
	[ "$(cat "$fixture")" = optional-loss ]; then
	"$(dirname -- "$0")/dwm-settings-personalization.real" "$@" | awk -F '\t' 'BEGIN { OFS = "\t" }
		$1 == "delegate" && ($2 == "gtk" || $2 == "qt") {
			$3 = "unavailable"; $4 = "";
			$5 = "No trusted advanced editor is installed";
		}
		{ print }'
	exit 0
fi
exec "$(dirname -- "$0")/dwm-settings-personalization.real" "$@"
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-settings-personalization"

wallpaper_status_fixture=$work/wallpaper-status
mv "$data_home/dwm-titus/scripts/dwm-settings-wallpaper" \
	"$data_home/dwm-titus/scripts/dwm-settings-wallpaper.real"
cat >"$data_home/dwm-titus/scripts/dwm-settings-wallpaper" <<'SH'
#!/bin/sh
set -eu
fixture=${DWM_SETTINGS_TEST_WALLPAPER_STATUS:-}
if [ "${1:-}" = status ] && [ "${2:-}" = --read-only ] &&
	[ -n "$fixture" ] && [ -f "$fixture" ]; then
	if [ "$(cat "$fixture")" = optional-loss ]; then
		"$(dirname -- "$0")/dwm-settings-wallpaper.real" "$@" | awk -F '\t' 'BEGIN { OFS = "\t" }
			$1 == "provider" {
				$3 = "partial"; $5 = "Feh is optional and is not installed";
			}
			$1 == "selection" {
				$2 = "unavailable"; $3 = ""; $4 = "fill";
				$5 = "Wallpaper folder is unavailable";
			}
			$1 == "mutation" {
				$2 = "restricted"; $3 = "Feh is optional and is not installed";
			}
			$1 == "reset" {
				$2 = "restricted"; $3 = "No managed wallpaper state exists";
			}
			{ print }'
		exit 0
	fi
	printf 'wallpaper-protocol\t1\t0\n'
	exit 0
fi
exec "$(dirname -- "$0")/dwm-settings-wallpaper.real" "$@"
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-settings-wallpaper"

theme_status_fixture=$work/theme-preview-status
mv "$data_home/dwm-titus/scripts/dwm-settings-theme" \
	"$data_home/dwm-titus/scripts/dwm-settings-theme.real"
cat >"$data_home/dwm-titus/scripts/dwm-settings-theme" <<'SH'
#!/bin/sh
set -eu
fixture=${DWM_SETTINGS_TEST_THEME_STATUS:?}
if [ "${1:-}" = preview-status ] && [ -f "$fixture" ]; then
	case $(cat "$fixture") in
	active-zero)
		printf '%s\n' none >"$fixture"
		printf 'appearance-action-protocol\t1\t0\n'
		printf 'preview-active\tboundary-preview\tnord\n'
		printf 'preview-remaining\t0\n'
		;;
	none)
		printf 'appearance-action-protocol\t1\t0\nresult\tnone\n'
		;;
	active-zero-fail)
		printf x >>"$fixture.calls"
		if [ ! -f "$fixture.started" ]; then
			: >"$fixture.started"
			printf 'appearance-action-protocol\t1\t0\n'
			printf 'preview-active\tboundary-preview\tnord\n'
			printf 'preview-remaining\t0\n'
		else
			exit 1
		fi
		;;
	external-active)
		printf 'appearance-action-protocol\t1\t0\n'
		if [ -f "$fixture.external" ]; then
			printf 'preview-active\texternal-preview\tnord\n'
			printf 'preview-remaining\t30\n'
		else
			printf 'result\tnone\n'
		fi
		;;
	external-failed)
		printf 'appearance-action-protocol\t1\t0\n'
		if [ -f "$fixture.external" ]; then
			printf 'preview-failed\texternal-preview\tExternal preview failed\n'
		else
			printf 'result\tnone\n'
		fi
		;;
	esac
	exit 0
fi
exec "$(dirname -- "$0")/dwm-settings-theme.real" "$@"
SH
chmod +x "$data_home/dwm-titus/scripts/dwm-settings-theme"

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

Xvfb "$display" -screen 0 "$screen_geometry" -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
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
	QT_QPA_PLATFORMTHEME= \
	TMPDIR="$helper_tmp" \
	DWM_SETTINGS_TEST_POWER_STATE="$power_state" DWM_SETTINGS_TEST_DELAY_POWER=1 \
	DWM_SETTINGS_TEST_MALFORMED_POWER_SNAPSHOT="$malformed_power_snapshot" \
	DWM_SETTINGS_TEST_APPEARANCE_FAILURE="$appearance_failure_fixture" \
	DWM_SETTINGS_TEST_WALLPAPER_STATUS="$wallpaper_status_fixture" \
	DWM_SETTINGS_TEST_THEME_STATUS="$theme_status_fixture" \
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
[ "$width" = "$expected_window_width" ]
[ "$height" = "$expected_window_height" ]

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

rm -f -- "$runtime/dwm-settings-wallpaper/exchange-support"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	case $appearance_status in
	available | partial) break ;;
	esac
	i=$((i + 1))
	sleep 0.05
done
case $appearance_status in
available | partial) ;;
*)
	appearance_detail=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderDetail 2>/dev/null || true)
	printf 'Appearance provider did not become readable: %s (%s)\n' \
		"$appearance_status" "$appearance_detail" >&2
	HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		DWM_SETTINGS_TEST_APPEARANCE_FAILURE="$appearance_failure_fixture" \
		"$data_home/dwm-titus/scripts/dwm-settings-appearance" snapshot >&2 || true
	exit 1
	;;
esac
wallpaper_reset_ready=false
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_reset_ready=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperResetReady 2>/dev/null || true)
	[ "$wallpaper_reset_ready" = true ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_reset_ready" != true ] ||
	[ ! -f "$runtime/dwm-settings-wallpaper/exchange-support" ]; then
	printf 'Appearance pane did not prime wallpaper readiness after live shell startup: %s\n' \
		"$wallpaper_reset_ready" >&2
	exit 1
fi
appearance_theme=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme)
appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount)
appearance_application=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceApplicationState)
appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState)
appearance_recovery=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceRecoveryState)
[ "$appearance_theme" = nord ]
[ "$appearance_count" -eq 15 ]
[ "$appearance_application" = partial ]
[ "$appearance_preview" = none ]
[ "$appearance_recovery" = none ]

test_stage='validating shared panel widget persistence'
panel_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelSettingsState)
case $panel_state in defaults | available) ;; *) exit 1 ;; esac
panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume)
[ "$panel_volume" = true ]

panel_status_ready=$work/panel-status.ready
panel_status_used=$work/panel-status.used
managed_panel_helper=$data_home/dwm-titus/scripts/dwm-panel-settings
mv "$managed_panel_helper" "$managed_panel_helper.real"
cat >"$managed_panel_helper" <<EOF
#!/bin/sh
set -eu

if [ "\${1:-}" = status ] && [ ! -e "$panel_status_used" ]; then
	: >"$panel_status_used"
	"$managed_panel_helper.real" status
	: >"$panel_status_ready"
	sleep 2
else
	exec "$managed_panel_helper.real" "\$@"
fi
EOF
chmod 700 "$managed_panel_helper"
HOME=$home XDG_CONFIG_HOME=$config_home XDG_RUNTIME_DIR=$runtime \
	"$managed_panel_helper.real" set volume disabled >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	[ -e "$panel_status_ready" ] && break
	i=$((i + 1))
	sleep 0.01
done
[ -e "$panel_status_ready" ]
HOME=$home XDG_CONFIG_HOME=$config_home XDG_RUNTIME_DIR=$runtime \
	"$managed_panel_helper.real" reset >/dev/null
sleep 2.5
panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume)
[ "$panel_volume" = true ]

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetSet volume false >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume 2>/dev/null || true)
	[ "$panel_volume" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$panel_volume" = false ]
expected=$(printf 'volume\tdisabled')
grep -Fqx "$expected" "$config_home/dwm-titus/panel-widgets.conf"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetsReset >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	panel_volume=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings panelWidgetEnabled volume 2>/dev/null || true)
	[ "$panel_volume" = true ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$panel_volume" = true ]

test_stage='validating desktop personalization Settings lifecycle'
personalization_status=idle
personalization_mutation=idle
i=0
while [ "$i" -lt 100 ]; do
	personalization_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationStatus 2>/dev/null || true)
	personalization_mutation=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationMutationState 2>/dev/null || true)
	case $personalization_status:$personalization_mutation in
	available:available | partial:available) break ;;
	esac
	i=$((i + 1))
	sleep 0.05
done
case $personalization_status:$personalization_mutation in
available:available | partial:available) ;;
*)
	printf 'Desktop personalization did not become mutable: %s / %s\n' \
		"$personalization_status" "$personalization_mutation" >&2
	exit 1
	;;
esac
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_SETTINGS_TEST_THEME_STATUS=$theme_status_fixture \
	DWM_SETTINGS_TEST_APPEARANCE_FAILURE=$appearance_failure_fixture \
	"$data_home/dwm-titus/scripts/dwm-settings-personalization" \
	apply qt gtk3 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	personalization_qt_option=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationOption qt 2>/dev/null || true)
	personalization_qt_value=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationValue qt 2>/dev/null || true)
	[ "$personalization_qt_option" = gtk3 ] && [ "$personalization_qt_value" = gtk3 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$personalization_qt_option" != gtk3 ] || [ "$personalization_qt_value" != gtk3 ]; then
	printf 'Desktop Qt selection did not reach Settings: %s / %s\n' \
		"$personalization_qt_option" "$personalization_qt_value" >&2
	exit 1
fi
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_SETTINGS_TEST_THEME_STATUS=$theme_status_fixture \
	DWM_SETTINGS_TEST_APPEARANCE_FAILURE=$appearance_failure_fixture \
	"$data_home/dwm-titus/scripts/dwm-settings-personalization" \
	reset qt >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	personalization_qt_option=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationOption qt 2>/dev/null || true)
	[ "$personalization_qt_option" = follow-theme ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$personalization_qt_option" != follow-theme ]; then
	printf 'Desktop Qt reset did not return Settings to theme follow: %s\n' \
		"$personalization_qt_option" >&2
	exit 1
fi

test_stage='validating font Settings lifecycle and event-driven shell updates'
font_mutation_ready=false
i=0
while [ "$i" -lt 100 ]; do
	font_mutation_ready=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontMutationReady 2>/dev/null || true)
	[ "$font_mutation_ready" = true ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_mutation_ready" != true ]; then
	printf 'Font mutation readiness did not become available: %s\n' "$font_mutation_ready" >&2
	exit 1
fi
font_candidates=$work/font-candidates
HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	fc-list ':charset=20-7e' --format '%{family[0]}\n' | awk 'NF && !seen[$0]++' >"$font_candidates"
test_font=
while IFS= read -r candidate; do
	resolved=$(HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		fc-match --format '%{family[0]}\n' "$candidate:charset=20-7e" 2>/dev/null || true)
	if [ "$resolved" = "$candidate" ]; then
		test_font=$candidate
		break
	fi
	case $candidate:$resolved in
	'MesloLGS Nerd Font Mono:MesloLGS Nerd Font' | \
		'MesloLGS Nerd Font Mono:MesloLGS NF' | \
		'MesloLGS Nerd Font:MesloLGS Nerd Font Mono' | \
		'MesloLGS Nerd Font:MesloLGS NF' | \
		'MesloLGS NF:MesloLGS Nerd Font Mono' | \
		'MesloLGS NF:MesloLGS Nerd Font')
		test_font=$candidate
		break
		;;
	esac
done <"$font_candidates"
[ -n "$test_font" ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$data_home/dwm-titus/scripts/dwm-settings-font" \
	apply "$test_font" 1.25 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_family=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontFamily 2>/dev/null || true)
	font_scale=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontScale 2>/dev/null || true)
	[ "$font_family" = "$test_font" ] && [ "$font_scale" = 1.25 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_family" != "$test_font" ] || [ "$font_scale" != 1.25 ]; then
	printf 'Font apply did not reach the shell: %s / %s (expected %s / 1.25)\n' \
		"$font_family" "$font_scale" "$test_font" >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$data_home/dwm-titus/scripts/dwm-settings-font" \
	preview nested-font 60 "$test_font" 1.50 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontPreviewState 2>/dev/null || true)
	font_scale=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontScale 2>/dev/null || true)
	[ "$font_preview" = active ] && [ "$font_scale" = 1.50 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_preview" != active ] || [ "$font_scale" != 1.50 ]; then
	printf 'Font preview did not reach the shell: %s / %s\n' "$font_preview" "$font_scale" >&2
	exit 1
fi
font_remaining_before=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontPreviewRemaining)
[ "$font_remaining_before" -gt 0 ]
sleep 1
font_remaining_after=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontPreviewRemaining)
if [ "$font_remaining_after" -ge "$font_remaining_before" ]; then
	printf 'Font preview countdown did not advance: %s -> %s\n' \
		"$font_remaining_before" "$font_remaining_after" >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$data_home/dwm-titus/scripts/dwm-settings-font" revert nested-font >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontPreviewState 2>/dev/null || true)
	font_scale=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontScale 2>/dev/null || true)
	[ "$font_preview" = none ] && [ "$font_scale" = 1.25 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_preview" != none ] || [ "$font_scale" != 1.25 ]; then
	printf 'Font preview revert did not converge: %s / %s\n' "$font_preview" "$font_scale" >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$data_home/dwm-titus/scripts/dwm-settings-font" reset >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_scale=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontScale 2>/dev/null || true)
	[ "$font_scale" = 1.00 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_scale" != 1.00 ]; then
	printf 'Font reset did not restore the managed scale: %s\n' "$font_scale" >&2
	exit 1
fi
# The isolated nested HOME does not inherit user-installed Meslo fonts. Keep
# the fixture on an exact system family after proving reset, so later aggregate
# appearance assertions isolate the state they are intended to test.
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$data_home/dwm-titus/scripts/dwm-settings-font" \
	apply "$test_font" 1.00 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontState 2>/dev/null || true)
	[ "$font_state" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_state" != available ]; then
	printf 'Nested font fixture did not return to an available family: %s\n' "$font_state" >&2
	exit 1
fi

test_stage='validating wallpaper Settings lifecycle and recovery'
test_wallpaper=$home/Pictures/backgrounds/test-wallpaper.png
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$home/Pictures/backgrounds \
	"$data_home/dwm-titus/scripts/dwm-settings-wallpaper" apply "$test_wallpaper" max >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	wallpaper_path=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPath 2>/dev/null || true)
	wallpaper_fit=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperFit 2>/dev/null || true)
	[ "$wallpaper_state" = available ] && [ "$wallpaper_path" = "$test_wallpaper" ] &&
		[ "$wallpaper_fit" = max ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$wallpaper_state" = available ]
[ "$wallpaper_path" = "$test_wallpaper" ]
[ "$wallpaper_fit" = max ]

wallpaper_preview_timeout=60
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$home/Pictures/backgrounds \
	"$data_home/dwm-titus/scripts/dwm-settings-wallpaper" \
	preview nested-wallpaper "$wallpaper_preview_timeout" "$test_wallpaper" center >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewState 2>/dev/null || true)
	[ "$wallpaper_preview" = active ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$wallpaper_preview" = active ]
wallpaper_remaining_before=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewRemaining)
[ "$wallpaper_remaining_before" -gt 0 ]
wallpaper_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMessage)
case $wallpaper_message in
"Wallpaper preview active; keep it within "*" seconds or it will revert") ;;
*)
	printf 'External wallpaper preview message omitted its live deadline: %s\n' \
		"$wallpaper_message" >&2
	exit 1
	;;
esac
wallpaper_message_remaining=${wallpaper_message#*within }
wallpaper_message_remaining=${wallpaper_message_remaining%% seconds*}
sleep 1.2
wallpaper_remaining_after=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewRemaining)
[ "$wallpaper_remaining_after" -lt "$wallpaper_remaining_before" ]
case $wallpaper_message_remaining in
'' | *[!0-9]*)
	printf 'External wallpaper preview message reported an invalid deadline: %s\n' \
		"$wallpaper_message" >&2
	exit 1
	;;
esac
if [ "$wallpaper_message_remaining" -lt "$wallpaper_remaining_before" ] ||
	[ "$wallpaper_message_remaining" -gt "$wallpaper_preview_timeout" ]; then
	printf 'External wallpaper preview message did not match the live deadline: %s (%s -> %s)\n' \
		"$wallpaper_message" "$wallpaper_remaining_before" "$wallpaper_remaining_after" >&2
	exit 1
fi

# A dead watchdog is surfaced as failed by read-only status. The explicit
# Settings recovery action performs writable reconciliation and rearms it.
test_stage='validating wallpaper watchdog reconciliation'
wallpaper_preview_meta=$state_home/dwm-titus/appearance/wallpaper/nested-wallpaper.meta
wallpaper_watchdog_identity=$(awk -F= '
	$1 == "pid" { pid = $2 }
	$1 == "pid_start" { start = $2 }
	END { if (pid != "" && start != "") print pid ":" start }
' "$wallpaper_preview_meta")
if [ -z "$wallpaper_watchdog_identity" ]; then
	printf 'Wallpaper watchdog metadata omitted process identity: %s\n' \
		"$wallpaper_preview_meta" >&2
	exit 1
fi
wallpaper_watchdog_pid=${wallpaper_watchdog_identity%%:*}
if process_identity_alive "$wallpaper_watchdog_identity"; then
	kill -TERM "$wallpaper_watchdog_pid" 2>/dev/null || true
fi
i=0
while [ "$i" -lt 100 ]; do
	! process_identity_alive "$wallpaper_watchdog_identity" && break
	i=$((i + 1))
	sleep 0.05
done
if process_identity_alive "$wallpaper_watchdog_identity"; then
	printf 'Wallpaper watchdog remained active after SIGTERM: %s\n' \
		"$wallpaper_watchdog_identity" >&2
	exit 1
fi
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
# Trigger the independently covered theme-source watcher only after the pane is
# open. This guarantees a post-cleanup snapshot even when CI coalesces the
# integration FileView load with the close/open boundary.
printf '# trigger inactive integration snapshot\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 200 ]; do
	wallpaper_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewState 2>/dev/null || true)
	wallpaper_status_busy=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperStatusBusy 2>/dev/null || true)
	[ "$wallpaper_preview" = failed ] && [ "$wallpaper_status_busy" = false ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_preview" != failed ] || [ "$wallpaper_status_busy" != false ]; then
	printf 'Wallpaper watchdog state did not converge: %s / busy=%s\n' \
		"$wallpaper_preview" "$wallpaper_status_busy" >&2
	exit 1
fi
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperReconcile >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewState 2>/dev/null || true)
	[ "$wallpaper_preview" = active ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$wallpaper_preview" = active ]
wallpaper_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMessage)
if [ "$wallpaper_message" != 'Wallpaper preview recovery reconciled' ]; then
	printf 'Unexpected wallpaper reconcile message: %s\n' "$wallpaper_message" >&2
	exit 1
fi

# A transient read-only status failure must not hide the active transaction or
# its recovery controls while the wallpaper watchdog still owns the preview.
test_stage='validating wallpaper status failure preservation'
: >"$wallpaper_status_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	wallpaper_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperProviderState 2>/dev/null || true)
	wallpaper_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewState 2>/dev/null || true)
	[ "$wallpaper_state" = unavailable ] && [ "$wallpaper_preview" = active ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_state" != unavailable ] || [ "$wallpaper_preview" != active ]; then
	printf 'Wallpaper status failure did not preserve preview: %s / %s\n' \
		"$wallpaper_state" "$wallpaper_preview" >&2
	exit 1
fi
rm -f "$wallpaper_status_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	[ "$wallpaper_state" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_state" != available ]; then
	printf 'Wallpaper status did not recover after fixture removal: %s\n' "$wallpaper_state" >&2
	exit 1
fi
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$home/Pictures/backgrounds \
	"$data_home/dwm-titus/scripts/dwm-settings-wallpaper" revert nested-wallpaper >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	wallpaper_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperPreviewState 2>/dev/null || true)
	[ "$wallpaper_preview" = none ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_preview" != none ]; then
	printf 'Wallpaper preview did not clear after revert: %s\n' "$wallpaper_preview" >&2
	exit 1
fi

test_stage='validating wallpaper missing-file recovery'
rm -f "$test_wallpaper"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	[ "$wallpaper_state" = partial ] && break
	i=$((i + 1))
	sleep 0.05
done
wallpaper_mutation_detail=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperMutationDetail)
wallpaper_reset_ready=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperResetReady)
if [ "$wallpaper_state" != partial ] ||
	[ "$wallpaper_mutation_detail" != 'Wallpaper changes require a recoverable current or default wallpaper' ] ||
	[ "$wallpaper_reset_ready" != true ]; then
	printf 'Unexpected missing wallpaper state/detail/reset: %s / %s / %s\n' \
		"$wallpaper_state" "$wallpaper_mutation_detail" "$wallpaper_reset_ready" >&2
	exit 1
fi
cp "$repo/config/quickshell/assets/ctt_logo.png" "$test_wallpaper"

# Preview and recovery metadata are watched while Appearance is open. An
# external keep or abandon must clear active and failed controls without
# waiting for a theme-file change or a countdown boundary.
transaction_state_file=$state_home/dwm-titus/appearance/integration-transaction
printf '%s\n' external-active >"$theme_status_fixture"
: >"$theme_status_fixture.external"
printf 'active\n' >"$transaction_state_file"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
test_stage='validating appearance provider and inventory state'
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState 2>/dev/null || true)
	[ "$appearance_preview" = active ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_preview" = active ]
rm -f "$theme_status_fixture.external"
rm -f "$transaction_state_file"
i=0
while [ "$i" -lt 100 ]; do
	appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState 2>/dev/null || true)
	[ "$appearance_preview" = none ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_preview" = none ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMessage)" = \
	'Theme preview completed outside Settings' ]

printf '%s\n' external-failed >"$theme_status_fixture"
: >"$theme_status_fixture.external"
printf 'failed\n' >"$transaction_state_file"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState 2>/dev/null || true)
	[ "$appearance_preview" = failed ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_preview" = failed ]
rm -f "$theme_status_fixture.external"
rm -f "$transaction_state_file"
i=0
while [ "$i" -lt 100 ]; do
	appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState 2>/dev/null || true)
	[ "$appearance_preview" = none ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_preview" = none ]
printf '%s\n' none >"$theme_status_fixture"

# A helper that exits silently must clear the last good snapshot instead of
# leaving stale available state visible.
printf '%s\n' silent >"$appearance_failure_fixture"
printf '# trigger silent provider failure\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	appearance_detail=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderDetail 2>/dev/null || true)
	[ "$appearance_status" = unavailable ] &&
		[ "$appearance_detail" = 'Appearance provider failed before returning a valid snapshot' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_status" = unavailable ]
[ "$appearance_detail" = 'Appearance provider failed before returning a valid snapshot' ]
rm -f "$appearance_failure_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	case $appearance_status in available | partial) break ;; esac
	i=$((i + 1))
	sleep 0.05
done
case $appearance_status in available | partial) ;; *) exit 1 ;; esac

# Early provider records from a failed helper are not a complete snapshot.
printf '%s\n' truncated >"$appearance_failure_fixture"
printf '# trigger truncated provider failure\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount 2>/dev/null || true)
	[ "$appearance_status" = unavailable ] && [ "$appearance_count" -eq 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_status" = unavailable ]
[ "$appearance_count" -eq 0 ]
rm -f "$appearance_failure_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	case $appearance_status in available | partial) break ;; esac
	i=$((i + 1))
	sleep 0.05
done
case $appearance_status in available | partial) ;; *) exit 1 ;; esac

# Integration inputs are watched only while Appearance is open. Updating the
# generated environment file must refresh the provider without manual action.
test_stage='validating active appearance integration watches'
printf '%s\n' 'export QT_QPA_PLATFORMTHEME=gtk3' \
	'export XCURSOR_THEME=Adwaita' 'export XCURSOR_SIZE=24' \
	>"$config_home/dwm-titus/theme-env.sh"
i=0
while [ "$i" -lt 100 ]; do
	appearance_qt=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceIntegrationState qt 2>/dev/null || true)
	[ "$appearance_qt" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_qt" = available ]

# Inventory diagnostics for an unused theme remain visible without further
# degrading the aggregate application state. The clean fixture can already be
# partial when optional XSETTINGS verification tools are not installed.
test_stage='validating unused appearance inventory diagnostics'
appearance_application_before=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceApplicationState)
printf '%s\n' inventory-only >"$appearance_failure_fixture"
printf '# trigger inventory-only provider fixture\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	appearance_application=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceApplicationState 2>/dev/null || true)
	appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount 2>/dev/null || true)
	[ "$appearance_status" = partial ] &&
		[ "$appearance_application" = "$appearance_application_before" ] &&
		[ "$appearance_count" -eq 16 ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$appearance_status" != partial ] ||
	[ "$appearance_application" != "$appearance_application_before" ] ||
	[ "$appearance_count" -ne 16 ]; then
	printf 'Inventory-only diagnostics reported provider=%s application=%s themes=%s\n' \
		"$appearance_status" "$appearance_application" "$appearance_count" >&2
	for integration_id in gtk qt cursor alacritty kitty compositor; do
		integration_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
			XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings \
			appearanceIntegrationState "$integration_id" 2>/dev/null || true)
		printf '  %s: %s\n' "$integration_id" "$integration_state" >&2
	done
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime DWM_SETTINGS_TEST_THEME_STATUS=$theme_status_fixture \
		DWM_SETTINGS_TEST_APPEARANCE_FAILURE=$appearance_failure_fixture \
		"$data_home/dwm-titus/scripts/dwm-settings-personalization" status >&2 || true
	exit 1
fi
rm -f "$appearance_failure_fixture"
printf '# restore real provider snapshot\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount 2>/dev/null || true)
	[ "$appearance_count" -eq 15 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_count" -eq 15 ]

baseline_wallpaper_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperProviderState)
baseline_wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState)
baseline_inventory_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryProviderState)
baseline_cursor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState cursor)
baseline_icon_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState icon)
baseline_gtk_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState gtk)
baseline_qt_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState qt)
baseline_compositor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryState compositor)
baseline_gtk_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState gtk)
baseline_qt_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState qt)

# Exercise the combined optional-component loss through the live Settings
# model. The fixture preserves valid versioned provider responses while making
# wallpaper, toolkit assets, Picom, Feh, and delegated editors unavailable.
test_stage='validating combined optional-component loss isolation'
printf '%s\n' optional-loss >"$appearance_failure_fixture"
printf '%s\n' optional-loss >"$wallpaper_status_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	font_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceFontState 2>/dev/null || true)
	desktop_font_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryState font 2>/dev/null || true)
	inventory_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryProviderState 2>/dev/null || true)
	personalization_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationStatus 2>/dev/null || true)
	personalization_mutation=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationMutationState 2>/dev/null || true)
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	wallpaper_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperProviderState 2>/dev/null || true)
	cursor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState cursor 2>/dev/null || true)
	icon_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState icon 2>/dev/null || true)
	gtk_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState gtk 2>/dev/null || true)
	qt_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState qt 2>/dev/null || true)
	compositor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryState compositor 2>/dev/null || true)
	gtk_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState gtk 2>/dev/null || true)
	qt_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState qt 2>/dev/null || true)
	[ "$font_state" = available ] && [ "$desktop_font_state" = available ] &&
		[ "$inventory_provider" = available ] && [ "$personalization_status" = available ] &&
		[ "$personalization_mutation" = available ] && [ "$wallpaper_provider" = partial ] &&
		[ "$wallpaper_state" = unavailable ] &&
		[ "$cursor_state" = unavailable ] && [ "$icon_state" = unavailable ] &&
		[ "$gtk_state" = unavailable ] && [ "$qt_state" = partial ] &&
		[ "$compositor_state" = unavailable ] && [ "$gtk_delegate_state" = unavailable ] &&
		[ "$qt_delegate_state" = unavailable ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$font_state" != available ] || [ "$desktop_font_state" != available ] ||
	[ "$inventory_provider" != available ] || [ "$personalization_status" != available ] ||
	[ "$personalization_mutation" != available ] || [ "$wallpaper_provider" != partial ] ||
	[ "$wallpaper_state" != unavailable ] ||
	[ "$cursor_state" != unavailable ] || [ "$icon_state" != unavailable ] ||
	[ "$gtk_state" != unavailable ] || [ "$qt_state" != partial ] ||
	[ "$compositor_state" != unavailable ] || [ "$gtk_delegate_state" != unavailable ] ||
	[ "$qt_delegate_state" != unavailable ]; then
	printf 'Combined optional loss did not remain capability-scoped: %s / %s / %s / %s / %s / %s / %s / %s / %s / %s / %s / %s / %s / %s\n' \
		"$font_state" "$desktop_font_state" "$inventory_provider" "$personalization_status" \
		"$personalization_mutation" "$wallpaper_provider" \
		"$wallpaper_state" "$cursor_state" "$icon_state" "$gtk_state" "$qt_state" \
		"$compositor_state" "$gtk_delegate_state" "$qt_delegate_state" >&2
	exit 1
fi
process_identity_alive "$quickshell_identity"
rm -f "$appearance_failure_fixture" "$wallpaper_status_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	wallpaper_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperProviderState 2>/dev/null || true)
	wallpaper_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceWallpaperState 2>/dev/null || true)
	inventory_provider=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryProviderState 2>/dev/null || true)
	cursor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState cursor 2>/dev/null || true)
	icon_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState icon 2>/dev/null || true)
	gtk_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState gtk 2>/dev/null || true)
	qt_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationEffectiveState qt 2>/dev/null || true)
	compositor_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceInventoryState compositor 2>/dev/null || true)
	gtk_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState gtk 2>/dev/null || true)
	qt_delegate_state=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePersonalizationDelegateState qt 2>/dev/null || true)
	[ "$wallpaper_provider" = "$baseline_wallpaper_provider" ] &&
		[ "$wallpaper_state" = "$baseline_wallpaper_state" ] &&
		[ "$inventory_provider" = "$baseline_inventory_provider" ] &&
		[ "$cursor_state" = "$baseline_cursor_state" ] &&
		[ "$icon_state" = "$baseline_icon_state" ] &&
		[ "$gtk_state" = "$baseline_gtk_state" ] && [ "$qt_state" = "$baseline_qt_state" ] &&
		[ "$compositor_state" = "$baseline_compositor_state" ] &&
		[ "$gtk_delegate_state" = "$baseline_gtk_delegate_state" ] &&
		[ "$qt_delegate_state" = "$baseline_qt_delegate_state" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$wallpaper_provider" != "$baseline_wallpaper_provider" ] ||
	[ "$wallpaper_state" != "$baseline_wallpaper_state" ] ||
	[ "$inventory_provider" != "$baseline_inventory_provider" ] ||
	[ "$cursor_state" != "$baseline_cursor_state" ] || [ "$icon_state" != "$baseline_icon_state" ] ||
	[ "$gtk_state" != "$baseline_gtk_state" ] || [ "$qt_state" != "$baseline_qt_state" ] ||
	[ "$compositor_state" != "$baseline_compositor_state" ] ||
	[ "$gtk_delegate_state" != "$baseline_gtk_delegate_state" ] ||
	[ "$qt_delegate_state" != "$baseline_qt_delegate_state" ]; then
	printf 'Optional loss did not recover to baseline: %s / %s / %s / %s / %s / %s / %s / %s / %s / %s\n' \
		"$wallpaper_provider" "$wallpaper_state" "$inventory_provider" "$cursor_state" \
		"$icon_state" "$gtk_state" "$qt_state" "$compositor_state" \
		"$gtk_delegate_state" "$qt_delegate_state" >&2
	exit 1
fi

test_stage='validating restored appearance integration state'
printf '# inactive integration watch fixture\n' >"$config_home/dwm-titus/theme-env.sh"
# The active-file assertion above covers the integration watcher. Reopen the
# pane for cleanup so this restoration is a fresh generation-scoped snapshot,
# not a second file event that can be coalesced with the provider-fixture edge.
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_qt=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceIntegrationState qt 2>/dev/null || true)
	[ "$appearance_qt" = unavailable ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$appearance_qt" != unavailable ]; then
	printf 'Restored Qt integration state remained %s\n' "$appearance_qt" >&2
	exit 1
fi

# Invalid selected labels are diagnostic provider output. Keep the valid
# fallback inventory available so Settings can offer recovery.
test_stage='validating appearance recovery inventory'
cp "$config_home/dwm-titus/themes.toml" "$work/valid-themes.toml"
sed -i '0,/theme = "nord"/s//theme = "missing theme"/' \
	"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_theme=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme 2>/dev/null || true)
	appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount 2>/dev/null || true)
	[ "$appearance_theme" = 'missing theme' ] && [ "$appearance_count" -eq 15 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_theme" = 'missing theme' ]
[ "$appearance_count" -eq 15 ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus)" = partial ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceApplicationState)" = partial ]
cp "$work/valid-themes.toml" "$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_theme=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme 2>/dev/null || true)
	[ "$appearance_theme" = nord ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_theme" = nord ]

# Invalid dark-mode metadata remains visible in the inventory and uses the
# provider's safe dark default instead of dropping the active row.
test_stage='validating appearance metadata recovery'
sed -i '0,/dark_mode       = true/s//dark_mode       = "bogus"/' \
	"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	appearance_count=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount 2>/dev/null || true)
	[ "$appearance_status" = partial ] && [ "$appearance_count" -eq 15 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_status" = partial ]
[ "$appearance_count" -eq 15 ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme)" = nord ]
cp "$work/valid-themes.toml" "$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	case $appearance_status in available | partial) break ;; esac
	i=$((i + 1))
	sleep 0.05
done

printf '%s\n' active-zero >"$theme_status_fixture"
test_stage='validating appearance preview completion'
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	appearance_preview=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewState 2>/dev/null || true)
	appearance_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMessage 2>/dev/null || true)
	[ "$appearance_preview" = none ] &&
		[ "$appearance_message" = 'Theme preview completed outside Settings' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_preview" = none ]
[ "$appearance_message" = 'Theme preview completed outside Settings' ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearancePreviewRemaining)" -eq 0 ]

# A broken status helper after the rollback boundary is retried only a bounded
# number of times instead of creating a permanent subprocess loop.
test_stage='validating bounded appearance preview retries'
rm -f "$theme_status_fixture.started" "$theme_status_fixture.calls"
printf '%s\n' none >"$theme_status_fixture"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select audio >/dev/null
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings select appearance >/dev/null
# Let pane-open provider and watcher setup settle before isolating the retry
# fixture. Otherwise unrelated initial refreshes are counted as retry work.
sleep 1
rm -f "$theme_status_fixture.started" "$theme_status_fixture.calls"
printf '%s\n' active-zero-fail >"$theme_status_fixture"
printf '# trigger bounded preview retry fixture\n' >>"$config_home/dwm-titus/themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_message=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMessage 2>/dev/null || true)
	[ "$appearance_message" = 'Automatic rollback status needs a manual refresh' ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ "$appearance_message" != 'Automatic rollback status needs a manual refresh' ]; then
	printf 'Bounded appearance retry message did not converge: %s\n' \
		"$appearance_message" >&2
	exit 1
fi
# The warning can be published while one already-scheduled final probe is
# still starting. Let that bounded probe settle before proving retries stop.
sleep 0.75
preview_status_calls=$(wc -c <"$theme_status_fixture.calls")
sleep 0.75
preview_status_calls_after=$(wc -c <"$theme_status_fixture.calls")
if [ "$preview_status_calls_after" -ne "$preview_status_calls" ]; then
	printf 'Appearance preview retries continued after convergence: %s -> %s calls\n' \
		"$preview_status_calls" "$preview_status_calls_after" >&2
	exit 1
fi
if [ "$preview_status_calls" -gt 6 ]; then
	printf 'Appearance preview retries exceeded the bound: %s calls\n' \
		"$preview_status_calls" >&2
	exit 1
fi
rm -f "$theme_status_fixture.started" "$theme_status_fixture.calls"
printf '%s\n' none >"$theme_status_fixture"

# The provider's missing-source and legacy identifiers are intentional
# read-only protocol sentinels, not mutation-safe theme names.
mv "$config_home/dwm-titus/themes.toml" "$work/named-themes.toml"
mv "$data_home/dwm-titus/config/themes.toml" "$work/managed-themes.toml"
i=0
while [ "$i" -lt 100 ]; do
	appearance_status=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus 2>/dev/null || true)
	appearance_detail=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderDetail 2>/dev/null || true)
	[ "$appearance_status" = unavailable ] &&
		[ "$appearance_detail" = 'Shared theme inventory and integration state' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_status" = unavailable ]
[ "$appearance_detail" = 'Shared theme inventory and integration state' ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceMutationReady)" = false ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme)" = none ]

cat >"$config_home/dwm-titus/themes.toml" <<'EOF'
[colors]
normfgcolor = "#D8DEE9"
normbgcolor = "#2E3440"
normbordercolor = "#4C566A"
selfgcolor = "#ECEFF4"
selbgcolor = "#5E81AC"
selbordercolor = "#81A1C1"
EOF
i=0
while [ "$i" -lt 100 ]; do
	appearance_theme=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceActiveTheme 2>/dev/null || true)
	[ "$appearance_theme" = @legacy-colors ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$appearance_theme" = @legacy-colors ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceProviderStatus)" = partial ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call settings appearanceThemeCount)" -eq 1 ]

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
