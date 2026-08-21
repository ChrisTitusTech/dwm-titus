#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
theme=$repo/config/quickshell/core/Theme.qml
panel=$repo/config/quickshell/panel/DwmPanel.qml
button=$repo/config/quickshell/panel/BarIconButton.qml
logo=$repo/config/quickshell/panel/LogoButton.qml
workspace=$repo/config/quickshell/panel/WorkspaceButton.qml
running_app=$repo/config/quickshell/panel/RunningAppItem.qml

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
grep -F 'signal focusRequested(string windowId)' "$running_app" >/dev/null
grep -F 'onClicked: root.focusRequested(root.app.windowId)' "$running_app" >/dev/null
if [ "$(grep -Fc 'IconText {' "$button")" -ne 1 ] \
    || [ "$(grep -Fc 'MouseArea {' "$button")" -ne 1 ]; then
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
if grep -F 'PanelTooltip {' "$panel" >/dev/null; then
    printf '%s\n' 'DwmPanel still creates tooltips' >&2
    exit 1
fi
printf '%s\n' 'Quickshell bar source contract: PASS'
