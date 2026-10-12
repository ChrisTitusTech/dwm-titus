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

# Press the keysyms (or #keycodes) in order and release them in reverse with
# raw XTest events.
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
    if name.startswith("#"):
        codes.append(int(name[1:]))
        continue
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

# Sets the server's out-of-range group handling: wrap, clamp or redirect.
# XkbDescRec.ctrls is the pointer after dpy, flags, device_spec and the two
# keycodes (offset 16 on LP64); groups_wrap is byte 2 of XkbControlsRec.
set_groups_wrap() {
	DISPLAY=$display python3 -I -c '
import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XkbAllocKeyboard.restype = ctypes.c_void_p
dpy = ctypes.c_void_p(x11.XOpenDisplay(None))
xkb = ctypes.c_void_p(x11.XkbAllocKeyboard())
if not dpy.value or not xkb.value:
    sys.exit("cannot open display")
if x11.XkbGetControls(dpy, ctypes.c_ulong(0xF8001FFF), xkb) != 0:
    sys.exit("XkbGetControls failed")
ctrls = ctypes.c_void_p.from_address(xkb.value + 16).value
ctypes.c_ubyte.from_address(ctrls + 2).value = {"wrap": 0x00, "clamp": 0x40, "redirect": 0x80}[sys.argv[1]]
if not x11.XkbSetControls(dpy, ctypes.c_ulong(1 << 27), xkb):
    sys.exit("XkbSetControls failed")
x11.XSync(dpy, 0)
' "$1"
}

count_lines() {
	grep -c "$1" "$2" || true
}

# Wait until the watch stream's newest value for key matches.
wait_watch_value() {
	i=0
	while [ "$i" -lt 100 ]; do
		last=$(sed -n "s/^$1=//p" "$work/watch.out" | tail -n 1)
		[ "$last" = "$2" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "watch stream last $1 '$last', expected '$2'"
}

# Appends size MiB to the request property in 1 MiB chunks.
huge_request() {
	DISPLAY=$display python3 -I -c '
import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XInternAtom.restype = ctypes.c_ulong
dpy = ctypes.c_void_p(x11.XOpenDisplay(None))
if not dpy.value:
    sys.exit("cannot open display")
root = x11.XDefaultRootWindow(dpy)
atom = ctypes.c_ulong(x11.XInternAtom(dpy, b"_DWM_KEYBOARD_GROUP_REQUEST", 0))
chunk = b"x" * (1 << 20)
x11.XGrabServer(dpy)
for i in range(int(sys.argv[1])):
    x11.XChangeProperty(dpy, ctypes.c_ulong(root), atom, ctypes.c_ulong(31), 8,
        0 if i == 0 else 2, chunk, len(chunk))
x11.XUngrabServer(dpy)
x11.XSync(dpy, 0)
' "$1"
}

# Writes the request with raw bytes (Python escapes), so it can hold a NUL.
raw_request() {
	DISPLAY=$display python3 -I -c '
import ctypes, sys
x11 = ctypes.CDLL("libX11.so.6")
x11.XOpenDisplay.restype = ctypes.c_void_p
x11.XInternAtom.restype = ctypes.c_ulong
dpy = ctypes.c_void_p(x11.XOpenDisplay(None))
if not dpy.value:
    sys.exit("cannot open display")
root = ctypes.c_ulong(x11.XDefaultRootWindow(dpy))
atom = ctypes.c_ulong(x11.XInternAtom(dpy, b"_DWM_KEYBOARD_GROUP_REQUEST", 0))
value = sys.argv[1].encode().decode("unicode_escape").encode("latin-1")
x11.XChangeProperty(dpy, root, atom, ctypes.c_ulong(31), 8, 0, value, len(value))
x11.XSync(dpy, 0)
' "$1"
}

peak_kib() {
	sed -n 's/^VmHWM:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$dwm_pid/status"
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

require_cmd Xvfb xprop xinput setxkbmap xkbcomp xmodmap python3 awk sed grep
[ -x "$repo_dir/dwm" ] || fail "build dwm first (make)"

tmp_root=${DWM_TEST_TMP_ROOT:-$HOME/tmp}
mkdir -p "$tmp_root"
work=$(mktemp -d "$tmp_root/dwm-keyboard-xvfb.XXXXXX")
home="$work/home"
cleanup() {
	set +e
	# A test interrupted while dwm is stopped must resume it first, or the
	# pending SIGTERM never lands and wait blocks forever.
	[ -n "${dwm_pid:-}" ] && kill -CONT "$dwm_pid" 2>/dev/null
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
# A NUL inside the value makes it invalid, even with a valid prefix.
for bad in 'next\0junk' '1\0'; do
	raw_request "$bad"
	assert_no_request
	sleep 0.2
	wait_group '2, 3'
done
# Longer than the 16 bytes dwm reads: still consumed.
X xprop -root -f _DWM_KEYBOARD_GROUP_REQUEST 8s -set _DWM_KEYBOARD_GROUP_REQUEST \
	"$(awk 'BEGIN { while (n++ < 600) printf "x" }')"
assert_no_request
# 64 MiB: dwm reads only the first bytes, so its peak memory stays put.
peak_before=$(peak_kib)
huge_request 64 || fail "could not write the huge request"
assert_no_request
# the server deletes the value before dwm has received it; a request dwm
# answers afterwards means it is done with the huge one
request 1
wait_group '1, 3'
peak_after=$(peak_kib)
[ $((peak_after - peak_before)) -lt 16384 ] ||
	fail "dwm peak memory grew from ${peak_before} to ${peak_after} KiB on a huge request"
request 2
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
# 7. Back-to-back helper requests: the helper returns only after dwm took the
# request, so every relative step lands.
request 0
wait_group '0, 3'
for expected in 1 2 0 1; do
	request next
	wait_group "$expected, 3"
done
for target in 1 2 0; do
	request "$target"
	wait_group "$target, 3"
done
assert_no_request

# 7b. Raw writes without waiting may coalesce (documented: last one wins
# among those dwm had not read yet). Only check what the protocol promises:
# the request is consumed, the group is in range and dwm is still there.
for _ in 1 2 3 4 5; do
	X xprop -root -f _DWM_KEYBOARD_GROUP_REQUEST 8s -set _DWM_KEYBOARD_GROUP_REQUEST next
done
assert_no_request
case $(root_value _DWM_KEYBOARD_GROUP) in
'0, 3' | '1, 3' | '2, 3') ;;
*) fail "group out of range after raw writes: $(root_value _DWM_KEYBOARD_GROUP)" ;;
esac
kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited after raw writes"

# 7c. dwm not reading (stopped): the helper gives up after about a second
# with exit 75. Once dwm runs again it takes the pending request.
request 0
wait_group '0, 3'
kill -STOP "$dwm_pid"
start=$(date +%s)
set +e
request next 2>"$work/timeout.err"
status=$?
set -e
kill -CONT "$dwm_pid"
elapsed=$(($(date +%s) - start))
[ "$status" -eq 75 ] || fail "helper exit $status while dwm was stopped, expected 75"
grep -q 'is dwm running' "$work/timeout.err" || fail "no timeout message"
[ "$elapsed" -le 3 ] || fail "helper took ${elapsed}s to give up"
wait_group '1, 3'
assert_no_request
request 0
wait_group '0, 3'

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

# With clamp wrapping a stale lock of 3 on three groups shows as group 2, and
# a relative switch starts from there, not from the raw lock. The server sends
# no event for a wrap change alone, so it is set before the keymap shrinks
# (it survives setxkbmap).
X setxkbmap -layout us,gr,de,ru -option ''
wait_group '0, 4'
request 3
wait_group '3, 4'
set_groups_wrap clamp
X setxkbmap -layout us,gr,de -option ''
wait_group '2, 3'
request next
wait_group '0, 3'
set_groups_wrap wrap

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
wait_watch_value keyboard_layouts 'us|gr'
X xprop -root -remove _XKB_RULES_NAMES
wait_state_value keyboard_layouts '|'
# the watcher follows the fallback too
wait_watch_value keyboard_layouts '|'
wait_state_value keyboard_names 'English (US)|Greek'
wait_state_value keyboard_groups 2

step=14
# 14. xmodmap adds groups without a new keyboard; only XkbMapNotify reports it.
X setxkbmap -layout us -option ''
wait_group '0, 1'
# step 11 left a lock of 3 behind; start from group 0
request 0
assert_no_request
sleep 0.3
names_before=$(count_lines '^_DWM_KEYBOARD_GROUP_NAMES' "$work/names.spy")
symbols_before=$(count_lines '^_DWM_KEYBOARD_SYMBOLS' "$work/names.spy")
X xmodmap -e 'keycode 38 = a A Greek_alpha Greek_ALPHA'
wait_group '0, 2'
X xmodmap -e 'keycode 38 = a A Greek_alpha Greek_ALPHA Cyrillic_ef Cyrillic_EF'
wait_group '0, 3'
# a new count rewrites the names, the unchanged symbols name stays; dwm writes
# the symbols before the names, so once the names arrived a symbols write
# would be in the spy output already
i=0
while [ "$i" -lt 100 ] &&
	[ "$(count_lines '^_DWM_KEYBOARD_GROUP_NAMES' "$work/names.spy")" -le "$names_before" ]; do
	i=$((i + 1))
	sleep 0.05
done
names_after=$(count_lines '^_DWM_KEYBOARD_GROUP_NAMES' "$work/names.spy")
symbols_after=$(count_lines '^_DWM_KEYBOARD_SYMBOLS' "$work/names.spy")
[ "$names_after" -gt "$names_before" ] || fail "names not rewritten for the new count"
[ "$symbols_before" = "$symbols_after" ] ||
	fail "unchanged symbols rewritten ($symbols_before -> $symbols_after)"

step=15
# 15. Selecting XkbMapNotify must not cost dwm the core MappingNotify it regrabs
# hotkeys on: after xmodmap moves k to another keycode, Super+k follows it.
X xmodmap -e 'keycode 45 = a A Greek_alpha Greek_ALPHA Cyrillic_ef Cyrillic_EF' \
	-e 'keycode 38 = k K Greek_kappa Greek_KAPPA Cyrillic_ka Cyrillic_KA'
sleep 0.5
wait_group '0, 3'
press_keys Super_L '#38'
wait_group '1, 3'
press_keys Super_L '#45'
sleep 0.3
wait_group '1, 3'

step=16
# 16. An options change renames the symbols but not the groups: only the
# symbols property is rewritten.
X setxkbmap -layout us,gr -option ''
# step 15 left group 1 locked
request 0
wait_group '0, 2'
sleep 0.3
names_before=$(count_lines '^_DWM_KEYBOARD_GROUP_NAMES' "$work/names.spy")
symbols_before=$(count_lines '^_DWM_KEYBOARD_SYMBOLS' "$work/names.spy")
X setxkbmap -layout us,gr -option grp:alt_shift_toggle
i=0
while [ "$i" -lt 100 ] && [ "$(count_lines '^_DWM_KEYBOARD_SYMBOLS' "$work/names.spy")" = "$symbols_before" ]; do
	i=$((i + 1))
	sleep 0.05
done
sleep 0.3
symbols_after=$(count_lines '^_DWM_KEYBOARD_SYMBOLS' "$work/names.spy")
names_after=$(count_lines '^_DWM_KEYBOARD_GROUP_NAMES' "$work/names.spy")
[ "$symbols_after" -gt "$symbols_before" ] || fail "symbols name not republished"
root_value _DWM_KEYBOARD_SYMBOLS | grep -q 'alt_shift_toggle' || fail "symbols name lacks the option"
[ "$names_before" = "$names_after" ] ||
	fail "unchanged names rewritten ($names_before -> $names_after)"

step=17
# 17. A layout set on one keyboard device, as Settings does: X copies it to
# the core keyboard at once when that device sent the last key, otherwise on
# its next key; then switching works from the device (grp: key) and from dwm.
X setxkbmap -layout us -option ''
request 0
wait_group '0, 1'
xtest_id=$(X xinput list --id-only 'Virtual core XTEST keyboard') ||
	fail "no XTEST keyboard device"
X setxkbmap -device "$xtest_id" -layout us,gr -option '' -option grp:caps_toggle
press_keys '#38'
wait_group '0, 2'
press_keys '#66'
wait_group '1, 2'
request next
wait_group '0, 2'
press_keys '#66'
wait_group '1, 2'

step=18
# 18. dwm survived all of it.
kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited"

printf '%s\n' "Keyboard layout Xvfb test: PASS"
