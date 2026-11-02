#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
network_model=$repo/config/quickshell/network/NetworkModel.qml
bluetooth_model=$repo/config/quickshell/controls/BluetoothModel.qml
settings_model=$repo/config/quickshell/settings/SettingsModel.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
network_pane=$repo/config/quickshell/settings/NetworkSettingsPane.qml
bluetooth_pane=$repo/config/quickshell/settings/BluetoothSettingsPane.qml

grep -Fq 'run_parent_bound nmcli monitor' "$repo/scripts/dwm-quickshell-network"
grep -Fq 'run_parent_bound playerctl --follow' "$repo/scripts/dwm-quickshell-controls"
grep -Fq 'networkMonitorRestartTimer.restart()' "$network_model"

for pattern in \
	'fields[0] === "connectivity-protocol"' \
	'fields[1] === "1"' \
	'!protocolValid || !providerSeen || malformed' \
	'fields.length < 5' \
	'root.providerState = "failure"'; do
	grep -Fq "$pattern" "$network_model"
	grep -Fq "$pattern" "$bluetooth_model"
done

grep -Fq 'else if (fields[0] === "network-profile")' "$network_model"
grep -Fq 'else if (fields[0] === "wifi-network")' "$network_model"
grep -Fq 'else if (fields[0] === "bluetooth-adapter")' "$bluetooth_model"
grep -Fq 'else if (fields[0] === "bluetooth-device")' "$bluetooth_model"

grep -Fq 'function openSettings()' "$network_model"
grep -Fq "[ -n \"\$parent_identity\" ] || return 1" "$repo/scripts/dwm-quickshell-network"
grep -Fq "[ -n \"\$parent_identity\" ] || return 1" "$repo/scripts/dwm-quickshell-controls"
grep -Fq 'property string wifiPasswordPromptOrigin: ""' "$network_model"
grep -Fq 'function supportsFixedWifiSecurity(security)' "$network_model"
grep -Fq 'function closeSettings()' "$network_model"
grep -Fq 'property bool hiddenPromptVisible: false' "$network_model"
grep -Fq 'property string hiddenPromptOrigin: ""' "$network_model"
grep -Fq 'function openHiddenPrompt(origin)' "$network_model"
grep -Fq 'function cancelHiddenPrompt()' "$network_model"
grep -Fq 'function connectHidden(origin)' "$network_model"
# IPC can open the form while open() is still loading the first snapshot.
grep -Fq 'root.hiddenPromptPendingOrigin = origin || "panel";' "$network_model"
grep -Fq 'if (root.hiddenPromptPendingOrigin.length > 0) root.openHiddenPrompt(root.hiddenPromptPendingOrigin);' "$network_model"
test "$(grep -Fc 'root.openPendingHiddenPrompt();' "$network_model")" -eq 2
grep -Fq 'root.hiddenPromptPendingOrigin = "";' "$network_model"
# A failed snapshot must not drop a pending hidden prompt request: the request
# is only cleared once the form can actually open.
grep -A1 -F 'if (!root.actionsAvailable || root.wifiDevices.length === 0) return;' "$network_model" |
	grep -Fq 'root.hiddenPromptPendingOrigin = "";'
grep -Fq 'readonly property var wifiDevices' "$network_model"
grep -Fq 'Commands.networkHelperCommand("wifi-connect-hidden", args)' "$network_model"
grep -Fq 'root.actionUsesPasswordStdin = secured;' "$network_model"
if grep -Fq 'args.push(root.wifiPassword)' "$network_model"; then
	printf 'Hidden Wi-Fi password must not be passed on argv.\n' >&2
	exit 1
fi
grep -Fq 'function openSettings()' "$bluetooth_model"
grep -Fq 'function closeSettings()' "$bluetooth_model"
grep -Fq 'root.actionOrigin === origin && actionProcess.running' "$network_model"
grep -Fq 'root.scanOrigin === origin && scanProcess.running' "$bluetooth_model"
grep -Fq 'operationState === "delegated"' "$bluetooth_model"
grep -Fq 'root.connections = []' "$network_model"
grep -Fq 'root.operationState = "unavailable"' "$bluetooth_model"

if grep -Fq 'repeat: true' "$network_model" || grep -Fq 'repeat: true' "$bluetooth_model"; then
	printf 'Connectivity models must not poll.\n' >&2
	exit 1
fi
grep -Fq 'stdout: SplitParser { onRead: monitorSettleTimer.restart() }' "$bluetooth_model"

grep -Fq 'networkModel: networkModel' "$repo/config/quickshell/shell.qml"
grep -Fq 'bluetoothModel: bluetoothModel' "$repo/config/quickshell/shell.qml"
grep -Fq 'root.networkModel.openSettings()' "$settings_model"
grep -Fq 'root.bluetoothModel.openSettings()' "$settings_model"
grep -Fq 'NetworkSettingsPane {' "$settings_window"
grep -Fq 'BluetoothSettingsPane {' "$settings_window"

grep -Fq 'connectSelectedWifi("settings")' "$network_pane"
grep -Fq 'function onWifiPasswordChanged()' "$network_pane"
grep -Fq 'passwordInput.clear()' "$network_pane"
grep -Fq 'Confirm Forget' "$network_pane"
grep -Fq 'root.networkModel.wifiPasswordPromptOrigin === "settings"' "$network_pane"
grep -Fq 'delegated: !root.networkModel.supportsFixedWifiSecurity(modelData.security)' "$network_pane"
grep -Fq 'forgetProfile(profileRow.modelData, "settings")' "$network_pane"
grep -Fq 'bluetooth-trust' "$bluetooth_pane"
grep -Fq 'bluetooth-remove' "$bluetooth_pane"
grep -Fq 'Confirm Remove' "$bluetooth_pane"
grep -Fq 'actionAddress === modelData.address' "$bluetooth_pane"

printf 'Quickshell connectivity contract: PASS\n'
