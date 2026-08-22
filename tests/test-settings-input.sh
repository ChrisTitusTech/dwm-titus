#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo/scripts/dwm-settings-input"
work=$(mktemp -d)
watch_test_owner_pid=
watch_test_owner_identity=
declare -a watch_test_identities=()

identity_is_live() {
	local identity=$1 pid=${1%%:*} starttime=${1#*:} stat rest
	local -a fields=()
	[[ $pid =~ ^[1-9][0-9]*$ && $starttime =~ ^[0-9]+$ ]] || return 1
	{ IFS= read -r stat <"/proc/$pid/stat"; } 2>/dev/null || return 1
	rest=${stat##*) }
	read -r -a fields <<<"$rest"
	[[ ${#fields[@]} -ge 20 && ${fields[0]} != Z && ${fields[19]} == "$starttime" ]]
}

cleanup_test() {
	local identity
	if [[ -n $watch_test_owner_identity ]] && identity_is_live "$watch_test_owner_identity"; then
		kill -KILL "${watch_test_owner_identity%%:*}" 2>/dev/null || true
	fi
	if [[ -n $watch_test_owner_pid ]]; then
		wait "$watch_test_owner_pid" 2>/dev/null || true
	fi
	for identity in "${watch_test_identities[@]}"; do
		identity_is_live "$identity" || continue
		kill -KILL "${identity%%:*}" 2>/dev/null || true
	done
	rm -rf "$work"
}

trap cleanup_test EXIT
mkdir -p "$work/bin" "$work/home/.config/dwm-titus" "$work/runtime"
chmod 700 "$work/runtime"

cat >"$work/devices" <<'EOF'
⎡ Virtual core pointer                     id=2    [master pointer  (3)]
⎜   ↳ Mouse, Wild [Name]                   id=12   [slave  pointer  (2)]
⎜   ↳ Portable TouchPad                    id=14   [slave  pointer  (2)]
⎜   ↳ Node-less Pointer                    id=15   [slave  pointer  (2)]
⎣ Virtual core keyboard                    id=3    [master keyboard (2)]
    ↳ Keyboard with spaces                 id=13   [slave  keyboard (3)]
EOF

cat >"$work/devices-ascii" <<'EOF'
+ Virtual core pointer                     id=2    [master pointer  (3)]
|   + Mouse, Wild [Name]                   id=12   [slave  pointer  (2)]
|   + Portable TouchPad                    id=14   [slave  pointer  (2)]
|   + Node-less Pointer                    id=15   [slave  pointer  (2)]
+ Virtual core keyboard                    id=3    [master keyboard (2)]
    + Keyboard with spaces                 id=13   [slave  keyboard (3)]
EOF

cat >"$work/bin/xinput" <<'EOF'
#!/bin/sh
case $1 in
--list)
	cat "$TEST_DEVICES"
	;;
list-props)
	if [ "${TEST_DISAPPEAR_ID:-}" = "$2" ]; then
		count=$(cat "$TEST_COUNTER" 2>/dev/null || printf 0)
		count=$((count + 1))
		printf '%s\n' "$count" >"$TEST_COUNTER"
		[ "$count" -lt 2 ] || exit 1
	fi
	case $2 in
	12) cat <<'PROPS'
Device 'Mouse, Wild [Name]':
	Device Product ID (101): 1133, 49291
	Device Node (102): "/dev/input/event9"
	libinput Accel Speed (300): 0.000000
	libinput Accel Speed Default (301): 0.000000
	libinput Natural Scrolling Enabled (302): 0
	libinput Natural Scrolling Enabled Default (303): 0
	libinput Tapping Enabled (304): 1
	libinput Tapping Enabled Default (305): 1
PROPS
		;;
	13) cat <<'PROPS'
Device 'Keyboard with spaces':
	Device Product ID (101): 1234, 5678
	Device Node (102): "/dev/input/event10"
PROPS
		;;
	14) cat <<'PROPS'
Device 'Portable TouchPad':
	Device Product ID (101): 2222, 3333
	Device Node (102): "/dev/input/event11"
	libinput Accel Speed (300): 0.000000
	libinput Accel Speed Default (301): 0.000000
	libinput Natural Scrolling Enabled (302): 1
	libinput Natural Scrolling Enabled Default (303): 0
	libinput Tapping Enabled (304): 1
	libinput Tapping Enabled Default (305): 1
PROPS
		;;
	15) cat <<'PROPS'
Device 'Node-less Pointer':
	Device Product ID (101): 4444, 5555
	libinput Accel Speed (300): 0.000000
	libinput Accel Speed Default (301): 0.000000
PROPS
		;;
	esac
	;;
set-prop)
	[ "${TEST_FAIL_SET:-0}" != 1 ] || exit 1
	if [ -n "${TEST_TIMING_LOG:-}" ]; then
		printf 'apply %s\n' "$(date +%s%N)" >>"$TEST_TIMING_LOG"
	fi
	printf 'xinput %s\n' "$*" >>"$TEST_LOG"
	;;
*) exit 2 ;;
esac
EOF

cat >"$work/bin/setxkbmap" <<'EOF'
#!/bin/sh
case " $* " in
*' -query '*)
	[ "${TEST_FAIL_QUERY:-0}" != 1 ] || exit 1
	printf 'rules: evdev\nmodel: pc105\nlayout: %s\noptions: %s\n' "${TEST_LAYOUT-us}" "${TEST_OPTIONS-caps:escape}"
	;;
*) [ "${TEST_FAIL_SET:-0}" != 1 ] || exit 1; printf 'setxkbmap %s\n' "$*" >>"$TEST_LOG" ;;
esac
EOF

cat >"$work/bin/udevadm" <<'EOF'
#!/bin/sh
case ${1:-} in
info)
	if [ "${TEST_UNSTABLE:-0}" = 1 ]; then
		exit 0
	fi
	case "$*" in
	*event9*) printf 'ID_PATH=pci-test-mouse\n' ;;
	*event10*) printf 'ID_SERIAL=test-keyboard\n' ;;
	*event11*) printf 'ID_PATH=pci-test-touchpad\n' ;;
	esac
	;;
monitor)
		if [ -n "${TEST_WATCH_MONITOR_ID:-}" ]; then
			[ "${TEST_WATCH_MONITOR_EXIT:-0}" != 1 ] || exit 0
			stat=$(cat "/proc/$$/stat")
			rest=${stat##*) }
			set -- $rest
			trap '' TERM
			printf '%s:%s\n' "$$" "${20}" >"$TEST_WATCH_MONITOR_ID"
			printf 'ACTION=change\n'
			exec "$TEST_SLEEP_BIN" 60
		fi
		if [ "${TEST_UDEV_BLOCK:-0}" = 1 ]; then
			trap 'exit 0' HUP INT TERM
			while :; do sleep 0.1; done
		fi
		if [ -n "${TEST_UDEV_DELAY:-}" ]; then
			printf 'ACTION=add\n'
			sleep "$TEST_UDEV_DELAY"
			if [ -n "${TEST_TIMING_LOG:-}" ]; then
				printf 'event %s\n' "$(date +%s%N)" >>"$TEST_TIMING_LOG"
			fi
			printf 'ACTION=change\n'
		else
			printf '%b\n' "${TEST_UDEV_EVENTS:-ACTION=add}"
		fi
		;;
*) exit 2 ;;
esac
EOF
chmod +x "$work/bin/"*

cat >"$work/watch-owner" <<'EOF'
#!/bin/bash
set -euo pipefail
identity_file=$1
shift
owner_file=$identity_file.owner
stat=$(<"/proc/$$/stat")
rest=${stat##*) }
read -r -a fields <<<"$rest"
printf '%s:%s\n' "$$" "${fields[19]}" >"$owner_file"
"$@" "$$" "${fields[19]}" &
child=$!
for ((attempt = 0; attempt < 50; attempt++)); do
	if IFS= read -r stat <"/proc/$child/stat" 2>/dev/null; then
		rest=${stat##*) }
		read -r -a fields <<<"$rest"
		if [[ ${#fields[@]} -ge 20 && ${fields[0]} != Z && ${fields[19]} =~ ^[0-9]+$ ]]; then
			printf '%s:%s\n' "$child" "${fields[19]}" >"$identity_file"
			wait "$child"
			exit $?
		fi
	fi
	sleep 0.01
done
kill -KILL "$child" 2>/dev/null || true
wait "$child" 2>/dev/null || true
exit 1
EOF
chmod +x "$work/watch-owner"

env_common=(
	DISPLAY=:88
	HOME="$work/home"
	XDG_CONFIG_HOME="$work/home/.config"
	XDG_RUNTIME_DIR="$work/runtime"
	PATH="$work/bin:/usr/bin:/bin"
	TEST_DEVICES="$work/devices"
	TEST_LOG="$work/actions.log"
	TEST_COUNTER="$work/list-props.count"
)

env "${env_common[@]}" "$helper" discover >"$work/discover"
grep -Fqx 'input-protocol	1' "$work/discover"
grep -Fq $'pointer	Mouse, Wild [Name]' "$work/discover"
grep -Fq $'keyboard	Keyboard with spaces' "$work/discover"
grep -Fq $'touchpad	Portable TouchPad' "$work/discover"
grep -Fq $'pointer-speed	Pointer acceleration / speed	number	0.000000	0.000000	-1	1' "$work/discover"
grep -Fq $'keyboard-layout	Keyboard layout	text	us	us	0	0' "$work/discover"

mouse_key=$(awk -F '\t' '$1 == "device" && $4 == "pointer" {print $2; exit}' "$work/discover")
keyboard_key=$(awk -F '\t' '$1 == "device" && $4 == "keyboard" {print $2}' "$work/discover")
nodeless_key=$(awk -F '\t' '$1 == "device" && $5 == "Node-less Pointer" {print $2}' "$work/discover")
[[ $mouse_key =~ ^[0-9a-f]{16}$ ]]
[[ $keyboard_key =~ ^[0-9a-f]{16}$ ]]
grep -Fq $'unsupported\t'"$nodeless_key"$'\tpersistence\tNo stable udev serial' "$work/discover"

bash_bin=$(command -v bash)
no_setxkbmap_bin="$work/no-setxkbmap-bin"
mkdir -p "$no_setxkbmap_bin"
cp "$work/bin/xinput" "$work/bin/udevadm" "$no_setxkbmap_bin/"
for tool in awk cat dirname mktemp rm sed sha256sum tr; do
	ln -s "$(command -v "$tool")" "$no_setxkbmap_bin/$tool"
done
env "${env_common[@]}" PATH="$no_setxkbmap_bin" \
	"$bash_bin" "$helper" discover >"$work/discover-no-setxkbmap"
grep -Fq $'unsupported\t'"$keyboard_key"$'\tkeyboard-layout\tsetxkbmap is unavailable' \
	"$work/discover-no-setxkbmap"
grep -Fq $'unsupported\t'"$keyboard_key"$'\tmodifier-options\tsetxkbmap is unavailable' \
	"$work/discover-no-setxkbmap"
env "${env_common[@]}" TEST_FAIL_QUERY=1 "$helper" discover >"$work/discover-query-failure"
grep -Fq $'unsupported\t'"$keyboard_key"$'\tkeyboard-layout\tsetxkbmap could not query this keyboard' \
	"$work/discover-query-failure"
grep -Fq $'unsupported\t'"$keyboard_key"$'\tmodifier-options\tsetxkbmap could not query this keyboard' \
	"$work/discover-query-failure"
env "${env_common[@]}" TEST_LAYOUT= "$helper" discover >"$work/discover-empty-layout"
grep -Fq $'unsupported\t'"$keyboard_key"$'\tkeyboard-layout\tsetxkbmap did not report a keyboard layout' \
	"$work/discover-empty-layout"
grep -Fq $'setting\t'"$keyboard_key"$'\tmodifier-options\tModifier options\ttext\tcaps:escape' \
	"$work/discover-empty-layout"
expected_mouse_key=$(printf '%s' 'pointer|Mouse, Wild [Name]|1133, 49291|path:pci-test-mouse' | sha256sum | awk '{print substr($1, 1, 16)}')
expected_keyboard_key=$(printf '%s' 'keyboard|Keyboard with spaces|1234, 5678|serial:test-keyboard' | sha256sum | awk '{print substr($1, 1, 16)}')
[[ $mouse_key == "$expected_mouse_key" ]]
[[ $keyboard_key == "$expected_keyboard_key" ]]

env "${env_common[@]}" TEST_DEVICES="$work/devices-ascii" "$helper" discover >"$work/discover-ascii"
ascii_mouse_key=$(awk -F '\t' '$1 == "device" && $4 == "pointer" {print $2; exit}' "$work/discover-ascii")
ascii_keyboard_key=$(awk -F '\t' '$1 == "device" && $4 == "keyboard" {print $2}' "$work/discover-ascii")
[[ $ascii_mouse_key == "$mouse_key" ]]
[[ $ascii_keyboard_key == "$keyboard_key" ]]
grep -Fq $'pointer\tMouse, Wild [Name]' "$work/discover-ascii"
grep -Fq $'keyboard\tKeyboard with spaces' "$work/discover-ascii"

rm -f "$work/watch-helper.id" "$work/watch-helper.id.owner" \
	"$work/watch-monitor.id" "$work/watch-output"
env "${env_common[@]}" TEST_WATCH_MONITOR_ID="$work/watch-monitor.id" \
	TEST_SLEEP_BIN="$(command -v sleep)" "$work/watch-owner" "$work/watch-helper.id" \
	"$helper" watch >"$work/watch-output" &
watch_test_launcher_pid=$!
for _ in {1..50}; do
	[[ -s $work/watch-helper.id.owner && -s $work/watch-helper.id && -s $work/watch-monitor.id ]] &&
		grep -Fqx changed "$work/watch-output" && break
	sleep 0.05
done
grep -Fqx changed "$work/watch-output"
owner_identity=$(<"$work/watch-helper.id.owner")
watch_test_owner_identity=$owner_identity
watch_test_owner_pid=${owner_identity%%:*}
[[ $watch_test_owner_pid == "$watch_test_launcher_pid" ]]
helper_identity=$(<"$work/watch-helper.id")
monitor_identity=$(<"$work/watch-monitor.id")
identity_is_live "$helper_identity"
identity_is_live "$monitor_identity"
watch_test_identities+=("$helper_identity" "$monitor_identity")
helper_pid=${helper_identity%%:*}
for child_pid in $(<"/proc/$helper_pid/task/$helper_pid/children"); do
	child_start=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' \
		"/proc/$child_pid/stat" 2>/dev/null || true)
	[[ $child_start =~ ^[0-9]+$ ]] && watch_test_identities+=("$child_pid:$child_start")
done
kill -KILL "$watch_test_owner_pid"
wait "$watch_test_owner_pid" 2>/dev/null || true
watch_test_owner_pid=
watch_test_owner_identity=
for _ in {1..80}; do
	live=0
	for identity in "${watch_test_identities[@]}"; do
		identity_is_live "$identity" && live=1
	done
	((live == 0)) && break
	sleep 0.05
done
for identity in "${watch_test_identities[@]}"; do
	if identity_is_live "$identity"; then
		printf 'input watch process survived direct owner exit: %s\n' "$identity" >&2
		exit 1
	fi
done
watch_test_identities=()

"$(command -v sleep)" 0.1 &
dead_owner_pid=$!
dead_owner_start=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' \
	"/proc/$dead_owner_pid/stat")
wait "$dead_owner_pid"
if env "${env_common[@]}" TEST_WATCH_MONITOR_ID="$work/dead-owner-monitor.id" \
	TEST_SLEEP_BIN="$(command -v sleep)" "$helper" watch \
	"$dead_owner_pid" "$dead_owner_start" >"$work/dead-owner.out" 2>"$work/dead-owner.err"; then
	printf 'input watch accepted an owner that exited before helper startup\n' >&2
	exit 1
fi
grep -Fq 'input watch owner is unavailable' "$work/dead-owner.err"
[[ ! -e $work/dead-owner-monitor.id ]]

test_owner_start=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' \
	"/proc/$$/stat")
if env "${env_common[@]}" TEST_WATCH_MONITOR_ID="$work/monitor-exit.id" \
	TEST_WATCH_MONITOR_EXIT=1 TEST_SLEEP_BIN="$(command -v sleep)" \
	"$helper" watch "$$" "$test_owner_start" \
	>"$work/monitor-exit.out" 2>"$work/monitor-exit.err"; then
	printf 'input watch accepted an event monitor that exited unexpectedly\n' >&2
	exit 1
fi

rm -f "$work/list-props.count"
env "${env_common[@]}" TEST_DISAPPEAR_ID=14 "$helper" discover >"$work/discover-hotplug"
grep -Fqx 'input-protocol	1' "$work/discover-hotplug"
grep -Fq $'pointer\tMouse, Wild [Name]' "$work/discover-hotplug"
if grep -Fq $'touchpad\tPortable TouchPad' "$work/discover-hotplug"; then
	printf 'device removed during discovery remained in the provider response\n' >&2
	exit 1
fi

env "${env_common[@]}" "$helper" preview nodeless-test 5 "$nodeless_key" pointer-speed 0.4 >/dev/null
env "${env_common[@]}" "$helper" keep nodeless-test 2>"$work/nodeless-keep.err" >/dev/null
grep -Fq 'session value only' "$work/nodeless-keep.err"
if [[ -f $work/home/.config/dwm-titus/input-settings.conf ]] &&
	grep -Fq "$nodeless_key" "$work/home/.config/dwm-titus/input-settings.conf"; then
	printf 'node-less input identity was persisted\n' >&2
	exit 1
fi

env "${env_common[@]}" "$helper" preview pointer-test 5 "$mouse_key" pointer-speed 0.25 >"$work/preview"
grep -Fqx 'preview	pointer-test	5' "$work/preview"
env "${env_common[@]}" "$helper" keep pointer-test >"$work/keep"
grep -Fqx 'result	keep	pointer-test' "$work/keep"
grep -Fqx "$mouse_key"$'\tpointer-speed\t0.25\t0.000000' \
	"$work/home/.config/dwm-titus/input-settings.conf"

env "${env_common[@]}" "$helper" apply-saved
grep -Fq 'xinput set-prop 12 libinput Accel Speed 0.25' "$work/actions.log"

for invalid_settle in 0 0.0; do
	if env "${env_common[@]}" DWM_INPUT_HOTPLUG_SETTLE_SECONDS="$invalid_settle" \
		"$helper" watch-apply 2>"$work/invalid-settle.err"; then
		printf 'zero hotplug settle interval was accepted\n' >&2
		exit 1
	fi
	grep -Fq 'hotplug settle interval must be positive' "$work/invalid-settle.err"
done

rm -f "$work/actions.log"
env "${env_common[@]}" DWM_INPUT_HOTPLUG_SETTLE_SECONDS=0.15 \
	TEST_UDEV_DELAY=0.12 TEST_TIMING_LOG="$work/hotplug-timing.log" "$helper" watch-apply
[[ $(grep -Fc 'xinput set-prop 12 libinput Accel Speed 0.25' "$work/actions.log") == 1 ]]
event_time=$(awk '$1 == "event" { print $2; exit }' "$work/hotplug-timing.log")
apply_time=$(awk '$1 == "apply" { print $2; exit }' "$work/hotplug-timing.log")
((apply_time - event_time >= 100000000))
test -f "$work/runtime/dwm-settings-input/hotplug-watch.lock"
[[ $(stat -c %a "$work/runtime/dwm-settings-input/hotplug-watch.lock") == 600 ]]

exec 9>"$work/runtime/dwm-settings-input/hotplug-watch.lock"
flock -n 9
if env "${env_common[@]}" "$helper" watch-apply 2>"$work/duplicate-watcher.err"; then
	printf 'duplicate input hotplug watcher was accepted\n' >&2
	exit 1
fi
grep -Fq 'input hotplug watcher is already running' "$work/duplicate-watcher.err"
flock -u 9
exec 9>&-

sleep 1 &
session_pid=$!
session_start=$(awk '{ print $22 }' "/proc/$session_pid/stat")
env "${env_common[@]}" TEST_UDEV_BLOCK=1 \
	DWM_INPUT_SESSION_PID="$session_pid" DWM_INPUT_SESSION_START="$session_start" \
	"$helper" watch-apply &
session_watcher_pid=$!
for _ in {1..30}; do
	test -f "$work/runtime/dwm-settings-input/hotplug-watch.lock" && break
	sleep 0.1
done
wait "$session_pid"
for _ in {1..30}; do
	if ! kill -0 "$session_watcher_pid" 2>/dev/null ||
		[[ $(awk '{ print $3 }' "/proc/$session_watcher_pid/stat" 2>/dev/null || true) == Z ]]; then
		break
	fi
	sleep 0.1
done
if kill -0 "$session_watcher_pid" 2>/dev/null &&
	[[ $(awk '{ print $3 }' "/proc/$session_watcher_pid/stat" 2>/dev/null || true) != Z ]]; then
	kill "$session_watcher_pid" 2>/dev/null || true
	printf 'input hotplug watcher survived its X11 session process\n' >&2
	exit 1
fi
wait "$session_watcher_pid" 2>/dev/null || true

rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" preview hotplug-preview 5 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" DWM_INPUT_HOTPLUG_SETTLE_SECONDS=0.01 \
	TEST_UDEV_EVENTS=ACTION=add "$helper" watch-apply
[[ $(grep -Fc 'xinput set-prop 12 libinput Accel Speed 0.5' "$work/actions.log") == 1 ]]
if grep -Fq 'xinput set-prop 12 libinput Accel Speed 0.25' "$work/actions.log"; then
	printf 'hotplug replay overwrote an active input preview\n' >&2
	exit 1
fi
test -f "$work/runtime/dwm-settings-input/hotplug-replay.pending"
env "${env_common[@]}" "$helper" keep hotplug-preview >/dev/null
[[ $(grep -Fc 'xinput set-prop 12 libinput Accel Speed 0.5' "$work/actions.log") == 2 ]]
test ! -e "$work/runtime/dwm-settings-input/hotplug-replay.pending"
env "${env_common[@]}" "$helper" preview hotplug-restore 5 "$mouse_key" pointer-speed 0.25 >/dev/null
env "${env_common[@]}" "$helper" keep hotplug-restore >/dev/null

rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" preview hotplug-revert 5 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" DWM_INPUT_HOTPLUG_SETTLE_SECONDS=0.01 \
	TEST_UDEV_EVENTS=ACTION=change "$helper" watch-apply
env "${env_common[@]}" "$helper" revert hotplug-revert >/dev/null
[[ $(grep 'xinput set-prop 12 libinput Accel Speed' "$work/actions.log" | tail -n 1) == 'xinput set-prop 12 libinput Accel Speed 0.000000' ]]
test ! -e "$work/runtime/dwm-settings-input/hotplug-replay.pending"

rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" preview hotplug-timeout 1 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" DWM_INPUT_HOTPLUG_SETTLE_SECONDS=0.01 \
	TEST_UDEV_EVENTS=ACTION=change "$helper" watch-apply
for _ in {1..30}; do
	test ! -e "$work/runtime/dwm-settings-input/hotplug-timeout.state" && break
	sleep 0.1
done
test ! -e "$work/runtime/dwm-settings-input/hotplug-timeout.state"
[[ $(grep 'xinput set-prop 12 libinput Accel Speed' "$work/actions.log" | tail -n 1) == 'xinput set-prop 12 libinput Accel Speed 0.000000' ]]
test ! -e "$work/runtime/dwm-settings-input/hotplug-replay.pending"

override_file="$work/override/nested/input.conf"
env "${env_common[@]}" DWM_INPUT_SETTINGS_FILE="$override_file" \
	"$helper" preview override-path 5 "$mouse_key" pointer-speed 0.4 >/dev/null
env "${env_common[@]}" DWM_INPUT_SETTINGS_FILE="$override_file" \
	"$helper" keep override-path >/dev/null
grep -Fqx "$mouse_key"$'\tpointer-speed\t0.4\t0.000000' "$override_file"

if env "${env_common[@]}" TEST_FAIL_SET=1 "$helper" preview apply-failure 5 \
	"$mouse_key" pointer-speed 0.5 2>"$work/apply-failure.err"; then
	printf 'failed input preview reported success\n' >&2
	exit 1
fi
grep -Fq 'input preview failed' "$work/apply-failure.err"
test ! -e "$work/runtime/dwm-settings-input/apply-failure.state"
test ! -e "$work/runtime/dwm-settings-input/current"

cp "$work/home/.config/dwm-titus/input-settings.conf" "$work/saved-connected"
{
	printf '0000000000000000\tpointer-speed\t0.75\n'
	cat "$work/saved-connected"
} >"$work/home/.config/dwm-titus/input-settings.conf"
rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" apply-saved 2>"$work/apply-disconnected.err"
if ! grep -Fq 'skipped unavailable 0000000000000000/pointer-speed' "$work/apply-disconnected.err"; then
	cat "$work/apply-disconnected.err" >&2
	exit 1
fi
grep -Fq 'xinput set-prop 12 libinput Accel Speed 0.25' "$work/actions.log"

env "${env_common[@]}" "$helper" preview keyboard-test 5 "$keyboard_key" keyboard-layout de >/dev/null
mkdir "$work/runtime/dwm-settings-input/keyboard-test.claim"
if env "${env_common[@]}" "$helper" keep keyboard-test 2>"$work/input-claim.err"; then
	printf 'concurrent input finalization was accepted\n' >&2
	exit 1
fi
grep -Fq 'already being finalized' "$work/input-claim.err"
test -f "$work/runtime/dwm-settings-input/keyboard-test.state"
rmdir "$work/runtime/dwm-settings-input/keyboard-test.claim"
env "${env_common[@]}" "$helper" revert keyboard-test >"$work/revert"
grep -Fqx 'result	revert	keyboard-test' "$work/revert"
grep -Fq 'setxkbmap -device 13 -layout de' "$work/actions.log"
grep -Fq 'setxkbmap -device 13 -layout us' "$work/actions.log"

rm -f "$work/actions.log"
if env "${env_common[@]}" "$helper" preview 'bad/token' 5 \
	"$mouse_key" pointer-speed 0.5 2>"$work/invalid-token.err"; then
	printf 'invalid preview token was accepted\n' >&2
	exit 1
fi
grep -Fq 'invalid preview token' "$work/invalid-token.err"
test ! -s "$work/actions.log"

rm -f "$work/actions.log"
if env "${env_common[@]}" TEST_OPTIONS='foo|bar' "$helper" preview separator-test 5 \
	"$keyboard_key" modifier-options ctrl:nocaps 2>"$work/separator.err"; then
	printf 'reserved preview-state separator was accepted\n' >&2
	exit 1
fi
grep -Fq 'reserved preview-state separator' "$work/separator.err"
test ! -s "$work/actions.log"

mkdir "$work/real-runtime-base"
chmod 700 "$work/real-runtime-base"
ln -s "$work/real-runtime-base" "$work/symlink-runtime-base"
if env "${env_common[@]}" XDG_RUNTIME_DIR="$work/symlink-runtime-base" \
	"$helper" preview symlink-runtime 5 "$mouse_key" pointer-speed 0.5 \
	2>"$work/symlink-runtime.err"; then
	printf 'symlinked runtime base was accepted\n' >&2
	exit 1
fi
grep -Fq 'unsafe runtime base directory' "$work/symlink-runtime.err"

mkdir "$work/permissive-runtime-base"
chmod 755 "$work/permissive-runtime-base"
if env "${env_common[@]}" XDG_RUNTIME_DIR="$work/permissive-runtime-base" \
	"$helper" preview permissive-runtime 5 "$mouse_key" pointer-speed 0.5 \
	2>"$work/permissive-runtime.err"; then
	printf 'permissive runtime base was accepted\n' >&2
	exit 1
fi
grep -Fq 'runtime base directory is too permissive' "$work/permissive-runtime.err"

mkdir "$work/runtime/permissive-state"
chmod 700 "$work/runtime/permissive-state"
env "${env_common[@]}" XDG_RUNTIME_DIR="$work/runtime/permissive-state" \
	"$helper" preview permissive-state-setup 5 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" XDG_RUNTIME_DIR="$work/runtime/permissive-state" \
	"$helper" revert permissive-state-setup >/dev/null
chmod 755 "$work/runtime/permissive-state/dwm-settings-input"
if env "${env_common[@]}" XDG_RUNTIME_DIR="$work/runtime/permissive-state" \
	"$helper" preview permissive-state 5 "$mouse_key" pointer-speed 0.5 \
	2>"$work/permissive-state.err"; then
	printf 'permissive preview state directory was accepted\n' >&2
	exit 1
fi
grep -Fq 'preview state directory is too permissive' "$work/permissive-state.err"

env "${env_common[@]}" TEST_UNSTABLE=1 "$helper" discover >"$work/discover-unstable"
unstable_mouse_key=$(awk -F '\t' '$1 == "device" && $4 == "pointer" {print $2; exit}' "$work/discover-unstable")
grep -Fq $'unsupported\t'"$unstable_mouse_key"$'\tpersistence\tNo stable udev serial' \
	"$work/discover-unstable"
env "${env_common[@]}" TEST_UNSTABLE=1 "$helper" preview unstable-test 5 \
	"$unstable_mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" TEST_UNSTABLE=1 "$helper" keep unstable-test \
	2>"$work/unstable-keep.err" >/dev/null
grep -Fq 'session value only' "$work/unstable-keep.err"
if grep -Fq "$unstable_mouse_key" "$work/home/.config/dwm-titus/input-settings.conf"; then
	printf 'unstable input identity was persisted\n' >&2
	exit 1
fi

env "${env_common[@]}" "$helper" preview disconnect-test 1 "$mouse_key" pointer-speed 0.5 >/dev/null
cp "$work/devices" "$work/devices-all"
sed '/Mouse, Wild/d' "$work/devices-all" >"$work/devices"
for _ in {1..30}; do
	env "${env_common[@]}" "$helper" preview-status disconnect-test >"$work/disconnect-status"
	grep -Fq $'preview-failed\tdisconnect-test\t' "$work/disconnect-status" && break
	sleep 0.1
done
grep -Fq $'preview-failed\tdisconnect-test\tAutomatic input rollback failed' "$work/disconnect-status"
test -f "$work/runtime/dwm-settings-input/disconnect-test.state"
env "${env_common[@]}" "$helper" preview-status >"$work/recovered-disconnect-status"
grep -Fq $'preview-failed\tdisconnect-test\tAutomatic input rollback failed' \
	"$work/recovered-disconnect-status"
if env "${env_common[@]}" "$helper" revert disconnect-test 2>"$work/disconnect-revert.err"; then
	printf 'rollback unexpectedly succeeded while the input device was disconnected\n' >&2
	exit 1
fi
grep -Fq 'preview state was retained for rollback retry' "$work/disconnect-revert.err"
test ! -e "$work/runtime/dwm-settings-input/disconnect-test.claim"
cp "$work/devices-all" "$work/devices"
env "${env_common[@]}" "$helper" revert disconnect-test >/dev/null
test ! -e "$work/runtime/dwm-settings-input/current"

env "${env_common[@]}" "$helper" preview keep-disconnected 1 "$mouse_key" pointer-speed 0.6 >/dev/null
sed '/Mouse, Wild/d' "$work/devices-all" >"$work/devices"
for _ in {1..30}; do
	env "${env_common[@]}" "$helper" preview-status keep-disconnected >"$work/keep-disconnected-status"
	grep -Fq $'preview-failed\tkeep-disconnected\t' "$work/keep-disconnected-status" && break
	sleep 0.1
done
env "${env_common[@]}" "$helper" keep keep-disconnected >/dev/null
grep -Fqx "$mouse_key"$'\tpointer-speed\t0.6\t0.000000' \
	"$work/home/.config/dwm-titus/input-settings.conf"
test ! -e "$work/runtime/dwm-settings-input/keep-disconnected.state"
cp "$work/devices-all" "$work/devices"
rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" apply-saved
grep -Fq 'xinput set-prop 12 libinput Accel Speed 0.6' "$work/actions.log"

env "${env_common[@]}" "$helper" preview after-disconnect 5 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" "$helper" revert after-disconnect >/dev/null

env "${env_common[@]}" TEST_OPTIONS= "$helper" preview empty-options 5 \
	"$keyboard_key" modifier-options ctrl:nocaps >/dev/null
env "${env_common[@]}" "$helper" keep empty-options >/dev/null
grep -Fqx "$keyboard_key"$'\tmodifier-options\tctrl:nocaps\t' \
	"$work/home/.config/dwm-titus/input-settings.conf"
env "${env_common[@]}" "$helper" reset "$keyboard_key" modifier-options >/dev/null
printf '%s\tmodifier-options\t\t\n' "$keyboard_key" \
	>>"$work/home/.config/dwm-titus/input-settings.conf"
rm -f "$work/actions.log"
env "${env_common[@]}" "$helper" apply-saved
grep -Fq 'setxkbmap -device 13 -option  -option ' "$work/actions.log"

env "${env_common[@]}" TEST_LAYOUT=de "$helper" preview keyboard-reset 5 \
	"$keyboard_key" keyboard-layout fr >/dev/null
env "${env_common[@]}" "$helper" keep keyboard-reset >/dev/null
env "${env_common[@]}" "$helper" reset "$keyboard_key" keyboard-layout >/dev/null
grep -Fq 'setxkbmap -device 13 -layout de' "$work/actions.log"
if grep -Fq "$keyboard_key"$'\tkeyboard-layout\t' \
	"$work/home/.config/dwm-titus/input-settings.conf"; then
	printf 'keyboard reset left a persisted layout override\n' >&2
	exit 1
fi

if env "${env_common[@]}" "$helper" preview invalid 5 "$mouse_key" pointer-speed 4 2>"$work/invalid.err"; then
	printf 'out-of-range pointer speed was accepted\n' >&2
	exit 1
fi
grep -Fq 'invalid value' "$work/invalid.err"

printf 'Settings input discovery, stable IDs, preview, rollback, and persistence: PASS\n'
