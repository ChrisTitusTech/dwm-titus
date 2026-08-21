#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo/config/quickshell/core/Theme.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
state=$repo/config/quickshell/state/DwmState.qml
button=$repo/config/quickshell/panel/BarIconButton.qml
logo=$repo/config/quickshell/panel/LogoButton.qml
workspace=$repo/config/quickshell/panel/WorkspaceButton.qml
running_app=$repo/config/quickshell/panel/RunningAppItem.qml
network=$repo/config/quickshell/panel/NetworkBarModule.qml
volume=$repo/config/quickshell/panel/VolumeBarModule.qml

grep -F 'readonly property int omarchyBarFontSize: 11' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarBackground: "#1a1b26"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarForeground: "#a9b1d6"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarInactive: "#a9b1d6"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarActive: "#7aa2f7"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarUrgent: "#f7768e"' "$theme" >/dev/null
grep -F 'required property string glyph' "$button" >/dev/null
grep -F 'property bool active: false' "$button" >/dev/null
grep -F 'signal activated()' "$button" >/dev/null
grep -F 'signal wheelUp()' "$button" >/dev/null
grep -F 'signal wheelDown()' "$button" >/dev/null
grep -F 'anchors.centerIn: parent' "$button" >/dev/null
grep -F 'font.pixelSize: Theme.omarchyBarFontSize' "$button" >/dev/null
grep -F 'onClicked: root.activated()' "$button" >/dev/null
grep -F 'root.wheelUp();' "$button" >/dev/null
grep -F 'root.wheelDown();' "$button" >/dev/null
grep -F 'signal activated' "$logo" >/dev/null
grep -F 'font.pixelSize: Theme.omarchyBarFontSize' "$logo" >/dev/null
grep -F 'onClicked: root.activated()' "$logo" >/dev/null
grep -F 'signal clicked()' "$workspace" >/dev/null
grep -F 'font.pixelSize: Theme.omarchyBarFontSize' "$workspace" >/dev/null
grep -F 'onClicked: root.clicked()' "$workspace" >/dev/null
grep -F 'model: root.state.barWorkspaceIndexes(root.screen, root.primaryPanel)' "$panel" >/dev/null
grep -F 'function barWorkspaceIndexes(screen, primaryPanel)' "$state" >/dev/null
grep -F 'signal focusRequested(string windowId)' "$running_app" >/dev/null
grep -F 'onClicked: root.focusRequested(root.app.windowId)' "$running_app" >/dev/null
grep -F 'readonly property var wifiIcons: ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]' "$network" >/dev/null
grep -F 'readonly property string ethernetIcon: "󰈀"' "$network" >/dev/null
grep -F 'readonly property string disconnectedIcon: "󰤮"' "$network" >/dev/null
grep -F 'required property var networkModel' "$network" >/dev/null
grep -F 'onActivated: {' "$network" >/dev/null
grep -F 'root.popupRequested();' "$network" >/dev/null
grep -F 'root.networkModel.toggle();' "$network" >/dev/null
awk '
	/onActivated:[[:space:]]*\{/ { in_handler = 1; next }
	in_handler && /root\.popupRequested\(\);/ { requested = 1; next }
	in_handler && /root\.networkModel\.toggle\(\);/ { ordered = requested; exit }
	END { exit ordered ? 0 : 1 }
' "$network"
grep -F 'readonly property string muteIcon: "󰝟"' "$volume" >/dev/null
grep -F 'readonly property string lowIcon: "󰕿"' "$volume" >/dev/null
grep -F 'readonly property string mediumIcon: "󰖀"' "$volume" >/dev/null
grep -F 'readonly property string highIcon: "󰕾"' "$volume" >/dev/null
grep -F 'required property var controlsModel' "$volume" >/dev/null
grep -F 'onWheelUp: root.controlsModel.volumeUp()' "$volume" >/dev/null
grep -F 'onWheelDown: root.controlsModel.volumeDown()' "$volume" >/dev/null
if [ "$(grep -Fc 'IconText {' "$button")" -ne 1 ] ||
	[ "$(grep -Fc 'MouseArea {' "$button")" -ne 1 ]; then
	printf '%s\n' 'BarIconButton must contain one icon and one mouse area' >&2
	exit 1
fi
if grep -Eq '^[[:space:]]*(Text|IconText)[[:space:]]*{' "$running_app"; then
	printf '%s\n' 'RunningAppItem must preserve its image-only primitive' >&2
	exit 1
fi
for primitive in "$button" "$logo" "$workspace" "$running_app"; do
	if grep -Eiq 'tooltip|popup|timer' "$primitive"; then
		printf '%s\n' 'Bar primitive creates a tooltip, popup, or timer' >&2
		exit 1
	fi
done
for module in "$network" "$volume"; do
	if grep -Eiq 'tooltip|timer' "$module"; then
		printf '%s\n' 'Bar module creates a tooltip or timer' >&2
		exit 1
	fi
done
if grep -F 'PanelTooltip {' "$panel" >/dev/null; then
	printf '%s\n' 'DwmPanel still creates tooltips' >&2
	exit 1
fi
printf '%s\n' 'Quickshell bar source contract: PASS'
