#!/bin/sh

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

wait_for_display() {
	i=0
	while [ "$i" -lt 100 ]; do
		if DISPLAY=$display xprop -root >/dev/null 2>&1; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "Xvfb did not become ready" >&2
	return 1
}

wait_for_root_property() {
	prop=$1
	i=0
	while [ "$i" -lt 100 ]; do
		if DISPLAY=$display xprop -root "$prop" 2>/dev/null |
			grep -qv 'not found'; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "root property did not appear: $prop" >&2
	return 1
}

wait_for_current_desktop() {
	expected=$1
	i=0
	while [ "$i" -lt 100 ]; do
		current=$(DISPLAY=$display xprop -root _NET_CURRENT_DESKTOP 2>/dev/null |
			sed -n 's/.*= //p')
		if [ "$current" = "$expected" ]; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "current desktop did not become $expected" >&2
	return 1
}

wait_for_window_state() {
	win=$1
	needle=$2
	i=0
	while [ "$i" -lt 100 ]; do
		if DISPLAY=$display xprop -id "$win" _NET_WM_STATE 2>/dev/null |
			grep -q "$needle"; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "window $win did not gain state $needle" >&2
	return 1
}

wait_for_window_state_absent() {
	win=$1
	needle=$2
	i=0
	while [ "$i" -lt 100 ]; do
		if ! DISPLAY=$display xprop -id "$win" _NET_WM_STATE 2>/dev/null |
			grep -q "$needle"; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "window $win retained state $needle" >&2
	return 1
}

wait_for_top_window() {
	expected=$1
	i=0
	while [ "$i" -lt 100 ]; do
		top=$(DISPLAY=$display xdotool search --class '^DwmXvfbRuntime$' 2>/dev/null |
			tail -n 1 || true)
		if [ -n "$top" ] && [ "$(printf '0x%x' "$top")" = "$expected" ]; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "window $expected did not reach the top of the stack" >&2
	return 1
}

wait_for_active_window() {
	expected_win=$1
	i=0
	while [ "$i" -lt 100 ]; do
		active=$(DISPLAY=$display xprop -root _NET_ACTIVE_WINDOW 2>/dev/null |
			sed -n 's/.*# //p')
		if [ "$active" = "$expected_win" ]; then
			return 0
		fi
		i=$((i + 1))
		sleep 0.05
	done
	printf '%s\n' "window $expected_win did not become active" >&2
	return 1
}

require_cmd Xvfb awk cc pkg-config xdotool xprop sed grep tail
pkg-config --exists x11

work=$(mktemp -d)
trap 'set +e; [ -n "${stack_client_pid:-}" ] && kill "$stack_client_pid" 2>/dev/null; [ -n "${above_client_pid:-}" ] && kill "$above_client_pid" 2>/dev/null; [ -n "${second_client_pid:-}" ] && kill "$second_client_pid" 2>/dev/null; [ -n "${client_pid:-}" ] && kill "$client_pid" 2>/dev/null; [ -n "${dwm_pid:-}" ] && kill "$dwm_pid" 2>/dev/null; [ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null; rm -rf "$work"' EXIT HUP INT TERM

home="$work/home"
mkdir -p "$home/.config/dwm-titus" "$home/.local/share/dwm-titus/config"
cp "$repo_dir/config/hotkeys.toml" "$home/.config/dwm-titus/hotkeys.toml"
cp "$repo_dir/config/themes.toml" "$home/.config/dwm-titus/themes.toml"
cp "$repo_dir/config/window-rules.toml" "$home/.config/dwm-titus/window-rules.toml"
cp "$repo_dir/config/"*.toml "$home/.local/share/dwm-titus/config/"

cat >"$work/xclient.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void
stop(int sig)
{
	(void)sig;
	running = 0;
}

int
main(int argc, char **argv)
{
	Display *dpy;
	Window win;
	XClassHint classhint;
	Atom wm_delete;
	XEvent ev;
	int set_hints = 1;
	int malformed_icon = 0;
	int initial_above = 0;
	int override_redirect = 0;

	signal(SIGTERM, stop);
	signal(SIGINT, stop);

	dpy = XOpenDisplay(NULL);
	if (!dpy)
		return 2;
	if ((argc == 3 && strcmp(argv[1], "fullscreen") == 0)
	|| (argc == 5 && strcmp(argv[1], "state") == 0)) {
		XEvent ev;
		Atom state = XInternAtom(dpy, "_NET_WM_STATE", False);
		Atom requested;
		long action = 1;

		win = strtoul(argv[2], NULL, 0);
		if (strcmp(argv[1], "fullscreen") == 0) {
			requested = XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", False);
		} else {
			action = strtol(argv[3], NULL, 10);
			requested = XInternAtom(dpy, argv[4], False);
		}
		memset(&ev, 0, sizeof(ev));
		ev.xclient.type = ClientMessage;
		ev.xclient.window = win;
		ev.xclient.message_type = state;
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = action;
		ev.xclient.data.l[1] = requested;
		XSendEvent(dpy, DefaultRootWindow(dpy), False,
			SubstructureRedirectMask | SubstructureNotifyMask, &ev);
		XFlush(dpy);
		XCloseDisplay(dpy);
		return 0;
	}
	if (argc == 2 && strcmp(argv[1], "minimal") == 0)
		set_hints = 0;
	else if (argc == 2 && strcmp(argv[1], "malformed-icon") == 0)
		malformed_icon = 1;
	else if (argc == 2 && strcmp(argv[1], "initial-above") == 0)
		initial_above = 1;
	else if (argc == 2 && strcmp(argv[1], "override") == 0)
		override_redirect = 1;

	win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy),
		20, 20, 320, 180, 0, 0, WhitePixel(dpy, DefaultScreen(dpy)));
	if (override_redirect) {
		XSetWindowAttributes attributes = { .override_redirect = True };

		XChangeWindowAttributes(dpy, win, CWOverrideRedirect, &attributes);
	}
	if (set_hints) {
		XStoreName(dpy, win, "dwm-xvfb-runtime");
		classhint.res_name = "dwm-xvfb-runtime";
		classhint.res_class = "DwmXvfbRuntime";
		XSetClassHint(dpy, win, &classhint);
	}
	if (malformed_icon) {
		unsigned long icon[] = { 8, 8, 0xff00ff00 };
		Atom net_wm_icon = XInternAtom(dpy, "_NET_WM_ICON", False);
		XChangeProperty(dpy, win, net_wm_icon, XA_CARDINAL, 32,
			PropModeReplace, (unsigned char *)icon, 3);
	}
	if (initial_above) {
		Atom states[2];

		states[0] = XInternAtom(dpy, "_NET_WM_STATE_ABOVE", False);
		states[1] = XInternAtom(dpy, "_NET_WM_STATE_STAYS_ON_TOP", False);
		XChangeProperty(dpy, win, XInternAtom(dpy, "_NET_WM_STATE", False),
			XA_ATOM, 32, PropModeReplace, (unsigned char *)states, 2);
	}
	wm_delete = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
	XSetWMProtocols(dpy, win, &wm_delete, 1);
	XSelectInput(dpy, win, StructureNotifyMask);
	XMapWindow(dpy, win);
	XFlush(dpy);

	printf("0x%lx\n", win);
	fflush(stdout);

	while (running) {
		while (XPending(dpy)) {
			XNextEvent(dpy, &ev);
			if (ev.type == DestroyNotify)
				running = 0;
		}
		usleep(50000);
	}

	XDestroyWindow(dpy, win);
	XCloseDisplay(dpy);
	return 0;
}
EOF
# shellcheck disable=SC2046
cc "$work/xclient.c" -o "$work/xclient" $(pkg-config --cflags --libs x11)

display=":$((($$ % 500) + 150))"
Xvfb "$display" -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	>"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
wait_for_display

DISPLAY=$display \
	HOME=$home \
	PATH="$repo_dir:$PATH" \
	"$repo_dir/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

wait_for_root_property _NET_SUPPORTED
wait_for_root_property _NET_NUMBER_OF_DESKTOPS
wait_for_current_desktop 0
DISPLAY=$display xprop -root _NET_SUPPORTED | grep -q _NET_WM_STATE_ABOVE
DISPLAY=$display xprop -root _NET_SUPPORTED | grep -q _NET_WM_STATE_STAYS_ON_TOP

DISPLAY=$display "$work/xclient" >"$work/window-id" 2>"$work/xclient.log" &
client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
win=$(cat "$work/window-id")
[ -n "$win" ]

wait_for_active_window "$win"
DISPLAY=$display xprop -root _NET_CLIENT_LIST | grep -q "$win"

DISPLAY=$display xdotool key Super+2
wait_for_current_desktop 1

printf '%s\n' \
	'keys = [' \
	'  { mod="SUPER", key="1", desc="Xvfb tag 1", func="view", ui=1 },' \
	'  { mod="SUPER", key="m", desc="Xvfb fullscreen", func="fullscreen" },' \
	'  { mod="SUPER", key="o", desc="Xvfb monocle", func="setlayout", layout_idx=2 },' \
	'  { mod="SUPER", key="t", desc="Xvfb tile", func="setlayout", layout_idx=0 },' \
	'  { mod="SUPER", key="f", desc="Xvfb toggle floating", func="togglefloating" },' \
	'  { mod="SUPER", key="v", desc="Xvfb mouse resize", func="resizemouse" },' \
	'  { mod="SUPER", key="u", desc="Xvfb reload tag", func="view", ui=16 },' \
	']' >"$home/.config/dwm-titus/hotkeys.toml"
kill -USR1 "$dwm_pid"
sleep 0.2
DISPLAY=$display xdotool key Super+u
wait_for_current_desktop 4

DISPLAY=$display xdotool key Super+1
wait_for_current_desktop 0

printf '%s\n' '=' >"$home/.config/dwm-titus/hotkeys.toml"
kill -USR1 "$dwm_pid"
sleep 0.2
DISPLAY=$display xdotool key Super+u
wait_for_current_desktop 4
DISPLAY=$display xdotool key Super+1
wait_for_current_desktop 0

wait_for_active_window "$win"
DISPLAY=$display xdotool key Super+o
sleep 0.2
monocle_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$win")
monocle_width=$(printf '%s\n' "$monocle_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
monocle_height=$(printf '%s\n' "$monocle_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')

DISPLAY=$display xdotool mousemove --window "$win" 100 100
DISPLAY=$display xdotool key Super+v
sleep 0.05
DISPLAY=$display xdotool mousemove_relative --sync 120 90
DISPLAY=$display xdotool click 3
sleep 0.2

floating_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$win")
floating_width=$(printf '%s\n' "$floating_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
floating_height=$(printf '%s\n' "$floating_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
if [ "$floating_width" -ge "$monocle_width" ] || [ "$floating_height" -ge "$monocle_height" ]; then
	printf '%s\n' "monocle mouse resize did not fall back to floating resize" >&2
	exit 1
fi

DISPLAY=$display xdotool key Super+t
DISPLAY=$display xdotool key Super+f
sleep 0.2
single_tiled_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$win")
single_tiled_width=$(printf '%s\n' "$single_tiled_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
single_tiled_height=$(printf '%s\n' "$single_tiled_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')

DISPLAY=$display xdotool mousemove --window "$win" 100 100
DISPLAY=$display xdotool key Super+v
sleep 0.05
DISPLAY=$display xdotool mousemove_relative --sync 120 90
DISPLAY=$display xdotool click 3
sleep 0.2

single_floating_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$win")
single_floating_width=$(printf '%s\n' "$single_floating_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
single_floating_height=$(printf '%s\n' "$single_floating_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
if [ "$single_floating_width" -ge "$single_tiled_width" ] || [ "$single_floating_height" -ge "$single_tiled_height" ]; then
	printf '%s\n' "single tiled client mouse resize did not fall back to floating resize" >&2
	exit 1
fi

DISPLAY=$display xdotool key Super+f
DISPLAY=$display "$work/xclient" >"$work/second-window-id" 2>"$work/second-client.log" &
second_client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/second-window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
second_win=$(cat "$work/second-window-id")
[ -n "$second_win" ]
wait_for_active_window "$second_win"

two_tiled_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$second_win")
two_tiled_width=$(printf '%s\n' "$two_tiled_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
two_tiled_height=$(printf '%s\n' "$two_tiled_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
outer_x=$((two_tiled_width - 100))

DISPLAY=$display xdotool mousemove --window "$second_win" "$outer_x" 100
DISPLAY=$display xdotool key Super+v
sleep 0.05
DISPLAY=$display xdotool mousemove_relative --sync -- -120 90
DISPLAY=$display xdotool click 3
sleep 0.2

two_floating_geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$second_win")
two_floating_width=$(printf '%s\n' "$two_floating_geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
two_floating_height=$(printf '%s\n' "$two_floating_geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
if [ "$two_floating_width" -ge "$two_tiled_width" ] || [ "$two_floating_height" -ge "$two_tiled_height" ]; then
	printf '%s\n' "outer-edge tiled resize without an adjustable split did not fall back to floating resize" >&2
	exit 1
fi

kill "$second_client_pid"
wait "$second_client_pid" 2>/dev/null || true
second_client_pid=
wait_for_active_window "$win"

DISPLAY=$display "$work/xclient" fullscreen "$win"
wait_for_window_state "$win" _NET_WM_STATE_FULLSCREEN

kill "$client_pid"
wait "$client_pid" 2>/dev/null || true
client_pid=

DISPLAY=$display "$work/xclient" minimal >"$work/minimal-window-id" 2>"$work/minimal-client.log" &
client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/minimal-window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
minimal_win=$(cat "$work/minimal-window-id")
[ -n "$minimal_win" ]
wait_for_active_window "$minimal_win"
DISPLAY=$display xprop -root _NET_CLIENT_LIST | grep -q "$minimal_win"

kill "$client_pid"
wait "$client_pid" 2>/dev/null || true
client_pid=

DISPLAY=$display "$work/xclient" malformed-icon >"$work/icon-window-id" 2>"$work/icon-client.log" &
client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/icon-window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
icon_win=$(cat "$work/icon-window-id")
[ -n "$icon_win" ]
wait_for_active_window "$icon_win"
DISPLAY=$display xprop -root _NET_CLIENT_LIST | grep -q "$icon_win"
kill -0 "$dwm_pid"

DISPLAY=$display "$work/xclient" initial-above >"$work/above-window-id" 2>"$work/above-client.log" &
above_client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/above-window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
above_win=$(cat "$work/above-window-id")
[ -n "$above_win" ]
wait_for_window_state "$above_win" _NET_WM_STATE_ABOVE
wait_for_window_state "$above_win" _NET_WM_STATE_STAYS_ON_TOP
DISPLAY=$display "$work/xclient" override >"$work/stack-window-id" 2>"$work/stack-client.log" &
stack_client_pid=$!
i=0
while [ "$i" -lt 100 ] && [ ! -s "$work/stack-window-id" ]; do
	i=$((i + 1))
	sleep 0.05
done
stack_win=$(cat "$work/stack-window-id")
[ -n "$stack_win" ]
wait_for_top_window "$stack_win"
DISPLAY=$display xdotool key Super+t
wait_for_top_window "$above_win"

DISPLAY=$display "$work/xclient" state "$above_win" 0 _NET_WM_STATE_STAYS_ON_TOP
wait_for_window_state_absent "$above_win" _NET_WM_STATE_STAYS_ON_TOP
wait_for_top_window "$above_win"

DISPLAY=$display "$work/xclient" state "$above_win" 0 _NET_WM_STATE_ABOVE
wait_for_window_state_absent "$above_win" _NET_WM_STATE_ABOVE
DISPLAY=$display xdotool windowraise "$stack_win"
wait_for_top_window "$stack_win"

DISPLAY=$display "$work/xclient" state "$above_win" 1 _NET_WM_STATE_STAYS_ON_TOP
wait_for_window_state "$above_win" _NET_WM_STATE_STAYS_ON_TOP
wait_for_top_window "$above_win"
DISPLAY=$display "$work/xclient" fullscreen "$above_win"
wait_for_window_state "$above_win" _NET_WM_STATE_FULLSCREEN
wait_for_window_state "$above_win" _NET_WM_STATE_STAYS_ON_TOP
DISPLAY=$display "$work/xclient" state "$above_win" 0 _NET_WM_STATE_FULLSCREEN
wait_for_window_state_absent "$above_win" _NET_WM_STATE_FULLSCREEN
wait_for_window_state "$above_win" _NET_WM_STATE_STAYS_ON_TOP

kill "$stack_client_pid"
wait "$stack_client_pid" 2>/dev/null || true
stack_client_pid=
kill "$above_client_pid"
wait "$above_client_pid" 2>/dev/null || true
above_client_pid=

printf '%s\n' "Xvfb runtime smoke: PASS"
