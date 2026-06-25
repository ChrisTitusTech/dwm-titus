#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-default-apps"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/data/applications" "$work/home" "$work/empty"

cat >"$work/data/applications/firefox.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Firefox
Categories=Network;WebBrowser;
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;
Exec=firefox %u
DESKTOP

cat >"$work/data/applications/org.example.Files.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Files
Categories=System;FileManager;
Exec=files %U
DESKTOP

cat >"$work/bin/xdg-settings" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "get" ] && [ "$2" = "default-web-browser" ]; then
	if [ -f "$DWM_TEST_STATE/browser" ]; then
		cat "$DWM_TEST_STATE/browser"
	fi
	exit 0
fi
if [ "$1" = "set" ] && [ "$2" = "default-web-browser" ]; then
	printf '%s\n' "$3" >"$DWM_TEST_STATE/browser"
	printf 'xdg-settings %s %s %s\n' "$1" "$2" "$3" >>"$DWM_TEST_STATE/log"
	exit 0
fi
exit 2
SCRIPT

cat >"$work/bin/xdg-mime" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "default" ]; then
	printf 'xdg-mime %s %s %s\n' "$1" "$2" "$3" >>"$DWM_TEST_STATE/log"
	exit 0
fi
if [ "$1" = "query" ] && [ "$2" = "default" ]; then
	exit 0
fi
exit 2
SCRIPT

cat >"$work/bin/xdg-open" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$1" >"$DWM_TEST_STATE/opened"
SCRIPT

chmod +x "$work/bin/xdg-settings" "$work/bin/xdg-mime" "$work/bin/xdg-open"

env_common=(
	DWM_TEST_STATE="$work"
	HOME="$work/home"
	PATH="$work/bin:/usr/bin:/bin"
	XDG_DATA_HOME="$work/data"
	XDG_DATA_DIRS="$work/empty"
)

env "${env_common[@]}" "$BASH_BIN" "$HELPER" browsers >"$work/browsers"
grep -Fqx $'firefox.desktop\tFirefox' "$work/browsers"
if grep -Fq "org.example.Files.desktop" "$work/browsers"; then
	echo "non-browser desktop file listed as browser" >&2
	exit 1
fi

env "${env_common[@]}" "$BASH_BIN" "$HELPER" set-browser firefox.desktop >"$work/set-browser"
grep -Fqx "Default browser set to firefox.desktop" "$work/set-browser"
grep -Fqx "firefox.desktop" "$work/browser"
grep -Fqx "xdg-settings set default-web-browser firefox.desktop" "$work/log"
grep -Fqx "xdg-mime default firefox.desktop x-scheme-handler/http" "$work/log"
grep -Fqx "xdg-mime default firefox.desktop x-scheme-handler/https" "$work/log"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" set-mime inode/directory org.example.Files.desktop >"$work/set-mime"
grep -Fqx "Default for inode/directory set to org.example.Files.desktop" "$work/set-mime"
grep -Fqx "xdg-mime default org.example.Files.desktop inode/directory" "$work/log"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" open "https://example.test"
grep -Fqx "https://example.test" "$work/opened"
