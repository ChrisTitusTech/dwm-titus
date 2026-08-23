#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
helper=$repo/scripts/dwm-quickshell-controlcenter
model=$repo/config/quickshell/power/PowerMenuModel.qml
window=$repo/config/quickshell/power/PowerMenuWindow.qml
commands=$repo/config/quickshell/core/Commands.qml
work=$(mktemp -d)
test_pids=

forget_test_pid() {
	forgotten_pid=$1
	remaining_pids=
	for recorded_pid in $test_pids; do
		[ "$recorded_pid" = "$forgotten_pid" ] || remaining_pids="$remaining_pids $recorded_pid"
	done
	test_pids=$remaining_pids
}

cleanup() {
	set +e
	for test_pid in $test_pids; do
		kill -TERM "$test_pid" 2>/dev/null || :
		wait "$test_pid" 2>/dev/null || :
	done
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home" "$work/config"
: >"$work/systemctl.log"
: >"$work/xprop-details.count"

cat >"$work/dwm-fixture.c" <<'C'
#define _POSIX_C_SOURCE 200809L

#include <signal.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void
stop(int signal_number)
{
	(void)signal_number;
	running = 0;
}

int
main(void)
{
	signal(SIGUSR2, stop);
	while (running)
		pause();
	return 0;
}
C
"${CC:-cc}" -std=c99 -Wall -Wextra -Werror -o "$work/dwm-fixture" "$work/dwm-fixture.c"

cat >"$work/bin/systemctl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"${DWM_SESSION_TEST_SYSTEMCTL_LOG:?}"
exit "${DWM_SESSION_TEST_SYSTEMCTL_STATUS:-0}"
SH

cat >"$work/bin/xprop" <<'SH'
#!/bin/sh
case ${1:-} in
-root)
	if [ "${DWM_SESSION_TEST_XPROP_MODE:-}" = malformed-root ]; then
		printf '%s\n' '_NET_SUPPORTING_WM_CHECK(WINDOW): malformed'
	else
		printf '%s\n' '_NET_SUPPORTING_WM_CHECK(WINDOW): window id # 0x40001f'
	fi
	;;
-id)
	count=0
	[ ! -r "${DWM_SESSION_TEST_XPROP_COUNT:?}" ] ||
		count=$(cat "${DWM_SESSION_TEST_XPROP_COUNT:?}")
	count=$((count + 1))
	printf '%s\n' "$count" >"${DWM_SESSION_TEST_XPROP_COUNT:?}"
	pid=${DWM_SESSION_TEST_DWM_PID:?}
	if [ "$count" -ge 2 ] && [ -n "${DWM_SESSION_TEST_SECOND_PID:-}" ]; then
		pid=$DWM_SESSION_TEST_SECOND_PID
	fi
	case ${DWM_SESSION_TEST_XPROP_MODE:-} in
	wrong-self) self=0x400020 ;;
	*) self=0x40001f ;;
	esac
	printf '_NET_SUPPORTING_WM_CHECK(WINDOW): window id # %s\n' "$self"
	if [ "${DWM_SESSION_TEST_XPROP_MODE:-}" = wrong-name ]; then
		printf '%s\n' '_NET_WM_NAME(UTF8_STRING) = "other-wm"'
	else
		printf '%s\n' '_NET_WM_NAME(UTF8_STRING) = "dwm"'
	fi
	if [ "${DWM_SESSION_TEST_XPROP_MODE:-}" != missing-pid ]; then
		printf '_NET_WM_PID(CARDINAL) = %s\n' "$pid"
	fi
	;;
*) exit 2 ;;
esac
SH

cat >"$work/bin/stat" <<'SH'
#!/bin/sh
if [ "${1:-}" = -c ] && [ "${2:-}" = %u ]; then
	if [ -n "${DWM_SESSION_TEST_STAT_UID:-}" ]; then
		printf '%s\n' "$DWM_SESSION_TEST_STAT_UID"
		exit 0
	else
		exec /usr/bin/stat "$@"
	fi
fi
exec /usr/bin/stat "$@"
SH

cat >"$work/bin/locker-fixture" <<'SH'
#!/bin/sh
[ "${DWM_SESSION_TEST_LOCK_SUCCESS:-0}" = 1 ]
SH

for locker in light-locker-command xdg-screensaver mate-screensaver-command \
	xfce4-screensaver-command cinnamon-screensaver-command \
	gnome-screensaver-command i3lock slock xlock; do
	cp "$work/bin/locker-fixture" "$work/bin/$locker"
done
chmod +x "$work/bin/"*

run_helper() {
	HOME="$work/home" \
		XDG_CONFIG_HOME="$work/config" \
		DWM_LOCK_NO_LOGINCTL=1 \
		DWM_SESSION_TEST_SYSTEMCTL_LOG="$work/systemctl.log" \
		DWM_SESSION_TEST_XPROP_COUNT="$work/xprop-details.count" \
		DISPLAY=:99 \
		PATH="$work/bin:/usr/bin:/bin" \
		"$helper" "$@"
}

expect_status() {
	expected=$1
	shift
	set +e
	"$@" >"$work/action.out" 2>"$work/action.err"
	status=$?
	set -e
	[ "$status" -eq "$expected" ]
}

expect_failure_without_success() {
	expect_status "$@"
	if grep -Fq 'session-action' "$work/action.out"; then
		printf '%s\n' 'Failed session action emitted a success record.' >&2
		exit 1
	fi
}

process_running() {
	pid=$1
	[ -r "/proc/$pid/stat" ] || return 1
	state=$(awk '{ sub(/^.*\) /, ""); print $1 }' "/proc/$pid/stat" 2>/dev/null) || return 1
	[ "$state" != Z ]
}

start_dwm_fixture() {
	runtime_dir=$work/$1
	mkdir -p "$runtime_dir"
	cp "$work/dwm-fixture" "$runtime_dir/dwm"
	"$runtime_dir/dwm" &
	fixture_pid=$!
	test_pids="$test_pids $fixture_pid"
}

# The model owns a fixed allowlist, strict completion, origin attribution, and
# one root-owned process. No row carries a command or shell fragment.
for action in lock logout suspend reboot shutdown; do
	grep -Fq "\"id\": \"$action\"" "$model"
done
[ "$(grep -Fc 'Process {' "$model")" -eq 1 ]
grep -Fq 'property string actionOrigin: ""' "$model"
grep -Fq 'property string confirmationOrigin: ""' "$model"
grep -Fq 'function messageSeverityFor(origin)' "$model"
grep -Fq 'root.rejectionOrigin === source && root.rejectionMessage.length > 0' "$model"
grep -Fq 'if (root.busy || actionProcess.running)' "$model"
grep -Fq 'this.text.trim() === actionProcess.expectedResult' "$model"
grep -Fq 'actionProcess.command = Commands.checkedCommand(' "$model"
grep -Fq 'Commands.sessionActionCommand(requestedAction.id));' "$model"
grep -Fq 'function clearRejectionFor(origin)' "$model"
request_action_block=$(sed -n '/function requestAction(action, origin)/,/function cancelConfirmation(origin)/p' "$model")
if grep -Fq 'root.actionSucceeded = false' <<EOF; then
$request_action_block
EOF
	printf '%s\n' 'Session-action rejection paths must not mutate another action result.' >&2
	exit 1
fi
if grep -Eq '"command"[[:space:]]*:' "$model"; then
	printf '%s\n' 'Session action rows must not carry commands.' >&2
	exit 1
fi
grep -Fq 'function sessionActionCommand(action)' "$commands"
grep -Fq 'powerHelperCommand("session-action", [action])' "$commands"
grep -Fq 'enabled: !root.powerMenuModel.busy' "$window"
grep -Fq 'root.powerMenuModel.requestAction(modelData, root.actionOrigin)' "$window"
grep -Fq 'readonly property bool ownsConfirmation: powerMenuModel.confirming' "$window"
grep -Fq 'powerMenuModel.confirmationOrigin === actionOrigin' "$window"
grep -Fq 'readonly property bool foreignConfirmation: powerMenuModel.confirming && !ownsConfirmation' "$window"
grep -Fq 'if (root.ownsConfirmation)' "$window"
grep -Fq 'visible: root.ownsConfirmation' "$window"
grep -Fq 'visible: !root.ownsConfirmation' "$window"
grep -Fq '&& !root.foreignConfirmation' "$window"
grep -Fq 'readonly property bool foreignSessionConfirmation: powerMenuModel.confirming' \
	"$repo/config/quickshell/settings/PowerSettingsPane.qml"
grep -Fq 'Another surface is awaiting confirmation for a session action' \
	"$repo/config/quickshell/settings/PowerSettingsPane.qml"

# Every destructive operation is delegated through one fixed systemctl verb.
for specification in 'suspend suspend' 'reboot reboot' 'shutdown poweroff'; do
	action=${specification%% *}
	systemctl_action=${specification#* }
	: >"$work/systemctl.log"
	result=$(run_helper session-action "$action")
	expected=$(printf 'session-action\t%s\taccepted' "$action")
	[ "$result" = "$expected" ]
	grep -Fqx -- "--no-block $systemctl_action" "$work/systemctl.log"
done

export DWM_SESSION_TEST_SYSTEMCTL_STATUS=1
expect_failure_without_success 1 run_helper session-action suspend
grep -Fq 'denied or could not be accepted' "$work/action.err"
unset DWM_SESSION_TEST_SYSTEMCTL_STATUS
expect_failure_without_success 2 run_helper session-action unknown
expect_failure_without_success 2 run_helper session-action
expect_failure_without_success 2 run_helper session-action lock extra

# Lock reports success only after the managed locker accepts the request.
export DWM_SESSION_TEST_LOCK_SUCCESS=1
[ "$(run_helper session-action lock)" = 'session-action	lock	accepted' ]
unset DWM_SESSION_TEST_LOCK_SUCCESS
expect_failure_without_success 1 run_helper session-action lock
grep -Fq 'no usable screen locker found' "$work/action.err"

# A verified current DWM receives SIGUSR2; another same-name process survives.
start_dwm_fixture target
target_pid=$fixture_pid
start_dwm_fixture unrelated
other_pid=$fixture_pid
: >"$work/xprop-details.count"
export DWM_SESSION_TEST_DWM_PID=$target_pid
[ "$(run_helper session-action logout)" = 'session-action	logout	accepted' ]
i=0
while process_running "$target_pid" && [ "$i" -lt 50 ]; do
	i=$((i + 1))
	sleep 0.01
done
if process_running "$target_pid"; then
	printf '%s\n' 'Verified DWM did not receive the graceful logout signal.' >&2
	exit 1
fi
wait "$target_pid" 2>/dev/null || :
forget_test_pid "$target_pid"
process_running "$other_pid"

# Missing/forged X11 ownership and unverified processes fail without signaling.
for mode in malformed-root wrong-self wrong-name missing-pid; do
	start_dwm_fixture "invalid-$mode"
	candidate_pid=$fixture_pid
	: >"$work/xprop-details.count"
	export DWM_SESSION_TEST_DWM_PID=$candidate_pid
	export DWM_SESSION_TEST_XPROP_MODE=$mode
	expect_failure_without_success 1 run_helper session-action logout
	process_running "$candidate_pid"
done
unset DWM_SESSION_TEST_XPROP_MODE

/usr/bin/sleep 30 &
wrong_exe_pid=$!
test_pids="$test_pids $wrong_exe_pid"
: >"$work/xprop-details.count"
export DWM_SESSION_TEST_DWM_PID=$wrong_exe_pid
expect_failure_without_success 1 run_helper session-action logout
process_running "$wrong_exe_pid"

start_dwm_fixture wrong-uid
candidate_pid=$fixture_pid
: >"$work/xprop-details.count"
export DWM_SESSION_TEST_DWM_PID=$candidate_pid
export DWM_SESSION_TEST_STAT_UID=$(($(id -u) + 1))
expect_failure_without_success 1 run_helper session-action logout
process_running "$candidate_pid"
unset DWM_SESSION_TEST_STAT_UID

# A concurrent current-WM replacement is not folded into the captured cohort.
start_dwm_fixture first-owner
first_pid=$fixture_pid
start_dwm_fixture replacement-owner
second_pid=$fixture_pid
: >"$work/xprop-details.count"
export DWM_SESSION_TEST_DWM_PID=$first_pid
export DWM_SESSION_TEST_SECOND_PID=$second_pid
expect_failure_without_success 1 run_helper session-action logout
process_running "$first_pid"
process_running "$second_pid"
unset DWM_SESSION_TEST_SECOND_PID

# A running installed DWM whose inode was replaced remains a valid endpoint.
start_dwm_fixture deleted-owner
deleted_pid=$fixture_pid
rm "$work/deleted-owner/dwm"
: >"$work/xprop-details.count"
export DWM_SESSION_TEST_DWM_PID=$deleted_pid
[ "$(run_helper session-action logout)" = 'session-action	logout	accepted' ]
wait "$deleted_pid" 2>/dev/null || :
forget_test_pid "$deleted_pid"

# Exercise the real EWMH property and graceful main-loop exit when nested X11
# is available. The task-local autostop marker proves the normal exit path ran.
if command -v Xvfb >/dev/null 2>&1 && [ -x "$repo/dwm" ]; then
	runtime_display_number=$((200 + $$ % 3000))
	while [ -e "/tmp/.X11-unix/X$runtime_display_number" ]; do
		runtime_display_number=$((runtime_display_number + 1))
	done
	runtime_display=:$runtime_display_number
	runtime_home=$work/runtime-home
	runtime_data_home=$runtime_home/.local/share
	runtime_config_home=$runtime_home/.config
	mkdir -p "$runtime_data_home/dwm-titus/scripts" \
		"$runtime_data_home/dwm-titus/config" "$runtime_config_home/dwm-titus"
	cp "$repo/config/hotkeys.toml" "$repo/config/themes.toml" \
		"$repo/config/window-rules.toml" "$runtime_data_home/dwm-titus/config/"
	cat >"$runtime_data_home/dwm-titus/scripts/autostart.sh" <<'SH'
#!/bin/sh
exit 0
SH
	cat >"$runtime_data_home/dwm-titus/scripts/autostop.sh" <<'SH'
#!/bin/sh
: >"${DWM_SESSION_TEST_AUTOSTOP_MARKER:?}"
SH
	cat >"$runtime_data_home/dwm-titus/scripts/theme-apply.sh" <<'SH'
#!/bin/sh
printf x >>"${DWM_SESSION_TEST_THEME_APPLY_MARKER:?}"
printf '%s\n%s\n' "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" \
	>"${DWM_SESSION_TEST_THEME_ENV_MARKER:?}"
SH
	chmod +x "$runtime_data_home/dwm-titus/scripts/"*.sh

	Xvfb "$runtime_display" -screen 0 800x600x24 -nolisten tcp \
		>"$work/xvfb.log" 2>&1 &
	xvfb_pid=$!
	test_pids="$test_pids $xvfb_pid"
	i=0
	while ! DISPLAY=$runtime_display /usr/bin/xprop -root >/dev/null 2>&1; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || {
			printf '%s\n' 'Nested X11 server did not become ready.' >&2
			exit 1
		}
		sleep 0.02
	done

	DWM_SESSION_TEST_AUTOSTOP_MARKER="$work/autostop.marker" \
		DWM_SESSION_TEST_THEME_APPLY_MARKER="$work/theme-apply.marker" \
		DWM_SESSION_TEST_THEME_ENV_MARKER="$work/theme-env.marker" \
		DISPLAY=$runtime_display HOME="$runtime_home" \
		XDG_CONFIG_HOME=relative-config XDG_DATA_HOME=relative-data "$repo/dwm" \
		>"$work/dwm.log" 2>&1 &
	real_dwm_pid=$!
	test_pids="$test_pids $real_dwm_pid"
	i=0
	while ! DISPLAY=$runtime_display /usr/bin/xprop -root _NET_SUPPORTING_WM_CHECK \
		2>/dev/null | grep -Fq 'window id #'; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || {
			printf '%s\n' 'Nested DWM did not publish its supporting window.' >&2
			exit 1
		}
		sleep 0.02
	done
	initial_theme_loads=$(grep -Fc 'dwm: loaded theme from config' "$work/dwm.log" || true)
	[ "$initial_theme_loads" -ge 1 ] || {
		printf '%s\n' 'Nested DWM did not load its XDG_DATA_HOME theme fallback.' >&2
		exit 1
	}
	i=0
	while [ ! -f "$work/theme-apply.marker" ] || [ ! -f "$work/theme-env.marker" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || {
			printf '%s\n' 'Nested DWM did not run theme-apply from XDG_DATA_HOME.' >&2
			exit 1
		}
		sleep 0.02
	done
	grep -Fqx "$runtime_config_home" "$work/theme-env.marker"
	grep -Fqx "$runtime_data_home" "$work/theme-env.marker"
	initial_theme_applies=$(wc -c <"$work/theme-apply.marker")
	cp "$repo/config/themes.toml" "$runtime_config_home/dwm-titus/themes.toml"
	i=0
	while [ "$(grep -Fc 'dwm: loaded theme from config' "$work/dwm.log" || true)" \
		-le "$initial_theme_loads" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || {
			printf '%s\n' 'Nested DWM did not hot-reload its XDG_CONFIG_HOME theme.' >&2
			exit 1
		}
		sleep 0.02
	done
	i=0
	while [ "$(wc -c <"$work/theme-apply.marker")" -le "$initial_theme_applies" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || {
			printf '%s\n' 'Nested DWM did not run theme-apply from XDG_DATA_HOME.' >&2
			exit 1
		}
		sleep 0.02
	done
	support_window=$(DISPLAY=$runtime_display /usr/bin/xprop -root \
		_NET_SUPPORTING_WM_CHECK | awk '{ print $NF }')
	DISPLAY=$runtime_display /usr/bin/xprop -id "$support_window" _NET_WM_PID |
		grep -Fqx "_NET_WM_PID(CARDINAL) = $real_dwm_pid"
	real_logout=$(DWM_SESSION_TEST_AUTOSTOP_MARKER="$work/autostop.marker" \
		DISPLAY=$runtime_display HOME="$runtime_home" \
		XDG_CONFIG_HOME=relative-config XDG_DATA_HOME=relative-data PATH=/usr/bin:/bin \
		"$helper" session-action logout)
	[ "$real_logout" = 'session-action	logout	accepted' ]
	i=0
	while process_running "$real_dwm_pid" && [ "$i" -lt 500 ]; do
		i=$((i + 1))
		sleep 0.01
	done
	if process_running "$real_dwm_pid"; then
		printf '%s\n' 'Nested DWM did not exit after the logout request.' >&2
		exit 1
	fi
	wait "$real_dwm_pid" 2>/dev/null || true
	forget_test_pid "$real_dwm_pid"
	test -f "$work/autostop.marker"
fi

grep -Fq 'static volatile sig_atomic_t running = 1;' "$repo/dwm.c"
grep -Fq 'signal(SIGUSR2, sigusr2_handler);' "$repo/dwm.c"
grep -Fq 'netatom[NetWMPid] = XInternAtom(dpy, "_NET_WM_PID", False);' "$repo/dwm.c"
grep -Fq 'XChangeProperty(dpy, wmcheckwin, netatom[NetWMPid], XA_CARDINAL, 32,' "$repo/dwm.c"

printf '%s\n' 'Quickshell session action model, backend, and graceful logout: PASS'
