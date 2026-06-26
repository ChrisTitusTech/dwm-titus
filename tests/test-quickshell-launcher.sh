#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/data/applications"

cat >"$work/data/applications/visible.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Visible App
GenericName=Utility
Comment=Shown in launcher
Exec=visible-app --flag %U
Icon=visible
DESKTOP

cat >"$work/data/applications/hidden.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Hidden App
Exec=hidden-app
NoDisplay=true
DESKTOP

cat >"$work/data/applications/link.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Link
Name=Link Entry
Exec=xdg-open https://example.invalid
DESKTOP

output=$(
	HOME="$work/home" \
		XDG_DATA_HOME="$work/empty" \
		XDG_DATA_DIRS="$work/data" \
		"$repo/scripts/dwm-quickshell-launcher" list
)

printf '%s\n' "$output" | grep -F 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'
if printf '%s\n' "$output" | grep -F 'Hidden App'; then
	exit 1
fi
if printf '%s\n' "$output" | grep -F 'Link Entry'; then
	exit 1
fi

printf 'Quickshell launcher index: PASS\n'
