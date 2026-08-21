#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo/config/quickshell/core/Theme.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
button=$repo/config/quickshell/panel/BarIconButton.qml

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
if [ "$(grep -Fc 'IconText {' "$button")" -ne 1 ] \
    || [ "$(grep -Fc 'MouseArea {' "$button")" -ne 1 ]; then
    printf '%s\n' 'BarIconButton must contain one icon and one mouse area' >&2
    exit 1
fi
if grep -Eiq 'tooltip|popup|timer' "$button"; then
    printf '%s\n' 'BarIconButton creates a tooltip, popup, or timer' >&2
    exit 1
fi
if grep -F 'PanelTooltip {' "$panel" >/dev/null; then
    printf '%s\n' 'DwmPanel still creates tooltips' >&2
    exit 1
fi
printf '%s\n' 'Quickshell bar source contract: PASS'
