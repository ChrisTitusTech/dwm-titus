#!/bin/sh
set -eu

test_repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
repo=${DWM_LARGE_SURFACE_REPO:-$test_repo}

for command_name in Xvfb quickshell xdotool xprop getconf; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "$(id -u)" -eq 0 ] && [ "${DWM_LARGE_SURFACE_UNPRIVILEGED:-0}" != 1 ]; then
	command -v setpriv >/dev/null 2>&1 || {
		printf 'Quickshell large-surface Xvfb requires setpriv on a root runner\n' >&2
		exit 1
	}
	unprivileged_uid=$(id -u nobody)
	unprivileged_gid=$(id -g nobody)
	root_runner_work=$(mktemp -d /var/tmp/dwm-large-surface-root.XXXXXX)
	trap 'rm -rf -- "$root_runner_work"' EXIT
	fixture_repo=$root_runner_work/repo
	mkdir -p "$root_runner_work/cache" "$root_runner_work/config" \
		"$root_runner_work/data" "$root_runner_work/runtime" \
		"$root_runner_work/state" "$fixture_repo/tests"
	cp -a "$test_repo/config" "$test_repo/scripts" "$fixture_repo/"
	cp "$test_repo/dwm" "$fixture_repo/dwm"
	cp "$0" "$fixture_repo/tests/test-quickshell-large-surfaces-xvfb.sh"
	chown -R "$unprivileged_uid:$unprivileged_gid" "$root_runner_work"
	chmod 700 "$fixture_repo/dwm" "$root_runner_work/runtime"
	if HOME="$root_runner_work" TMPDIR="$root_runner_work" \
		DWM_LARGE_SURFACE_REPO="$fixture_repo" \
		DWM_LARGE_SURFACE_UNPRIVILEGED=1 \
		XDG_CACHE_HOME="$root_runner_work/cache" \
		XDG_CONFIG_HOME="$root_runner_work/config" \
		XDG_DATA_HOME="$root_runner_work/data" \
		XDG_RUNTIME_DIR="$root_runner_work/runtime" \
		XDG_STATE_HOME="$root_runner_work/state" \
		setpriv --reuid "$unprivileged_uid" --regid "$unprivileged_gid" \
		--clear-groups "$fixture_repo/tests/test-quickshell-large-surfaces-xvfb.sh" "$@"; then
		root_runner_status=0
	else
		root_runner_status=$?
	fi
	rm -rf -- "$root_runner_work"
	trap - EXIT
	exit "$root_runner_status"
fi

if [ "${DWM_LARGE_SURFACE_DBUS_SESSION:-0}" != 1 ]; then
	if ! command -v dbus-run-session >/dev/null 2>&1; then
		printf 'SKIP: dbus-run-session is unavailable\n'
		exit 77
	fi
	exec env DWM_LARGE_SURFACE_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 300) + 1100))"
runtime_alias_dir=
test_stage='initializing fixture'
cleanup() {
	cleanup_status=$?
	set +e
	if [ "$cleanup_status" -ne 0 ]; then
		printf 'Large-surface Xvfb failed while %s (status %s)\n' \
			"${test_stage:-stage unknown}" "$cleanup_status" >&2
		[ ! -f "$work/quickshell.log" ] || tail -80 "$work/quickshell.log" >&2
		[ ! -f "$work/dwm.log" ] || tail -40 "$work/dwm.log" >&2
	fi
	[ -n "${quickshell_pid:-}" ] && kill "$quickshell_pid" 2>/dev/null
	[ -n "${dwm_pid:-}" ] && kill "$dwm_pid" 2>/dev/null
	[ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null
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
runtime_storage=$work/runtime
runtime=$runtime_storage
config_home=$home/.config
data_home=$home/.local/share
bin=$work/bin
mkdir -p "$config_home/quickshell" "$config_home/dwm-titus" "$home/.cache" \
	"$data_home/dwm-titus/scripts" "$data_home/applications" "$runtime" "$bin"
chmod 700 "$runtime_storage"
if [ "${#runtime}" -gt 64 ]; then
	runtime_alias_dir=$(mktemp -d /tmp/dwm-large-surface-runtime.XXXXXX)
	ln -s "$runtime_storage" "$runtime_alias_dir/runtime"
	runtime=$runtime_alias_dir/runtime
fi
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
	urgency=${1:-normal}
	summary=${2:-Nested notification}
	if [ "${DWM_LARGE_SURFACE_FORCE_DBUS_SEND:-0}" != 1 ] &&
		command -v notify-send >/dev/null 2>&1; then
		DISPLAY=$display HOME=$home XDG_CACHE_HOME=$home/.cache XDG_RUNTIME_DIR=$runtime notify-send \
			--app-name='Large Surface Test' --urgency="$urgency" \
			"$summary" 'Pointer dismissal and history fixture'
		return
	fi
	if [ "$urgency" = critical ]; then
		printf 'SKIP: notify-send is required for critical notification validation\n'
		exit 77
	fi

	if ! command -v dbus-send >/dev/null 2>&1; then
		printf 'SKIP: dbus-send is unavailable and notify-send cannot be used\n'
		exit 77
	fi
	DISPLAY=$display HOME=$home XDG_CACHE_HOME=$home/.cache XDG_RUNTIME_DIR=$runtime \
		dbus-send --session --print-reply --dest=org.freedesktop.Notifications \
		/org/freedesktop/Notifications org.freedesktop.Notifications.Notify \
		string:'Large Surface Test' uint32:0 string:'' string:"$summary" \
		string:'Pointer dismissal and history fixture' array:string: dict:string:variant: int32:6000 >/dev/null
}

test_stage='waiting for launcher IPC'
i=0
while [ "$i" -lt 200 ]; do
	ipc launcher open >/dev/null 2>&1 && break
	i=$((i + 1))
	sleep 0.05
done
launcher_window=$(wait_window '^dwm launcher$')
test_stage='validating launcher interactions'
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
test_stage='validating Settings surface'
settings_window=$(wait_window '^dwm settings$')
capture_window settings "$settings_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc settings close >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$settings_window"
	DISPLAY=$display xdotool key Down
	i=0
	section=
	while [ "$i" -lt 100 ]; do
		section=$(ipc settings currentSection 2>/dev/null || true)
		[ "$section" = input ] && break
		i=$((i + 1))
		sleep 0.05
	done
	[ "$section" = input ]
	DISPLAY=$display xdotool key Escape
fi

ipc systemhealth open >/dev/null
test_stage='validating System Health surface'
health_window=$(wait_window '^dwm system health$')
DISPLAY=$display xprop -id "$health_window" _NET_WM_STATE | grep -q '_NET_WM_STATE_FULLSCREEN'
capture_window system-health "$health_window"
if [ "${DWM_LARGE_SURFACE_CAPTURE_ONLY:-0}" = 1 ]; then
	ipc systemhealth close >/dev/null
else
	DISPLAY=$display xdotool windowactivate --sync "$health_window"
	DISPLAY=$display xdotool key Escape
fi

test_stage='validating notifications'
i=0
while [ "$i" -lt 100 ]; do
	policy_state=$(ipc notifications policyState)
	case $policy_state in available | defaults | partial) break ;; esac
	i=$((i + 1))
	sleep 0.05
done
case $policy_state in
available | defaults | partial) ;;
*)
	printf 'Notification policy did not load: %s\n' "$policy_state" >&2
	exit 1
	;;
esac
ipc notifications resetPolicy >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
policy_state=$(ipc notifications policyState)
if [ "$policy_state" != available ]; then
	printf 'Notification policy reset did not save: %s\n' "$policy_state" >&2
	exit 1
fi
ipc notifications clearHistory >/dev/null
send_test_notification
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications count)" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
ipc notifications setPopupTimeout 4000 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
popup_timeout=$(ipc notifications popupTimeout)
if [ "$popup_timeout" != 4000 ]; then
	printf 'Notification popup timeout did not update: %s\n' "$popup_timeout" >&2
	exit 1
fi
if ! grep -Eq '"popupTimeoutMs"[[:space:]]*:[[:space:]]*4000' \
	"$config_home/dwm-titus/notification-settings.json"; then
	printf 'Notification popup timeout was not persisted:\n' >&2
	sed -n '1,20p' "$config_home/dwm-titus/notification-settings.json" >&2
	exit 1
fi
# FileView does not define whether saved or fileChanged arrives first. Sample a
# bounded post-save window so either ordering must keep the popup available.
i=0
while [ "$i" -lt 20 ]; do
	[ "$(ipc notifications policyState)" = available ]
	[ "$(ipc notifications count)" -gt 0 ]
	i=$((i + 1))
	sleep 0.05
done
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
ipc notifications setDoNotDisturb true >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications doNotDisturb)" = true ]
chmod 500 "$config_home/dwm-titus"
ipc notifications setDoNotDisturb false >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = unavailable ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = unavailable ]
[ "$(ipc notifications doNotDisturb)" = true ]
[ "$(ipc notifications popupTimeout)" = 4000 ]
chmod 700 "$config_home/dwm-titus"
ipc notifications resetPolicy >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = available ]
[ "$(ipc notifications doNotDisturb)" = false ]
[ "$(ipc notifications popupTimeout)" = 6000 ]
ipc notifications setPopupTimeout 4000 >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = available ]
ipc notifications setDoNotDisturb true >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = available ]
[ "$(ipc notifications doNotDisturb)" = true ]
[ "$(ipc notifications popupTimeout)" = 4000 ]
chmod 000 "$config_home/dwm-titus/notification-settings.json"
touch "$config_home/dwm-titus/notification-settings.json"
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = unavailable ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = unavailable ]
[ "$(ipc notifications doNotDisturb)" = true ]
[ "$(ipc notifications popupTimeout)" = 4000 ]
send_test_notification normal 'Suppressed during policy read failure'
sleep 0.1
[ "$(ipc notifications count)" = 0 ]
[ "$(ipc notifications historyLatestSummary)" = 'Suppressed during policy read failure' ]
chmod 600 "$config_home/dwm-titus/notification-settings.json"
touch "$config_home/dwm-titus/notification-settings.json"
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = available ]
ipc notifications resetPolicy >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications doNotDisturb)" = false ]
[ "$(ipc notifications popupTimeout)" = 6000 ]
printf '%s\n' '{"version":1,"doNotDisturb":true,"popupTimeoutMs":6000}' \
	>"$config_home/dwm-titus/notification-settings.json"
i=0
while [ "$i" -lt 100 ]; do
	policy_dnd=$(ipc notifications doNotDisturb)
	[ "$policy_dnd" = true ] && [ "$(ipc notifications count)" = 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$policy_dnd" = true ]
[ "$(ipc notifications count)" = 0 ]
[ "$(ipc notifications historyCount)" -gt 0 ]
printf '%s\n' '{malformed' >"$config_home/dwm-titus/notification-settings.json"
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = partial ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications policyState)" = partial ]
send_test_notification normal 'Suppressed with malformed policy'
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications historyLatestSummary)" = 'Suppressed with malformed policy' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications historyLatestSummary)" = 'Suppressed with malformed policy' ]
[ "$(ipc notifications count)" = 0 ]
ipc notifications resetPolicy >/dev/null
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications policyState)" = available ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications doNotDisturb)" = false ]
ipc notifications clear >/dev/null
[ "$(ipc notifications count)" = 0 ]

test_stage='validating Do Not Disturb history and urgency'
history_before=$(ipc notifications historyCount)
ipc notifications setDoNotDisturb true >/dev/null
[ "$(ipc notifications doNotDisturb)" = true ]
send_test_notification normal 'Suppressed notification'
i=0
while [ "$i" -lt 100 ]; do
	history_after=$(ipc notifications historyCount)
	latest_summary=$(ipc notifications historyLatestSummary)
	[ "$history_after" -gt "$history_before" ] &&
		[ "$latest_summary" = 'Suppressed notification' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$history_after" -gt "$history_before" ]
[ "$latest_summary" = 'Suppressed notification' ]
[ "$(ipc notifications count)" = 0 ]

send_test_notification critical 'Critical notification'
i=0
while [ "$i" -lt 100 ]; do
	[ "$(ipc notifications count)" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$(ipc notifications count)" -gt 0 ]
[ "$(ipc notifications historyLatestSummary)" = 'Critical notification' ]
ipc notifications clear >/dev/null
ipc notifications resetPolicy >/dev/null

test_stage='sampling closed-shell CPU usage'
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
