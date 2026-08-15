#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo/scripts/dwm-settings-input"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
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
	printf 'xinput %s\n' "$*" >>"$TEST_LOG"
	;;
*) exit 2 ;;
esac
EOF

cat >"$work/bin/setxkbmap" <<'EOF'
#!/bin/sh
case " $* " in
*' -query '*) printf 'rules: evdev\nmodel: pc105\nlayout: %s\noptions: %s\n' "${TEST_LAYOUT:-us}" "${TEST_OPTIONS-caps:escape}" ;;
*) printf 'setxkbmap %s\n' "$*" >>"$TEST_LOG" ;;
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
monitor) printf 'ACTION=add\n' ;;
*) exit 2 ;;
esac
EOF
chmod +x "$work/bin/"*

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
expected_mouse_key=$(printf '%s' 'pointer|Mouse, Wild [Name]|1133, 49291|path:pci-test-mouse' | sha256sum | awk '{print substr($1, 1, 16)}')
expected_keyboard_key=$(printf '%s' 'keyboard|Keyboard with spaces|1234, 5678|serial:test-keyboard' | sha256sum | awk '{print substr($1, 1, 16)}')
[[ $mouse_key == "$expected_mouse_key" ]]
[[ $keyboard_key == "$expected_keyboard_key" ]]

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
	[[ -e $work/runtime/dwm-settings-input/current ]] || break
	sleep 0.1
done
if [[ -e $work/runtime/dwm-settings-input/current ]]; then
	printf 'input watchdog did not clear the preview reservation\n' >&2
	exit 1
fi
cp "$work/devices-all" "$work/devices"
env "${env_common[@]}" "$helper" preview after-disconnect 5 "$mouse_key" pointer-speed 0.5 >/dev/null
env "${env_common[@]}" "$helper" revert after-disconnect >/dev/null

env "${env_common[@]}" TEST_OPTIONS= "$helper" preview empty-options 5 \
	"$keyboard_key" modifier-options ctrl:nocaps >/dev/null
env "${env_common[@]}" "$helper" keep empty-options >/dev/null
grep -Fqx "$keyboard_key"$'\tmodifier-options\tctrl:nocaps\t' \
	"$work/home/.config/dwm-titus/input-settings.conf"

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
