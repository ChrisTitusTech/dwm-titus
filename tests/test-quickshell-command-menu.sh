#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)

catalog=$repo/config/quickshell/launcher/CommandMenuCatalog.js
model=$repo/config/quickshell/launcher/CommandMenuModel.qml
window=$repo/config/quickshell/launcher/CommandMenuWindow.qml
shell=$repo/config/quickshell/shell.qml

for label in Apps Settings 'Display / Input' Network Bluetooth Audio \
	'System Health' Keybindings Screenshots System; do
	grep -Fq "\"label\": \"$label\"" "$catalog"
done

grep -Fq '"actionType": "ipc"' "$catalog"
grep -Fq '"actionType": "helper"' "$catalog"
grep -Fq '"kind": "application"' "$model"
grep -Fq 'Commands.screenshotHelperCommand(entry.action)' "$model"
grep -Fq 'Commands.lockHelperCommand()' "$model"
grep -Fq 'target: "menu"' "$shell"
menu_handler=$(awk '
	/target: "menu"/ { in_menu = 1; seen_menu = 1 }
	in_menu && seen_menu && /^    IpcHandler \{/ { exit }
	in_menu { print }
' "$shell")
for action in close open toggle summon; do
	printf '%s\n' "$menu_handler" | grep -Fq "function $action(): void"
done
grep -Fq 'title: "dwm menu"' "$window"
grep -Fq 'title="dwm menu"' "$repo/config/window-rules.toml"
grep -Fq 'target: "launcher"' "$shell"
grep -Eq 'key="r".*call launcher toggle' "$repo/config/hotkeys.toml"
if grep -Eq 'call menu (open|toggle|summon)' "$repo/config/hotkeys.toml"; then
	printf '%s\n' 'Command menu unexpectedly replaced or added a default hotkey.' >&2
	exit 1
fi

if grep -REn \
	-e 'Quickshell\.(Wayland|Hyprland)' \
	-e 'WlrLayershell' \
	-e '(^|[^[:alnum:]_-])(hyprctl|uwsm-app|wl-copy|wl-paste)([^[:alnum:]_-]|$)' \
	-e '"command"[[:space:]]*:' \
	"$catalog"; then
	printf '%s\n' 'Command catalog contains a compositor-specific or raw command backend.' >&2
	exit 1
fi

qml_runner=
for candidate in qml qml6 /usr/lib64/qt6/bin/qml /usr/lib/qt6/bin/qml; do
	if command -v "$candidate" >/dev/null 2>&1; then
		qml_runner=$(command -v "$candidate")
		break
	fi
done

if [ -n "$qml_runner" ]; then
	QT_QPA_PLATFORM=offscreen "$qml_runner" "$repo/tests/quickshell-command-menu-catalog.qml"
	printf '%s\n' 'Quickshell command menu: PASS'
else
	printf '%s\n' 'SKIP: Qt 6 qml runner is unavailable; catalog runtime assertions were not run.'
fi
