#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
model=$repo/config/quickshell/accessibility/AccessibilityModel.qml
theme=$repo/config/quickshell/core/Theme.qml
commands=$repo/config/quickshell/core/Commands.qml
shell=$repo/config/quickshell/shell.qml

grep -Fq 'accessibility-settings-protocol\t1\t0' "$model"
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
