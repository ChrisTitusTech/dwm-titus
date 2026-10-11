#!/bin/sh
# Keyboard layout groups on a private Xvfb: dwm publishes the XKB group state,
# handles _DWM_KEYBOARD_GROUP_REQUEST and the cyclelayout func, and
# dwm-quickshell-state reports it through state and watch.
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
	[ -f "$work/dwm.log" ] && tail -n 20 "$work/dwm.log" >&2
	exit 1
}

X() {
	DISPLAY=$display "$@"
}

root_value() {
	X xprop -root "$1" 2>/dev/null | sed -n 's/^[^=]*= //p'
}

wait_root_value() {
	prop=$1
	expected=$2
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(root_value "$prop")" = "$expected" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "$prop is '$(root_value "$prop")', expected '$expected'"
}

wait_group() {
	wait_root_value _DWM_KEYBOARD_GROUP "$1"
}

assert_no_request() {
	i=0
	while [ "$i" -lt 100 ]; do
		X xprop -root _DWM_KEYBOARD_GROUP_REQUEST 2>/dev/null | grep -q '= ' || return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "request property was not consumed"
}

request() {
	X "$repo_dir/scripts/dwm-quickshell-state" keyboard-group "$1"
}

# The state helper must only report what it is given, so read it on the
# private display with the repo copy.
state_value() {
	X "$repo_dir/scripts/dwm-quickshell-state" state | sed -n "s/^$1=//p"
}

wait_state_value() {
	key=$1
	expected=$2
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(state_value "$key")" = "$expected" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "state $key is '$(state_value "$key")', expected '$expected'"
}

# Press the keysyms in order and release them in reverse with raw XTest events.
# xdotool cannot be used for this: after typing it locks the group it started
# with again, which undoes a grp: toggle or a cyclelayout switch.
press_keys() {
	DISPLAY=$display python3 -I -c '
import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6")
xtst = ctypes.CDLL("libXtst.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XStringToKeysym.restype = ctypes.c_ulong
dpy = ctypes.c_void_p(x11.XOpenDisplay(None))
if not dpy.value:
    sys.exit("cannot open display")
codes = []
for name in sys.argv[1:]:
    code = x11.XKeysymToKeycode(dpy, ctypes.c_ulong(x11.XStringToKeysym(name.encode())))
    if not code:
        sys.exit("no keycode for " + name)
    codes.append(code)
for code in codes:
    xtst.XTestFakeKeyEvent(dpy, code, 1, 0)
for code in reversed(codes):
    xtst.XTestFakeKeyEvent(dpy, code, 0, 0)
x11.XSync(dpy, 0)
' "$@"
}

count_lines() {
	grep -c "$1" "$2" || true
}

# Wait until the watch stream's newest keyboard_group/keyboard_groups pair
# matches, so the test also proves the stream delivers it.
wait_watch_group() {
	i=0
	while [ "$i" -lt 100 ]; do
		last=$(awk -F= '
			$1 == "keyboard_group" { g = $2 }
			$1 == "keyboard_groups" { c = $2 }
			END { print g "," c }' "$work/watch.out")
		[ "$last" = "$1" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "watch stream last keyboard group '$last', expected '$1'"
}

require_cmd Xvfb xprop setxkbmap xkbcomp python3 awk sed grep
[ -x "$repo_dir/dwm" ] || fail "build dwm first (make)"

tmp_root=${DWM_TEST_TMP_ROOT:-$HOME/tmp}
mkdir -p "$tmp_root"
work=$(mktemp -d "$tmp_root/dwm-keyboard-xvfb.XXXXXX")
home="$work/home"
cleanup() {
	set +e
	for pid in ${watch_pid:-} ${spy_pid:-} ${dwm_pid:-} ${xvfb_pid:-}; do
		kill "$pid" 2>/dev/null
	done
	# The watcher's xprop -spy child outlives its parent; sweep everything
	# that runs with this test's HOME.
	for dir in /proc/[0-9]*; do
		[ -r "$dir/environ" ] || continue
		{ tr '\0' '\n' <"$dir/environ"; } 2>/dev/null | grep -qx "HOME=$home" &&
			kill "${dir#/proc/}" 2>/dev/null
	done
	wait 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$work/bin" "$home/.config/dwm-titus" "$home/.local/share/dwm-titus/config"
# Keep dwm config warnings away from the caller's notification daemon.
printf '#!/bin/sh\nexit 0\n' >"$work/bin/notify-send"
chmod 755 "$work/bin/notify-send"
cp "$repo_dir/config/"*.toml "$home/.local/share/dwm-titus/config/"
cp "$repo_dir/config/themes.toml" "$repo_dir/config/window-rules.toml" "$home/.config/dwm-titus/"
printf '%s\n' \
	'keys = [' \
	'  { mod="SUPER", key="k", desc="Next keyboard layout", func="cyclelayout", i=1 },' \
	'  { mod="SUPER SHIFT", key="k", desc="Previous keyboard layout", func="cyclelayout", i=-1 },' \
	']' >"$home/.config/dwm-titus/hotkeys.toml"

# -displayfd lets the server pick a free display number itself.
exec 3>"$work/displayfd"
Xvfb -displayfd 3 -noreset -nolisten tcp -screen 0 800x600x24 >"$work/xvfb.log" 2>&1 &
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

X setxkbmap -layout us -option ''

DISPLAY=$display \
	HOME=$home \
	XDG_CONFIG_HOME="$home/.config" \
	XDG_DATA_HOME="$home/.local/share" \
	PATH="$work/bin:$PATH" \
	"$repo_dir/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

step=1
# 1. Startup with one layout.
wait_group '0, 1'
wait_root_value _DWM_KEYBOARD_GROUP_NAMES '"English (US)"'
root_value _DWM_KEYBOARD_SYMBOLS | grep -q '+us' || fail "symbols name missing us"
wait_state_value keyboard_groups 1
wait_state_value keyboard_layouts us

DISPLAY=$display HOME=$home "$repo_dir/scripts/dwm-quickshell-state" watch >"$work/watch.out" 2>&1 &
watch_pid=$!
DISPLAY=$display HOME=$home xprop -root -spy _DWM_KEYBOARD_GROUP_NAMES _DWM_KEYBOARD_SYMBOLS >"$work/names.spy" 2>&1 &
spy_pid=$!
i=0
while [ "$i" -lt 100 ] && ! grep -q '^keyboard_layouts=' "$work/watch.out"; do
	i=$((i + 1))
	sleep 0.05
done
sleep 0.3

step=2
# 2. Keymap replaced with three layouts and a grp: toggle (what Settings > Input
# writes); the count comes from the keyboard.
X setxkbmap -layout us,de,gr -option '' -option grp:alt_shift_toggle
wait_group '0, 3'
wait_root_value _DWM_KEYBOARD_GROUP_NAMES '"English (US)", "German", "Greek"'
wait_state_value keyboard_layouts 'us|de|gr'
wait_state_value keyboard_names 'English (US)|German|Greek'
wait_watch_group '0,3'
names_before=$(count_lines '^_DWM_KEYBOARD' "$work/names.spy")

step=3
# 3. Absolute and relative requests through the helper, consumed by dwm.
request 2
wait_group '2, 3'
assert_no_request
request next
wait_group '0, 3'
request prev
wait_group '2, 3'
assert_no_request
wait_watch_group '2,3'

step=4
# 4. Invalid requests are ignored and still consumed.
for bad in 3 7 foo; do
	X xprop -root -f _DWM_KEYBOARD_GROUP_REQUEST 8s -set _DWM_KEYBOARD_GROUP_REQUEST "$bad"
	assert_no_request
done
X xprop -root -f _DWM_KEYBOARD_GROUP_REQUEST 32c -set _DWM_KEYBOARD_GROUP_REQUEST 1
assert_no_request
sleep 0.2
wait_group '2, 3'
if request 9 2>/dev/null; then
	fail "helper accepted group 9"
fi

step=5
# 5. An unchanged group publishes nothing: no new watch block.
blocks_before=$(count_lines '^keyboard_group=' "$work/watch.out")
request 2
assert_no_request
sleep 0.4
blocks_after=$(count_lines '^keyboard_group=' "$work/watch.out")
[ "$blocks_before" = "$blocks_after" ] ||
	fail "unchanged group produced watch output ($blocks_before -> $blocks_after)"

step=6
# 6. Group switches publish only the group: names and symbols are not rewritten,
# and the watch stream prints a keyboard-only block for them.
names_after=$(count_lines '^_DWM_KEYBOARD' "$work/names.spy")
[ "$names_before" = "$names_after" ] ||
	fail "group switches rewrote names/symbols ($names_before -> $names_after)"
awk -v RS='' '/^keyboard_group=2\nkeyboard_groups=3$/ { found = 1 } END { exit !found }' \
	"$work/watch.out" || fail "watch stream has no keyboard-only block"

step=7
# 7. Rapid requests, each helper run waiting for the previous one: every
# relative step lands and absolute requests end on the last one.
request 0
wait_group '0, 3'
request next
request next
request next
request next
wait_group '1, 3'
request 1
request 2
request 0
wait_group '0, 3'
assert_no_request

step=8
# 8. The server-side grp:alt_shift_toggle chord, from group 0 and group 1.
press_keys Alt_L Shift_L
wait_group '1, 3'
wait_watch_group '1,3'
press_keys Alt_L Shift_L
wait_group '2, 3'

step=9
# 9. The cyclelayout func bound in hotkeys.toml.
press_keys Super_L k
wait_group '0, 3'
press_keys Super_L k
wait_group '1, 3'
press_keys Super_L Shift_L k
wait_group '0, 3'
press_keys Super_L Shift_L k
wait_group '2, 3'

step=10
# 10. Keymap shrinks while group 2 is locked: the server keeps the locked
# group, dwm publishes it wrapped into range.
X setxkbmap -layout us,gr -option ''
wait_group '0, 2'
wait_state_value keyboard_layouts 'us|gr'
X setxkbmap -layout us -option ''
wait_group '0, 1'
request next
assert_no_request
wait_group '0, 1'

step=11
# 11. Five layouts: X has four groups; the count follows the keyboard, not
# _XKB_RULES_NAMES.
X setxkbmap -layout us,gr,de,ru,fr -option ''
wait_group '0, 4'
root_value _XKB_RULES_NAMES | grep -q 'us,gr,de,ru,fr' || fail "rules names not set"
wait_state_value keyboard_layouts 'us|gr|de|ru'
request 3
wait_group '3, 4'

step=12
# 12. A keymap loaded without setxkbmap leaves _XKB_RULES_NAMES stale; the
# codes still follow the loaded keymap.
X setxkbmap -layout de,ru -print >"$work/keymap.xkb"
X xkbcomp -w0 -I/usr/share/X11/xkb "$work/keymap.xkb" "$display" >/dev/null 2>&1 ||
	fail "xkbcomp could not load the keymap"
wait_state_value keyboard_layouts 'de|ru'
wait_state_value keyboard_groups 2
root_value _XKB_RULES_NAMES | grep -q 'us,gr,de,ru,fr' || fail "rules names changed"

step=13
# 13. Missing metadata: without the symbols name the rules names are only a
# hint; without either the codes are empty but names and count remain.
X setxkbmap -layout us,gr -option ''
wait_state_value keyboard_layouts 'us|gr'
X xprop -root -remove _DWM_KEYBOARD_SYMBOLS
wait_state_value keyboard_layouts 'us|gr'
X xprop -root -remove _XKB_RULES_NAMES
wait_state_value keyboard_layouts '|'
wait_state_value keyboard_names 'English (US)|Greek'
wait_state_value keyboard_groups 2

step=14
# 14. dwm survived all of it.
kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited"

printf '%s\n' "Keyboard layout Xvfb test: PASS"
