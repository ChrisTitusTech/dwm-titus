#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

for command_name in Xvfb dbus-run-session quickshell xprop pgrep getconf cc pkg-config; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if ! pkg-config --exists x11; then
	printf 'SKIP: X11 development files are unavailable\n'
	exit 77
fi

if [ "${DWM_BAR_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_BAR_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
cleanup() {
	set +e
	for child_pid in "${client_pid:-}" "${quickshell_pid:-}" "${dwm_pid:-}" "${xvfb_pid:-}"; do
		[ -n "$child_pid" ] && kill "$child_pid" 2>/dev/null
	done
	for child_pid in "${client_pid:-}" "${quickshell_pid:-}" "${dwm_pid:-}" "${xvfb_pid:-}"; do
		[ -n "$child_pid" ] && wait "$child_pid" 2>/dev/null
	done
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

wait_for_managed_geometry() {
	window=$1
	index=0
	while [ "$index" -lt 100 ]; do
		geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window" 2>/dev/null || true)
		window_y=$(printf '%s\n' "$geometry" | awk -F= '$1 == "Y" { print $2 }')
		window_height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
		if [ -n "$window_y" ] && [ -n "$window_height" ] && [ "$window_y" -ge 30 ] &&
			[ $((window_y + window_height)) -le 800 ]; then
			printf '%s\n' "$geometry"
			return 0
		fi
		index=$((index + 1))
		sleep 0.05
	done
	printf 'Client window was not tiled below the 30 px panel\n' >&2
	return 1
}

wait_for_panel_state() {
	window=$1
	state=$2
	index=0
	while [ "$index" -lt 100 ]; do
		if DISPLAY=$display xprop -id "$window" _NET_WM_STATE 2>/dev/null | grep -Fq "$state"; then
			return 0
		fi
		index=$((index + 1))
		sleep 0.05
	done
	printf 'Panel window did not enter %s\n' "$state" >&2
	return 1
}

wait_for_stacking_order() {
	first=$1
	second=$2
	index=0
	while [ "$index" -lt 100 ]; do
		if [ "$(DISPLAY=$display "$work/xclient" above "$first" "$second" 2>/dev/null || true)" = 1 ]; then
			return 0
		fi
		index=$((index + 1))
		sleep 0.05
	done
	printf 'Window %s was not stacked above %s\n' "$first" "$second" >&2
	return 1
}

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
	"$repo/scripts/dwm-display-setup" "$repo/scripts/dwm-quickshell-controlcenter" \
	"$repo/scripts/dwm-quickshell-controls" "$repo/scripts/dwm-quickshell-network" \
	"$repo/scripts/dwm-diagnostics" "$repo/scripts/dwm-lock" \
	"$data_home/dwm-titus/scripts/"

cat >"$work/xclient.c" <<'EOF'
#define _DEFAULT_SOURCE
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t running = 1;

static void stop(int signal_number) {
    (void)signal_number;
    running = 0;
}

int main(int argc, char **argv) {
    Display *display = XOpenDisplay(NULL);
    Window root;

    if (!display) return 2;
    root = DefaultRootWindow(display);

    if (argc == 2 && strcmp(argv[1], "panel") == 0) {
        Window root_return, parent_return, *children = NULL;
        unsigned int child_count = 0;
        unsigned int index;

        if (!XQueryTree(display, root, &root_return, &parent_return, &children, &child_count)) {
            XCloseDisplay(display);
            return 3;
        }
        for (index = 0; index < child_count; index++) {
            XWindowAttributes attributes;
            if (!XGetWindowAttributes(display, children[index], &attributes)) continue;
            if (attributes.map_state == IsViewable && attributes.x == 0 && attributes.y == 0
                && attributes.width == 1280 && attributes.height == 30) {
                printf("0x%lx\n", children[index]);
                if (children) XFree(children);
                XCloseDisplay(display);
                return 0;
            }
        }
        if (children) XFree(children);
        XCloseDisplay(display);
        return 1;
    }

    if (argc == 4 && strcmp(argv[1], "above") == 0) {
        Window root_return, parent_return, *children = NULL;
        Window first = strtoul(argv[2], NULL, 0);
        Window second = strtoul(argv[3], NULL, 0);
        unsigned int child_count = 0;
        int first_index = -1, second_index = -1;
        unsigned int index;

        if (!XQueryTree(display, root, &root_return, &parent_return, &children, &child_count)) {
            XCloseDisplay(display);
            return 3;
        }
        for (index = 0; index < child_count; index++) {
            if (children[index] == first) first_index = (int)index;
            if (children[index] == second) second_index = (int)index;
        }
        if (children) XFree(children);
        printf("%d\n", first_index >= 0 && second_index >= 0 && first_index > second_index);
        XCloseDisplay(display);
        return 0;
    }

    if (argc == 3 && strcmp(argv[1], "fullscreen") == 0) {
        XEvent event;
        Atom state = XInternAtom(display, "_NET_WM_STATE", False);

        memset(&event, 0, sizeof(event));
        event.xclient.type = ClientMessage;
        event.xclient.window = strtoul(argv[2], NULL, 0);
        event.xclient.message_type = state;
        event.xclient.format = 32;
        event.xclient.data.l[0] = 1;
        event.xclient.data.l[1] = XInternAtom(display, "_NET_WM_STATE_FULLSCREEN", False);
        XSendEvent(display, root, False, SubstructureRedirectMask | SubstructureNotifyMask, &event);
        XFlush(display);
        XCloseDisplay(display);
        return 0;
    }

    {
        Window window = XCreateSimpleWindow(display, root, 20, 20, 320, 180, 0, 0,
            WhitePixel(display, DefaultScreen(display)));
        XStoreName(display, window, "dwm quickshell bar xvfb client");
        XSelectInput(display, window, ExposureMask);
        XMapWindow(display, window);
        XFlush(display);
        printf("0x%lx\n", window);
        fflush(stdout);
        signal(SIGINT, stop);
        signal(SIGTERM, stop);
        while (running) {
            XEvent event;
            if (XPending(display)) XNextEvent(display, &event);
            else usleep(10000);
        }
        XDestroyWindow(display, window);
    }
    XCloseDisplay(display);
    return 0;
}
EOF
# shellcheck disable=SC2046 # pkg-config emits separate compiler arguments.
cc -std=c99 -Wall -Wextra -Werror "$work/xclient.c" $(pkg-config --cflags --libs x11) -o "$work/xclient"

Xvfb -displayfd 3 -screen 0 1280x800x24 -nolisten tcp -extension GLX \
	3>"$work/display-number" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!

index=0
while [ "$index" -lt 100 ]; do
	if [ -s "$work/display-number" ]; then
		break
	fi
	if ! kill -0 "$xvfb_pid" 2>/dev/null; then
		printf 'Spawned Xvfb exited before allocating a display\n' >&2
		cat "$work/xvfb.log" >&2
		exit 1
	fi
	index=$((index + 1))
	sleep 0.05
done
[ -s "$work/display-number" ]
display=":$(cat "$work/display-number")"
kill -0 "$xvfb_pid"
DISPLAY=$display xprop -root >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_AUTOSTART_NO_INPUT_WATCH=1 \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	PATH="$data_home/dwm-titus/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

config=$config_home/quickshell/shell.qml
index=0
while [ "$index" -lt 200 ]; do
	height=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call bar height 2>/dev/null || true)
	[ "$height" = 30 ] && break
	index=$((index + 1))
	sleep 0.05
done
if [ "${height:-}" != 30 ]; then
	printf 'Bar IPC did not report its 30 px height\n' >&2
	tail -60 "$work/quickshell.log" >&2
	exit 1
fi

expected_layout='logo,workspaces|clock|running-apps,bluetooth,network,volume'
index=0
while [ "$index" -lt 100 ]; do
	layout=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call bar layout 2>/dev/null || true)
	[ "$layout" = "$expected_layout" ] && break
	index=$((index + 1))
	sleep 0.05
done
if [ "${layout:-}" != "$expected_layout" ]; then
	printf 'Bar IPC reported an unexpected instantiated layout: %s\n' "${layout:-<empty>}" >&2
	exit 1
fi
managed_quickshell_pids=$(pgrep -P "$$" -x quickshell || true)
[ "$managed_quickshell_pids" = "$quickshell_pid" ]

if ! command -v xdotool >/dev/null 2>&1; then
	printf 'SKIP: xdotool is unavailable after bar IPC/runtime checks\n'
	exit 77
fi

index=0
while [ "$index" -lt 100 ]; do
	panel=$(DISPLAY=$display "$work/xclient" panel 2>/dev/null || true)
	[ -n "$panel" ] && break
	index=$((index + 1))
	sleep 0.05
done
if [ -z "${panel:-}" ]; then
	printf 'DwmPanel window was not found\n' >&2
	exit 1
fi

DISPLAY=$display "$work/xclient" >"$work/client-window-id" 2>"$work/client.log" &
client_pid=$!
index=0
while [ "$index" -lt 100 ] && [ ! -s "$work/client-window-id" ]; do
	index=$((index + 1))
	sleep 0.05
done
client=$(cat "$work/client-window-id")
[ -n "$client" ]

geometry=$(wait_for_managed_geometry "$client")
client_y=$(printf '%s\n' "$geometry" | awk -F= '$1 == "Y" { print $2 }')
client_height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
[ "$client_y" -ge 30 ]
[ $((client_y + client_height)) -le 800 ]

wait_for_panel_state "$panel" _NET_WM_STATE_ABOVE

DISPLAY=$display "$work/xclient" fullscreen "$client"
index=0
while [ "$index" -lt 100 ]; do
	if DISPLAY=$display xprop -id "$client" _NET_WM_STATE 2>/dev/null | grep -Fq '_NET_WM_STATE_FULLSCREEN'; then
		break
	fi
	index=$((index + 1))
	sleep 0.05
done
DISPLAY=$display xprop -id "$client" _NET_WM_STATE | grep -Fq '_NET_WM_STATE_FULLSCREEN'
# Quickshell EWMH hints vary by build; verify DWM state and observable X stacking.
DISPLAY=$display xprop -root _DWM_FULLSCREEN_MONITORS | grep -Eq '= 0|= 0,'
wait_for_stacking_order "$client" "$panel"

kill "$client_pid"
wait "$client_pid" 2>/dev/null || true
client_pid=

clock_ticks=$(getconf CLK_TCK)
before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
sleep 2
after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
cpu_percent=$(awk -v delta="$((after - before))" -v ticks="$clock_ticks" \
	'BEGIN { printf "%.2f", (delta * 100) / (ticks * 2) }')
awk -v cpu="$cpu_percent" 'BEGIN { exit !(cpu < 10.0) }'

printf 'Quickshell bar Xvfb and closed-idle sample: PASS (%s%% CPU)\n' "$cpu_percent"
