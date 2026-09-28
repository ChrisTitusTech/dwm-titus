#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core=$repo/config/quickshell/core
panel=$repo/config/quickshell/panel
controls=$repo/config/quickshell/controls
network=$repo/config/quickshell/network
controlcenter=$repo/config/quickshell/controlcenter
power=$repo/config/quickshell/power
shell=$repo/config/quickshell/shell.qml

for component in PanelHero PanelSeparator PanelSlider PanelToggleSwitch; do
	test -f "$core/$component.qml"
done
grep -Fq 'onEnabledChanged: if (enabled && !dragging) liveValue = value' "$core/PanelSlider.qml"
grep -Fq 'if (wheel.angleDelta.y === 0)' "$core/PanelSlider.qml"

grep -Fq 'readonly property int panelHeight: scaledSize(30)' "$core/Theme.qml"
grep -Fq 'exclusiveZone: Theme.panelHeight' "$panel/DwmPanel.qml"
grep -Fq 'aboveWindows: root.state.fullscreenMonitorIndexes.indexOf(' "$panel/DwmPanel.qml"
grep -Fq 'signal popupRequested(var panelWindow, string popupId)' "$panel/DwmPanel.qml"
grep -Fq 'model: root.state.workspaceIndexes(root.screen)' "$panel/DwmPanel.qml"
grep -Fq 'sourceComponent: TrayArea {}' "$panel/DwmPanel.qml"
grep -Fq 'RunningAppsArea { desktopState: root.state }' "$panel/DwmPanel.qml"

python3 - "$panel/DwmPanel.qml" "$shell" <<'PY'
import sys
from pathlib import Path

panel = Path(sys.argv[1]).read_text()
shell = Path(sys.argv[2]).read_text()
clock = panel.index('id: clockLabel')
button = panel.index('objectName: "updateCenterIndicator"')
right = panel.index('Item {\n                Layout.fillWidth: true', button)
assert clock < button < right, "Update Center is not immediately after the center clock"
assert 'required property var updateCenterModel' in panel
assert 'label: root.updateCenterModel.totalUpdates > 0 ? "󰜈 "' in panel
assert ': "󰏗"' in panel
assert 'root.updateCenterModel.totalUpdates.toString()' in panel
assert 'visible: root.updateCenterModel.shouldShow()' in panel
assert 'root.popupRequested(root, "updatecenter")' in panel
assert 'function updateCenterAnchorX()' in panel
assert 'objectName: "desktopUpdateIndicator"' not in panel

assert 'import qs.updatecenter' in shell
assert shell.count('UpdateCenterModel {') == 1, "Update Center scanner/model must be shared"
assert shell.count('UpdateCenterWindow {') == 1, "Update Center popup must be shared"
assert 'updateCenterModel: updateCenterModel' in shell
assert 'function requestPanelPopup(panel, popupId)' in shell
assert 'updateCenterModel.close();' in shell
assert 'updateCenterModel.open();' in shell
assert 'property real updateCenterAnchorX: 0' in shell
assert 'root.updateCenterAnchorX = panel.updateCenterAnchorX();' in shell
PY

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
grep -Fq 'ShellButton {' "$network/NetworkWifiRow.qml"
grep -Fq 'ShellButton {' "$network/NetworkProfileRow.qml"

grep -Fq 'PanelSeparator {' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'activeFocusOnTab: presetButton.enabled' "$controlcenter/ControlCenterWindow.qml"
grep -Fq 'event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space' \
	"$controlcenter/ControlCenterWindow.qml"
grep -Fq 'PanelSeparator {}' "$power/PowerMenuWindow.qml"
grep -Fq 'onDismissed: powerMenuModel.close(root.actionOrigin)' "$power/PowerMenuWindow.qml"
grep -Fq 'enabled: !root.powerMenuModel.busy' "$power/PowerMenuWindow.qml"
grep -Fq 'root.powerMenuModel.requestAction(modelData, root.actionOrigin)' \
	"$power/PowerMenuWindow.qml"
for action in lock logout suspend reboot shutdown; do
	grep -Fq "\"id\": \"$action\"" "$power/PowerMenuModel.qml"
done

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
