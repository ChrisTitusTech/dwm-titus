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

assert_listed() {
	printf '%s\n' "$output" | grep -Fq "$1"
}

visible_desktop="$work/data/applications/visible.desktop"
browser_desktop="$work/data/applications/browser-actions.desktop"
editor_desktop="$work/data/applications/editor-actions.desktop"
symlink_desktop="$work/data/applications/symlink.desktop"
flatpak_desktop="$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop"
snap_desktop="$work/home/.local/share/snapd/applications/snap.desktop"
localized_desktop="$work/data/applications/localized.desktop"

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

cat >"$work/data/applications/browser-actions.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Brave Origin Browser
GenericName=Web Browser
Comment=Access the Internet
Exec=brave-origin-beta %U
Icon=brave-origin-beta
Categories=Network;WebBrowser;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=brave-origin-beta

[Desktop Action new-private-window]
Name=New Private Window
Exec=brave-origin-beta --incognito
DESKTOP

cat >"$work/data/applications/editor-actions.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Zed
GenericName=Text Editor
Comment=A high-performance code editor.
Exec=zeditor %U
Icon=zed
Categories=Utility;TextEditor;Development;IDE;
Keywords=zed;
Actions=NewWorkspace;

[Desktop Action NewWorkspace]
Name=Open a new workspace
Exec=zeditor --new %U
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

assert_listed 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'
assert_listed 'Visible App	Utility	Shown in launcher	visible-app --flag %U	visible	'"$visible_desktop"'	visible;sample;	Utility;System;'
assert_listed 'Brave Origin Browser	Web Browser	Access the Internet	brave-origin-beta %U	brave-origin-beta	'"$browser_desktop"'		Network;WebBrowser;		new-window;new-private-window;'
assert_listed 'Zed	Text Editor	A high-performance code editor.	zeditor %U	zed	'"$editor_desktop"'	zed;	Utility;TextEditor;Development;IDE;		NewWorkspace;'
assert_listed 'Flatpak Export	Exported App	Shown from Flatpak export path	flatpak-export	flatpak	'"$flatpak_desktop"'	flatpak;exported;	Network;'
assert_listed 'Snap Export	Packaged App	Shown from Snap export path	snap-export	snap	'"$snap_desktop"'	snap;exported;	Utility;	snap-export	new-window;'
assert_listed 'Localized Name	Localized Generic	Localized comment	localized-app	localized	'"$localized_desktop"'	localized;translated;	Office;'
assert_listed 'Symlinked App			symlinked-app		'"$symlink_desktop"
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
