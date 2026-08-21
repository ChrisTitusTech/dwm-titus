#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo/config/quickshell/core/Theme.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml

grep -F 'readonly property int omarchyBarFontSize: 11' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarBackground: "#1a1b26"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarForeground: "#a9b1d6"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarActive: "#7aa2f7"' "$theme" >/dev/null
grep -F 'readonly property string omarchyBarUrgent: "#f7768e"' "$theme" >/dev/null
if grep -F 'PanelTooltip {' "$panel" >/dev/null; then
    printf '%s\n' 'DwmPanel still creates tooltips' >&2
    exit 1
fi
printf '%s\n' 'Quickshell bar source contract: PASS'
