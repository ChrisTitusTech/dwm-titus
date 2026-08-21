#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core=$repo/config/quickshell/core
panel=$repo/config/quickshell/panel
controls=$repo/config/quickshell/controls
network=$repo/config/quickshell/network
controlcenter=$repo/config/quickshell/controlcenter
power=$repo/config/quickshell/power

for component in PanelHero PanelSeparator PanelSlider PanelToggleSwitch; do
	test -f "$core/$component.qml"
done

grep -Fq 'readonly property int panelHeight: 30' "$core/Theme.qml"
grep -Fq 'exclusiveZone: Theme.panelHeight' "$panel/DwmPanel.qml"
grep -Fq 'aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(' "$panel/DwmPanel.qml"
grep -Fq 'signal popupRequested(var panelWindow, string popupId)' "$panel/DwmPanel.qml"
grep -Fq 'model: root.state.workspaceIndexes(root.screen)' "$panel/DwmPanel.qml"
grep -Fq 'sourceComponent: TrayArea {}' "$panel/DwmPanel.qml"
grep -Fq 'RunningAppsArea { state: root.state }' "$panel/DwmPanel.qml"

grep -Fq 'outlined: true' "$panel/DwmPanel.qml"
grep -Fq 'outlined ? Theme.controlNormalFill : Theme.transparent' "$core/PanelPill.qml"
grep -Fq 'Theme.controlSelectedFill' "$panel/WorkspaceButton.qml"
grep -Fq 'Theme.controlSelectedFill' "$panel/RunningAppItem.qml"
grep -Fq 'Theme.controlHoverFill' "$panel/TrayItem.qml"

grep -Fq 'PanelHero {' "$controls/ControlsWindow.qml"
grep -Fq 'title: "Audio"' "$controls/ControlsWindow.qml"
grep -Fq 'PanelSlider {' "$controls/ControlsWindow.qml"
grep -Fq 'root.controlsModel.volumeSet(Math.round(value))' "$controls/ControlsWindow.qml"
grep -Fq 'PanelHero {' "$controls/BluetoothWindow.qml"
grep -Fq 'PanelToggleSwitch {' "$controls/BluetoothWindow.qml"
grep -Fq 'root.bluetoothModel.action("bluetooth-power", [checked ? "off" : "on"])' \
	"$controls/BluetoothWindow.qml"
grep -Fq 'readonly property bool powered: available && statusText !== "BT off"' \
	"$controls/BluetoothModel.qml"

grep -Fq 'PanelHero {' "$network/NetworkWindow.qml"
grep -Fq 'title: "Network"' "$network/NetworkWindow.qml"
grep -Fq 'onDismissed: networkModel.close()' "$network/NetworkWindow.qml"
grep -Fq 'FloatingWindow {' "$network/NetworkWindow.qml"
grep -Fq 'wifiPasswordInput.forceActiveFocus();' "$network/NetworkWindow.qml"
grep -Fq 'Theme.controlSelectedFill' "$network/NetworkWifiRow.qml"
grep -Fq 'Theme.controlHoverFill' "$network/NetworkProfileRow.qml"

grep -Fq 'PanelSeparator {' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'PanelSeparator {}' "$power/PowerMenuWindow.qml"
grep -Fq 'detail: modelData.detail' "$power/PowerMenuWindow.qml"
grep -Fq 'onDismissed: powerMenuModel.close()' "$power/PowerMenuWindow.qml"

if grep -REn 'Quickshell\.(Wayland|Hyprland)|WlrLayershell|hyprctl|uwsm-app|wl-copy|wl-paste' \
	"$core"/PanelHero.qml "$core"/PanelSeparator.qml "$core"/PanelSlider.qml \
	"$core"/PanelToggleSwitch.qml "$panel" "$controls" "$network" "$controlcenter" "$power"; then
	printf 'Panel-menu views must remain X11-safe.\n' >&2
	exit 1
fi

if grep -REn '(^|[[:space:]])Process[[:space:]]*\{' \
	"$core"/PanelHero.qml "$core"/PanelSeparator.qml "$core"/PanelSlider.qml \
	"$core"/PanelToggleSwitch.qml; then
	printf 'Visual panel primitives must not own helper processes.\n' >&2
	exit 1
fi

printf 'Quickshell panel menus: PASS\n'
