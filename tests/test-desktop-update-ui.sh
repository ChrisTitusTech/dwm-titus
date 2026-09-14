#!/bin/sh
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${DWM_DESKTOP_UI_SESSION:-0}" != 1 ]; then
	exec env DWM_DESKTOP_UI_SESSION=1 dbus-run-session -- "$0"
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
trap 'exit 130' INT
trap 'exit 143' TERM HUP
mkdir -p "$work/qml" "$work/bin" "$work/home" "$work/state" "$work/runtime"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/settings" "$repo/config/quickshell/network" "$work/qml/"
cp "$repo/tests/qml/DesktopUpdateUi.qml" "$work/qml/shell.qml"
cp "$repo/tests/fixtures/desktop-update-provider.py" "$work/bin/dwm-desktop-update"
chmod 755 "$work/bin/dwm-desktop-update"
# Inject the provider explicitly into this isolated model copy. Production
# commands validate the root-owned installation instead of resolving a fixture.
/usr/bin/python3 - "$work" <<'PYTHON'
import json, sys
from pathlib import Path
work = Path(sys.argv[1])
model = work / "qml/settings/DesktopUpdateModel.qml"
text = model.read_text().replace(
    'readonly property var updaterCommand: ["/usr/bin/python3", "-I", "-c", updaterBootstrap]',
    'readonly property var updaterCommand: ' + json.dumps(["/usr/bin/python3", "-I", str(work / "bin/dwm-desktop-update")]))
model.write_text(text)
PYTHON
Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
attempt=0
while [ ! -s "$work/display" ] && [ "$attempt" -lt 100 ]; do
	attempt=$((attempt + 1))
	sleep 0.05
done
display=$(sed -n '1p' "$work/display")
case $display in
'' | *[!0-9]*)
	cat "$work/xvfb.log" >&2
	exit 1
	;;
esac
status=0
timeout --kill-after=2s 20s env DISPLAY=":$display" PATH="$work/bin:$PATH" \
	HOME="$work/home" XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
	QT_QPA_PLATFORM=xcb QT_QPA_PLATFORMTHEME= quickshell --no-duplicate --path "$work/qml/shell.qml" \
	>"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -Fq 'Desktop update UI: PASS' "$work/ui.log" ||
	grep -Fq 'Desktop UI FAILED:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Desktop update UI: PASS\n'
