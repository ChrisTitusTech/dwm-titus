#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
model=$repo/config/quickshell/power/PowerModel.qml
pane=$repo/config/quickshell/settings/PowerSettingsPane.qml
settings=$repo/config/quickshell/settings/SettingsModel.qml
control_center=$repo/config/quickshell/controlcenter/ControlCenterModel.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
shell=$repo/config/quickshell/shell.qml

grep -Fq 'import Quickshell.Services.UPower' "$model"
grep -Fq 'readonly property var nativeBattery: UPower.displayDevice' "$model"
grep -Fq 'function onOnBatteryChanged()' "$model"
grep -Fq 'Math.round(battery.percentage * 100)' "$model"
grep -Fq 'function nativeBatteryStatus(state)' "$model"
for state in Charging Discharging Empty FullyCharged PendingCharge PendingDischarge; do
	grep -Fq "UPowerDeviceState.$state" "$model"
done
grep -Fq 'return "pending-charge"' "$model"
grep -Fq 'return "pending-discharge"' "$model"
grep -Fq 'function onProfileChanged()' "$model"
grep -Fq 'property bool nativeProfileObserved: false' "$model"
grep -Fq 'if (root.nativeProfileObserved) root.updateNativeProfile();' "$model"

grep -Fq 'fields[0] === "power-protocol"' "$model"
grep -Fq 'fields.length >= 3 && fields[1] === "1"' "$model"
grep -Fq 'root.boundedInteger(fields[2], 0, 2147483647) >= 0' "$model"
grep -Fq '!/^[0-9]+$/.test(value)' "$model"
grep -Fq '!/^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/.test(value)' "$model"
grep -Fq '!protocolValid || !providerSeen' "$model"
for record in power-dpms power-lock power-external power-battery \
	power-profile-support power-profile power-suspend power-lid; do
	grep -Fq "fields[0] === \"$record\"" "$model"
done
grep -Fq 'fields[0] === "power-lid-policy"' "$model"
grep -Fq 'function validLidAction(value)' "$model"
grep -Fq 'root.boundedInteger(fields[3], 0, 100)' "$model"
grep -Fq 'root.dpmsState = "unavailable"' "$model"
grep -Fq 'root.lockState = "unavailable"' "$model"
grep -Fq 'root.dpmsEnabled = false;' "$model"
grep -Fq 'root.lockRunning = false;' "$model"
grep -Fq 'root.batteryPercent = 0;' "$model"
grep -Fq 'root.clearExternalPowerState("External power provider returned malformed state")' "$model"
grep -Fq 'root.profileState = "unavailable"' "$model"
grep -Fq 'root.suspendState = "unavailable"' "$model"
grep -Fq 'root.lidState = "unavailable"' "$model"
grep -Fq 'root.lidPolicyState = "unavailable"' "$model"

grep -Fq 'property int mutationGeneration: 0' "$model"
grep -Fq 'property int actionGeneration: 0' "$model"
grep -Fq 'property int snapshotGeneration: 0' "$model"
grep -Fq 'root.snapshotGeneration !== root.mutationGeneration' "$model"
grep -Fq 'root.actionGeneration !== root.mutationGeneration' "$model"
grep -Fq 'if (root.busy || actionProcess.running) return;' "$model"
grep -Fq 'if (root.sectionVisible) root.refresh();' "$model"
grep -Fq 'property string mutationOrigin: ""' "$model"
grep -Fq 'function messageFor(origin)' "$model"
grep -Fq 'root.mutationOrigin === origin ? root.message : ""' "$model"

[ "$(grep -Fc 'Commands.powerHelperCommand("power-watch")' "$model")" -eq 1 ]
grep -Fq 'readonly property bool sectionVisible:' "$model"
grep -Fq 'function openSettings()' "$model"
grep -Fq 'function closeSettings()' "$model"
grep -Fq 'function openControlCenter()' "$model"
grep -Fq 'function closeControlCenter()' "$model"
grep -Fq 'watchProcess.running = false' "$model"
grep -Fq 'snapshotProcess.running = false' "$model"
grep -Fq 'interval: 250' "$model"
grep -Fq 'interval: 3000' "$model"
if grep -Fq 'repeat: true' "$model"; then
	printf 'Power model must not poll.\n' >&2
	exit 1
fi

grep -Fq 'property var powerModel: null' "$settings"
grep -Fq 'root.powerModel.openSettings()' "$settings"
grep -Fq 'root.powerModel.closeSettings()' "$settings"
grep -Fq 'property var powerModel: null' "$control_center"
grep -Fq 'root.powerModel.openControlCenter()' "$control_center"
grep -Fq 'root.powerModel.closeControlCenter()' "$control_center"
grep -Fq 'PowerSettingsPane {' "$repo/config/quickshell/settings/SettingsWindow.qml"
grep -Fq 'setProfile(profileButton.modelData.id, "settings")' "$pane"
grep -Fq 'setDpms(!root.powerModel.dpmsEnabled, "settings")' "$pane"
grep -Fq 'setLock(!root.powerModel.lockEnabled, "settings")' "$pane"
grep -Fq 'root.powerModel.messageFor("settings")' "$pane"
grep -Fq 'function powerBusy(): bool' "$shell"
grep -Fq 'function powerMessage(): string' "$shell"
grep -Fq 'function powerSetDpms(enabled: bool): void' "$shell"
grep -Fq 'powerModel.setDpms(enabled, "settings")' "$shell"

[ "$(grep -Fc 'PowerModel {' "$shell")" -eq 1 ]
grep -Fq 'powerModel: powerModel' "$shell"
grep -Fq 'required property var powerModel' "$panel"
grep -Fq 'visible: root.powerModel.batteryAvailable' "$panel"
grep -Fq 'root.powerModel.batteryPercent.toString() + "%"' "$panel"
if grep -Fq 'visible: root.state.batteryAvailable' "$panel"; then
	printf 'Panel still renders battery state from the legacy DwmState model.\n' >&2
	exit 1
fi

grep -Fq 'root.powerModel.setDpms(!root.powerModel.dpmsEnabled, "controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.powerModel.setLock(!root.powerModel.lockEnabled, "controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'root.powerModel.messageFor("controlcenter")' \
	"$repo/config/quickshell/controlcenter/ControlCenterWindow.qml"
grep -Fq 'property bool confirming: false' \
	"$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq '"id": "reboot"' "$repo/config/quickshell/power/PowerMenuModel.qml"
grep -Fq '"id": "shutdown"' "$repo/config/quickshell/power/PowerMenuModel.qml"

printf 'Quickshell shared power model and Settings contract: PASS\n'
