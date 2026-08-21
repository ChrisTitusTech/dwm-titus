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
grep -Fq 'dwmState.focusedScreen()' "$shell"
grep -Fq 'function focusedScreen()' "$repo/config/quickshell/state/DwmState.qml"
grep -Fq 'function refreshApplicationIndex()' "$repo/config/quickshell/launcher/LauncherModel.qml"
grep -Fq 'root.refreshApplicationIndex()' "$repo/config/quickshell/launcher/LauncherModel.qml"
grep -Fq '{ title="dwm menu", isfloating=1, alwaysontop=1 },' "$repo/docs/OMARCHY-UI-ADAPTATION.md"
grep -Fq 'menu open|close|toggle|summon' "$repo/CHANGELOG.md"
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
for candidate in /usr/lib64/qt6/bin/qml /usr/lib/qt6/bin/qml qml6 qml; do
	if command -v "$candidate" >/dev/null 2>&1; then
		candidate_path=$(command -v "$candidate")
		if [ "$candidate" = qml ]; then
			candidate_version=$("$candidate_path" --version 2>&1 || true)
			case $candidate_version in
			*' 6.'* | *'Qt 6'*) ;;
			*) continue ;;
			esac
		fi
		qml_runner=$candidate_path
		break
	fi
done

if [ -n "$qml_runner" ]; then
	QT_QPA_PLATFORM=offscreen "$qml_runner" "$repo/tests/quickshell-command-menu-catalog.qml"
	printf '%s\n' 'Quickshell command menu: PASS'
else
	printf '%s\n' 'SKIP: Qt 6 qml runner is unavailable; catalog runtime assertions were not run.'
fi
