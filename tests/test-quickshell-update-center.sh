#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
assets=$repo/config/quickshell/assets/update-center
row=$repo/config/quickshell/updatecenter/ProviderRow.qml
window=$repo/config/quickshell/updatecenter/UpdateCenterWindow.qml
model=$repo/config/quickshell/updatecenter/UpdateCenterModel.qml

for asset in dwm-update-center.png fedora.svg dwm-titus.png flatpak.svg mise.svg other.svg; do
	test -s "$assets/$asset"
done
test ! -e "$assets/PROVENANCE.md"

python3 - "$assets/dwm-update-center.png" <<'PY'
import sys
from PIL import Image

image = Image.open(sys.argv[1]).convert("RGBA")
assert image.getpixel((0, 0))[3] == 0, "bar icon background must be transparent"
assert image.getbbox() is not None, "bar icon must contain visible artwork"
PY

if grep -rnaE '/home/|file://' "$assets"; then
	printf '%s\n' 'Update Center assets contain a host-local path.' >&2
	exit 1
fi

test -f "$row"
test -f "$window"

for mapping in \
	'fedora:fedora.svg' \
	'dwm-titus:dwm-titus.png' \
	'flatpak:flatpak.svg' \
	'mise:mise.svg' \
	'other:other.svg'; do
	provider=${mapping%%:*}
	asset=${mapping#*:}
	grep -Fq "\"$provider\": \"../assets/update-center/$asset\"" "$row"
done

grep -Fq 'readonly property var providerIcons:' "$row"
grep -Fq 'return root.providerIcons[providerId] || root.providerIcons.other;' "$row"
if grep -Eq 'color: "#111827"|border[.]color: "#94a3b8"' "$row"; then
	printf '%s\n' 'Update Center provider icons must render without a background tile or border.' >&2
	exit 1
fi
grep -Fq 'property bool expanded: false' "$row"
grep -Fq 'signal updateRequested(string providerId)' "$row"
grep -Fq 'signal recoverRequested(string providerId)' "$row"
grep -Fq 'signal openUrlRequested(string url)' "$row"
grep -Fq 'if (!item || typeof item.url !== "string" || !/^https:' "$row"
grep -Fq 'onOpenUrlRequested: url => Qt.openUrlExternally(url)' "$window"
grep -Fq 'root.providerBusy ? "Busy" : root.providerRecoverable ? "Recover" : "Update"' "$row"
grep -Fq 'enabled: !root.providerMissing && (root.providerRecoverable || (!root.globalBusy && root.provider.updateAvailable))' "$row"
grep -Fq 'visible: (root.expanded || root.providerMissing) && root.visibleDetail().length > 0' "$row"

grep -Fq 'ClickAwayPopup {' "$window"
grep -Fq 'readonly property int cardWidth: Theme.scaledSize(480)' "$window"
grep -Fq 'property int draftRefreshSeconds: 3600' "$model"
grep -Fq 'property bool draftAlwaysShow: true' "$model"
grep -Fq 'from: 300' "$window"
grep -Fq 'to: 21600' "$window"
grep -Fq 'label: "Updates"' "$window"
grep -Fq 'label: "Settings"' "$window"
grep -Fq 'label: "Refresh"' "$window"
grep -Fq 'label: "Save"' "$window"
grep -Fq 'event.key === Qt.Key_R' "$window"
grep -Fq 'event.key === Qt.Key_S' "$window"
grep -Fq 'event.key === Qt.Key_Escape' "$window"

if grep -niE 'update all|notification|notify-send' "$row" "$window" "$model"; then
	printf '%s\n' 'Update Center UI must have independent provider actions and silent discovery.' >&2
	exit 1
fi

printf '%s\n' 'Quickshell Update Center static UI contract: PASS'
