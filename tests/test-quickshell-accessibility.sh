#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo/config/quickshell/accessibility/AccessibilityModel.qml
theme=$repo/config/quickshell/core/Theme.qml
commands=$repo/config/quickshell/core/Commands.qml
shell=$repo/config/quickshell/shell.qml
pane=$repo/config/quickshell/settings/AppearanceSettingsPane.qml
settings_window=$repo/config/quickshell/settings/SettingsWindow.qml
toggle=$repo/config/quickshell/core/PanelToggleSwitch.qml

grep -Fq 'accessibility-settings-protocol\t1\t0' "$model"
grep -Fq 'for (let index = 1; index < lines.length - 1; index++)' "$model"
grep -Fq 'else if (fields[0] === "accessibility-settings-protocol"' "$model"
grep -Fq 'root.mutationState === "available"' "$model"
grep -Fq 'Commands.accessibilitySettingsCommand("watch", [])' "$model"
grep -Fq 'stdout: SplitParser {' "$model"
grep -Fq 'line === "ready\taccessibility"' "$model"
grep -Fq 'line.indexOf("DELETE_SELF")' "$model"
grep -Fq 'const shouldRestart = root.watchReady;' "$model"
grep -Fq 'readonly property int maxWatchSetupFailures: 5' "$model"
grep -Fq 'root.watchSetupFailures <= root.maxWatchSetupFailures' "$model"
grep -Fq 'Component.onCompleted: watchProcess.running = true' "$model"
grep -Fq 'Commands.accessibilitySettingsCommand("status", [])' "$model"
grep -Fq 'Theme.applyAccessibility(root.highContrast, root.reducedMotion)' "$model"
grep -Fq 'property bool highContrast: false' "$theme"
grep -Fq 'property bool reducedMotion: false' "$theme"
grep -Fq 'readonly property string textMuted: highContrast ? text : paletteTextMuted' "$theme"
grep -Fq 'readonly property int animationFast: reducedMotion ? 0 : 120' "$theme"
grep -Fq 'readonly property int animationNormal: reducedMotion ? 0 : 180' "$theme"
grep -Fq 'readonly property int controlBorderWidth: highContrast ? 2 : 1' "$theme"
grep -Fq 'readonly property string controlNormalBorder: highContrast ? textStrong : border' "$theme"
grep -Fq 'function accessibilitySettingsCommand(action, args)' "$commands"
grep -Fq 'import qs.accessibility' "$shell"
grep -Fq 'AccessibilityModel {' "$shell"
grep -Fq 'accessibilityModel: accessibilityModel' "$shell"
grep -Fq 'required property var accessibilityModel' "$settings_window"
grep -Fq 'component AccessibilityToggle: Rectangle {' "$pane"
grep -Fq 'title: "High contrast"' "$pane"
grep -Fq 'title: "Reduced motion"' "$pane"
grep -Fq 'label: "Reset contrast and motion"' "$pane"
grep -Fq 'Accessible.role: Accessible.CheckBox' "$toggle"
grep -Fq 'Accessible.name: root.accessibleName' "$toggle"
grep -Fq 'required property string accessibleName' "$toggle"
grep -Fq 'Accessible.onPressAction: root.requestToggle()' "$toggle"
grep -Fq 'Accessible.onToggleAction: root.requestToggle()' "$toggle"
grep -Fq 'accessibleName: panelWidgetRow.modelData.label' "$pane"
grep -Fq 'accessibleName: "Bluetooth power"' \
	"$repo/config/quickshell/controls/BluetoothWindow.qml"

if grep -Fq 'FileView {' "$model"; then
	printf 'Accessibility model reads the policy file without helper validation\n' >&2
	exit 1
fi

if awk '
	/^[[:space:]]*Timer[[:space:]]*\{/ { in_timer = 1; depth = 0 }
	in_timer {
		line = $0
		depth += gsub(/\{/, "{", line) - gsub(/\}/, "}", line)
		if ($0 ~ /repeat:[[:space:]]*true/) found = 1
		if (depth == 0) in_timer = 0
	}
	END { exit !found }
' "$model"; then
	printf 'Accessibility model introduced a polling timer\n' >&2
	exit 1
fi

printf 'Quickshell accessibility policy model: PASS\n'
