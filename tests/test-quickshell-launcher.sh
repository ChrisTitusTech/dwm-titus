#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/data/applications"
mkdir -p "$work/home/.local/share/flatpak/exports/share/applications"
mkdir -p "$work/home/.local/share/snapd/applications"
mkdir -p "$work/bin"

cat >"$work/data/applications/visible.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Visible App
GenericName=Utility
Comment=Shown in launcher
Exec=visible-app --flag %U
Icon=visible
Keywords=visible;sample;
Categories=Utility;System;
DESKTOP

cat >"$work/data/applications/symlink-target.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Symlinked App
Exec=symlinked-app
DESKTOP
ln -s "$work/data/applications/symlink-target.desktop" "$work/data/applications/symlink.desktop"

cat >"$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Flatpak Export
GenericName=Exported App
Comment=Shown from Flatpak export path
Exec=flatpak-export
Icon=flatpak
Keywords=flatpak;exported;
Categories=Network;
DESKTOP

cat >"$work/home/.local/share/snapd/applications/snap.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Snap Export
GenericName=Packaged App
Comment=Shown from Snap export path
Exec=snap-export
Icon=snap
Keywords=snap;exported;
Categories=Utility;
StartupWMClass=snap-export
Actions=new-window;
DESKTOP

cat >"$work/data/applications/localized.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Base Name
Name[en_US]=Localized Name
GenericName=Base Generic
GenericName[en_US]=Localized Generic
Comment=Base comment
Comment[en_US]=Localized comment
Exec=localized-app
Icon=localized
Keywords=base;
Keywords[en_US]=localized;translated;
Categories=Office;
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
	LANG=en_US.UTF-8 \
		HOME="$work/home" \
		XDG_DATA_HOME="$work/empty" \
		XDG_DATA_DIRS="$work/data" \
		"$repo/scripts/dwm-quickshell-launcher" list
)

printf '%s\n' "$output" | grep -Fq 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'
printf '%s\n' "$output" | grep -Fq 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'"$work/data/applications/visible.desktop"'	visible;sample;	Utility;System;'
printf '%s\n' "$output" | grep -Fq 'Flatpak Export	Exported App	Shown from Flatpak export path	flatpak-export	flatpak	'"$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop"'	flatpak;exported;	Network;'
printf '%s\n' "$output" | grep -Fq 'Snap Export	Packaged App	Shown from Snap export path	snap-export	snap	'"$work/home/.local/share/snapd/applications/snap.desktop"'	snap;exported;	Utility;	snap-export	new-window;'
printf '%s\n' "$output" | grep -Fq 'Localized Name	Localized Generic	Localized comment	localized-app	localized	'"$work/data/applications/localized.desktop"'	localized;translated;	Office;'
printf '%s\n' "$output" | grep -Fq 'Symlinked App			symlinked-app		'"$work/data/applications/symlink.desktop"
if printf '%s\n' "$output" | grep -F 'Hidden App'; then
	exit 1
fi
if printf '%s\n' "$output" | grep -F 'Link Entry'; then
	exit 1
fi

cat >"$work/bin/dex" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >"$DWM_TEST_DEX_LOG"
SH
chmod +x "$work/bin/dex"

DWM_TEST_DEX_LOG="$work/dex.log" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop"
grep -Fqx "$work/data/applications/visible.desktop" "$work/dex.log"

if "$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/missing.desktop" 2>"$work/missing.err"; then
	exit 1
fi
grep -Fqx "desktop entry not found: $work/data/applications/missing.desktop" "$work/missing.err"

printf 'Quickshell launcher helper: PASS\n'
