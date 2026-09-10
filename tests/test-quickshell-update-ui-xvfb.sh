#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_UPDATE_UI_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_UPDATE_UI_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
xvfb_pid=
cleanup() {
	if [ -n "$xvfb_pid" ]; then
		kill "$xvfb_pid" 2>/dev/null || true
		wait "$xvfb_pid" 2>/dev/null || true
	fi
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work/qml" "$work/home/.config/dwm-titus" \
	"$work/data/dwm-titus/scripts" "$work/runtime" "$work/state"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/settings" \
	"$repo/config/quickshell/systemmanagement" "$repo/config/quickshell/network" "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/dwm-titus/"
cp "$repo/tests/qml/SystemUpdateUi.qml" "$work/qml/shell.qml"
cp "$repo/tests/fixtures/system-update-ui-provider.py" "$work/data/dwm-titus/scripts/dwm-system-management"
chmod +x "$work/data/dwm-titus/scripts/dwm-system-management"
Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display_number=$(sed -n '1p' "$work/display")
case $display_number in
'' | *[!0-9]*)
	cat "$work/xvfb.log" >&2
	exit 1
	;;
esac

status=0
timeout --foreground --kill-after=2s 35s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/data" XDG_RUNTIME_DIR="$work/runtime" \
	QT_QPA_PLATFORMTHEME= DWM_UPDATE_UI_FIXTURE="$work/state" \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Update UI native tests: PASS' "$work/ui.log" ||
	grep -Fq 'Update UI FAILED:' "$work/ui.log" ||
	[ "$(sed -n '1p' "$work/state/origins" 2>/dev/null)" != 3 ] ||
	[ -e "$work/state/invalid-arguments" ] || [ -e "$work/state/overlap" ]; then
	cat "$work/ui.log" >&2
	exit 1
fi
