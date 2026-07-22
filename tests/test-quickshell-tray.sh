#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)

panel=$repo/config/quickshell/panel/DwmPanel.qml
tray_area=$repo/config/quickshell/panel/TrayArea.qml
tray_item=$repo/config/quickshell/panel/TrayItem.qml
running_area=$repo/config/quickshell/panel/RunningAppsArea.qml
running_item=$repo/config/quickshell/panel/RunningAppItem.qml
shell=$repo/config/quickshell/shell.qml

grep -Fq 'TrayArea {}' "$panel"
grep -Fq 'model: SystemTray.items.values' "$tray_area"
grep -Fq 'trayItem: modelData' "$tray_area"
grep -Fq 'property var iconSources: Icons.trayIconSources(root.trayItem)' "$tray_item"
grep -Fq 'status === Image.Error' "$tray_item"
grep -Fq 'root.iconSourceIndex += 1;' "$tray_item"
grep -Fq 'visible: !trayIcon.visible' "$tray_item"
grep -Fq 'Qt.LeftButton | Qt.MiddleButton | Qt.RightButton' "$tray_item"
grep -Fq 'import Quickshell.Services.SystemTray' "$shell"
grep -Fq 'target: "tray"' "$shell"
grep -Fq 'return SystemTray.items.values.length;' "$shell"

if grep -Fq 'SystemTray' "$running_area" || grep -Fq 'trayItems' "$running_item"; then
	printf 'Running-window items must not replace the independent system tray.\n' >&2
	exit 1
fi

printf 'Quickshell system tray: PASS\n'
