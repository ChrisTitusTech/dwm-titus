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

assert_file_line() {
	file=$1
	expected=$2
	attempts=0

	while [ "$attempts" -lt 5 ]; do
		if [ -f "$file" ] && grep -Fqx "$expected" "$file"; then
			return 0
		fi
		attempts=$((attempts + 1))
		sleep 1
	done

	printf 'expected line not found in %s: %s\n' "$file" "$expected" >&2
	return 1
}

visible_desktop="$work/data/applications/visible.desktop"
browser_desktop="$work/data/applications/browser-actions.desktop"
editor_desktop="$work/data/applications/editor-actions.desktop"
symlink_desktop="$work/data/applications/symlink.desktop"
flatpak_desktop="$work/home/.local/share/flatpak/exports/share/applications/flatpak.desktop"
snap_desktop="$work/home/.local/share/snapd/applications/snap.desktop"
localized_desktop="$work/data/applications/localized.desktop"
chatgpt_native_desktop="$work/data/applications/chatgpt.desktop"
chatgpt_web_desktop="$work/empty/applications/ChatGPT.desktop"

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

mkdir -p "$work/empty/applications"
cat >"$chatgpt_native_desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChatGPT
GenericName=AI assistant
Exec=chatgpt %U
Categories=Utility;Development;
DESKTOP

cat >"$chatgpt_web_desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=webapp-launch https://chatgpt.com/
Categories=Network;WebApp;
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
		XDG_RUNTIME_DIR=relative-runtime \
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
assert_listed "$chatgpt_native_desktop"
if printf '%s\n' "$output" | grep -F "$chatgpt_web_desktop"; then
	exit 1
fi

cat >"$work/bin/dex" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >"$DWM_TEST_DEX_LOG"
printf '%s\t%s\t%s\n' "${QT_QPA_PLATFORMTHEME:-}" "${XCURSOR_THEME:-}" \
	"${XCURSOR_SIZE:-}" >"$DWM_TEST_THEME_ENV_LOG"
SH
chmod +x "$work/bin/dex"

mkdir -p "$work/home/.config/dwm-titus"
mkdir -p "$work/runtime"
printf '%s\n' 'export QT_QPA_PLATFORMTHEME=gtk3' \
	'export XCURSOR_THEME=Cursor-One' 'export XCURSOR_SIZE=32' \
	>"$work/home/.config/dwm-titus/theme-env.sh"

DWM_TEST_DEX_LOG="$work/dex.log" \
	DWM_TEST_THEME_ENV_LOG="$work/theme-env.log" \
	HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	XDG_RUNTIME_DIR="$work/runtime" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop"
assert_file_line "$work/dex.log" "$work/data/applications/visible.desktop"
assert_file_line "$work/theme-env.log" "$(printf 'gtk3\tCursor-One\t32')"

mkdir -p "$work/relative-config/dwm-titus"
printf '%s\n' 'export QT_QPA_PLATFORMTHEME=qt6ct' \
	'export XCURSOR_THEME=Wrong-Cursor' 'export XCURSOR_SIZE=48' \
	>"$work/relative-config/dwm-titus/theme-env.sh"
(
	cd "$work"
	DWM_TEST_DEX_LOG="$work/dex-relative-config.log" \
		DWM_TEST_THEME_ENV_LOG="$work/theme-env-relative-config.log" \
		HOME="$work/home" \
		XDG_CONFIG_HOME=relative-config \
		XDG_RUNTIME_DIR="$work/runtime" \
		PATH="$work/bin:$PATH" \
		"$repo/scripts/dwm-session-launch" dex \
		"$work/data/applications/visible.desktop"
)
assert_file_line "$work/theme-env-relative-config.log" "$(printf 'gtk3\tCursor-One\t32')"

exec 9>"$work/runtime/dwm-theme-apply.lock"
flock 9
printf '%s\n' 'export QT_QPA_PLATFORMTHEME=qt6ct' \
	'export XCURSOR_THEME=Uncommitted-Cursor' 'export XCURSOR_SIZE=48' \
	>"$work/home/.config/dwm-titus/theme-env.sh"
rm -f "$work/theme-env-locked.log" "$work/dex-locked.log"
DWM_TEST_DEX_LOG="$work/dex-locked.log" \
	DWM_TEST_THEME_ENV_LOG="$work/theme-env-locked.log" \
	HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	XDG_RUNTIME_DIR="$work/runtime" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop" &
locked_launcher_pid=$!
attempts=0
while [ "$attempts" -lt 5 ]; do
	kill -0 "$locked_launcher_pid" 2>/dev/null || break
	[ ! -e "$work/theme-env-locked.log" ] || break
	attempts=$((attempts + 1))
	sleep 0.1
done
[ ! -e "$work/theme-env-locked.log" ]
printf '%s\n' 'export QT_QPA_PLATFORMTHEME=gtk3' \
	'export XCURSOR_THEME=Cursor-One' 'export XCURSOR_SIZE=32' \
	>"$work/home/.config/dwm-titus/theme-env.sh"
flock -u 9
exec 9>&-
wait "$locked_launcher_pid"
assert_file_line "$work/theme-env-locked.log" "$(printf 'gtk3\tCursor-One\t32')"

exec 9>"$work/runtime/dwm-theme-apply.lock"
flock 9
QT_QPA_PLATFORMTHEME=parent-qt XCURSOR_THEME=Parent-Cursor XCURSOR_SIZE=24 \
	DWM_TEST_DEX_LOG="$work/dex-timeout.log" \
	DWM_TEST_THEME_ENV_LOG="$work/theme-env-timeout.log" \
	HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	XDG_RUNTIME_DIR="$work/runtime" \
	PATH="$work/bin:$PATH" \
	timeout 4 "$repo/scripts/dwm-session-launch" dex \
	"$work/data/applications/visible.desktop"
flock -u 9
exec 9>&-
assert_file_line "$work/theme-env-timeout.log" "$(printf 'parent-qt\tParent-Cursor\t24')"

printf '%s\n' 'export QT_QPA_PLATFORMTHEME="unterminated' \
	>"$work/home/.config/dwm-titus/theme-env.sh"
QT_QPA_PLATFORMTHEME=parent-qt XCURSOR_THEME=Parent-Cursor XCURSOR_SIZE=24 \
	DWM_TEST_DEX_LOG="$work/dex-malformed.log" \
	DWM_TEST_THEME_ENV_LOG="$work/theme-env-malformed.log" \
	HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	XDG_RUNTIME_DIR="$work/runtime" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop"
assert_file_line "$work/dex-malformed.log" "$work/data/applications/visible.desktop"
assert_file_line "$work/theme-env-malformed.log" "$(printf 'parent-qt\tParent-Cursor\t24')"

mv "$work/home/.config/dwm-titus/theme-env.sh" "$work/theme-env.saved"
mkfifo "$work/home/.config/dwm-titus/theme-env.sh"
timeout 3 env \
	QT_QPA_PLATFORMTHEME=parent-qt XCURSOR_THEME=Parent-Cursor XCURSOR_SIZE=24 \
	DWM_TEST_DEX_LOG="$work/dex-fifo.log" \
	DWM_TEST_THEME_ENV_LOG="$work/theme-env-fifo.log" \
	HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" \
	XDG_RUNTIME_DIR="$work/runtime" \
	PATH="$work/bin:$PATH" \
	"$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/visible.desktop"
assert_file_line "$work/dex-fifo.log" "$work/data/applications/visible.desktop"
assert_file_line "$work/theme-env-fifo.log" "$(printf 'parent-qt\tParent-Cursor\t24')"
rm "$work/home/.config/dwm-titus/theme-env.sh"
mv "$work/theme-env.saved" "$work/home/.config/dwm-titus/theme-env.sh"

rm -f "$work/dex.log"
DWM_TEST_DEX_LOG="$work/dex.log" \
	HOME="$work/home" \
	PATH="$work/bin:$PATH" \
	XDG_DATA_HOME="$work/empty" \
	XDG_DATA_DIRS="$work/data" \
	"$repo/scripts/dwm-quickshell-launcher" launch-chatgpt
assert_file_line "$work/dex.log" "$chatgpt_native_desktop"

rm "$chatgpt_native_desktop"
output=$(
	LANG=en_US.UTF-8 \
		HOME="$work/home" \
		XDG_DATA_HOME="$work/empty" \
		XDG_DATA_DIRS="$work/data" \
		"$repo/scripts/dwm-quickshell-launcher" list
)
assert_listed "$chatgpt_web_desktop"

cat >"$work/bin/webapp-launch" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >"$DWM_TEST_WEBAPP_LOG"
SH
chmod +x "$work/bin/webapp-launch"

DWM_TEST_WEBAPP_LOG="$work/webapp.log" \
	HOME="$work/home" \
	PATH="$work/bin:$PATH" \
	XDG_DATA_HOME="$work/empty" \
	XDG_DATA_DIRS="$work/data" \
	"$repo/scripts/dwm-quickshell-launcher" launch-chatgpt
assert_file_line "$work/webapp.log" 'https://chatgpt.com'

if "$repo/scripts/dwm-quickshell-launcher" launch "$work/data/applications/missing.desktop" 2>"$work/missing.err"; then
	exit 1
fi
grep -Fqx "desktop entry not found: $work/data/applications/missing.desktop" "$work/missing.err"

grep -Fq 'readlink("/proc/self/exe", launcher' "$repo/dwm.c"
grep -Fq 'memcpy(separator, "/dwm-session-launch"' "$repo/dwm.c"
grep -Fq 'posix_spawn(NULL, wrapped[0]' "$repo/dwm.c"
if grep -Fq -- '-DPREFIX=' "$repo/config.mk"; then
	printf 'DWM still embeds a stale compile-time install prefix\n' >&2
	exit 1
fi
grep -Fq 'scripts/dwm-session-launch' "$repo/Makefile"

printf 'Quickshell launcher helper: PASS\n'
