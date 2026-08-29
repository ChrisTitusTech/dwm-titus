#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
quickshell=$repo/config/quickshell

for surface in \
	settings/SettingsWindow.qml \
	health/SystemHealthWindow.qml \
	notifications/NotificationHistoryWindow.qml \
	launcher/LauncherWindow.qml; do
	grep -Fq 'LargeSurfaceHeader {' "$quickshell/$surface"
done

grep -Fq 'title: "dwm settings"' "$quickshell/settings/SettingsWindow.qml"
grep -Fq 'id: sectionHeader' "$quickshell/settings/SettingsWindow.qml"
grep -Fq 'id: sectionContent' "$quickshell/settings/SettingsWindow.qml"
grep -Fq 'anchors.margins: Theme.spacingLg' "$quickshell/settings/SettingsWindow.qml"
grep -Fq 'height: Math.max(68, cardColumn.implicitHeight + 12)' \
	"$quickshell/settings/SettingsWindow.qml"
grep -Fq 'Layout.preferredHeight: Math.max(88, outputContent.implicitHeight + 12)' \
	"$quickshell/settings/DisplaySettingsPane.qml"
if grep -Fq 'label: root.settingsModel.selectedSectionId' \
	"$quickshell/settings/SettingsWindow.qml"; then
	printf 'Settings right pane still renders the selected section twice\n' >&2
	exit 1
fi
grep -Fq 'title: "dwm system health"' "$quickshell/health/SystemHealthWindow.qml"
grep -Fq 'title: "dwm notification history"' "$quickshell/notifications/NotificationHistoryWindow.qml"
grep -Fq 'title: "dwm launcher"' "$quickshell/launcher/LauncherWindow.qml"

grep -Fq 'NotificationUrgency.Critical' "$quickshell/notifications/NotificationCard.qml"
grep -Fq 'onDismiss: root.notificationModel.dismiss' "$quickshell/notifications/NotificationPopupWindow.qml"
grep -Fq 'onExpired: root.notificationModel.expire' "$quickshell/notifications/NotificationPopupWindow.qml"
grep -Fq 'onClicked: root.launcherModel.launchApp' "$quickshell/launcher/LauncherResultDelegate.qml"
grep -Fq 'onActivated: root.healthModel.confirmRepair()' "$quickshell/health/SystemHealthWindow.qml"
grep -Fq 'onActivated: root.settingsModel.revertPreview()' "$quickshell/settings/DisplaySettingsPane.qml"

if grep -ERq 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$quickshell/settings" "$quickshell/health" "$quickshell/notifications" \
	"$quickshell/launcher" "$quickshell/core/LargeSurfaceHeader.qml"; then
	printf 'Large surfaces introduced a forbidden Wayland or Omarchy runtime dependency\n' >&2
	exit 1
fi

if grep -Eq 'Process[[:space:]]*\{|command:' "$quickshell/core/LargeSurfaceHeader.qml"; then
	printf 'LargeSurfaceHeader must remain presentation-only\n' >&2
	exit 1
fi

printf 'Quickshell large-surface source contract: PASS\n'
