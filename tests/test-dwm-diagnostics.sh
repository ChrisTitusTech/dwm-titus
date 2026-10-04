#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-diagnostics"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home/.config"
ln -s "$(command -v dirname)" "$work/bin/dirname"

for cmd in cc make Xorg startx xrandr xset xsetroot xclip xdotool alacritty; do
	cat >"$work/bin/$cmd" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
	chmod +x "$work/bin/$cmd"
done

cat >"$work/bin/pkg-config" <<'SCRIPT'
#!/bin/sh
test "$1" = "--exists"
case "$2" in
	x11|xft|xinerama|xrender|imlib2|x11-xcb|xcb|xcb-res)
		exit 0
		;;
esac
exit 1
SCRIPT
chmod +x "$work/bin/pkg-config"

cat >"$work/bin/rpm" <<'SCRIPT'
#!/bin/sh
[ "$1" = -q ] || exit 2
[ "$2" != "${DWM_TEST_MISSING_PACKAGE:-}" ]
SCRIPT
chmod +x "$work/bin/rpm"

env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/ok"
grep -Fqx "  required_failures=0" "$work/ok"
grep -Fq "Optional desktop" "$work/ok"
grep -Fq "degraded quickshell" "$work/ok"
grep -Fq "degraded maim" "$work/ok"

# A running daemon does not prove that its separate PAM package is present.
for cmd in tr cut; do
	ln -s "$(command -v "$cmd")" "$work/bin/$cmd"
done
for package in gnome-keyring gnome-keyring-pam; do
	if env HOME="$work/home" PATH="$work/bin" DWM_TEST_MISSING_PACKAGE="$package" \
		"$BASH_BIN" "$HELPER" --format health-tsv >"$work/keyring-fail"; then
		echo "diagnostics passed despite missing $package" >&2
		exit 1
	fi
	grep -Fq $'error\tdependency-package-'"$package" "$work/keyring-fail"
	grep -Fq $'install-dependencies\tOpen dependency installer' "$work/keyring-fail"
done
env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" --format health-tsv >"$work/keyring-ok"
grep -Fq $'ok\tdependency-package-gnome-keyring-pam' "$work/keyring-ok"

# The command-line dependency checker must detect the same missing PAM package.
for cmd in grep paste; do
	ln -s "$(command -v "$cmd")" "$work/bin/$cmd"
done
for cmd in xkbset quickshell picom feh xsettingsd bwrap dex amixer jq bluetoothctl blueman-applet xdg-open; do
	cp "$work/bin/cc" "$work/bin/$cmd"
done
cat >"$work/bin/fc-list" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 'MesloLGS Nerd Font' 'Noto Color Emoji'
SCRIPT
chmod +x "$work/bin/fc-list"
env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$ROOT_DIR/scripts/check-deps.sh" >"$work/check-ok"
if env HOME="$work/home" PATH="$work/bin" DWM_TEST_MISSING_PACKAGE=gnome-keyring-pam \
	"$BASH_BIN" "$ROOT_DIR/scripts/check-deps.sh" >"$work/check-fail"; then
	echo 'dependency checker passed despite missing keyring PAM' >&2
	exit 1
fi
grep -Fq 'missing gnome-keyring-pam' "$work/check-fail"
grep -Fq '1 missing dependency/dependencies.' "$work/check-fail"

rm -f "$work/bin/alacritty" "$work/bin/Xorg"

if env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/fail" 2>"$work/err"; then
	echo "diagnostics passed despite missing required commands" >&2
	exit 1
fi

grep -Fq "missing X11 server" "$work/fail"
grep -Fq "missing terminal" "$work/fail"
grep -Fq "Required failures must be fixed" "$work/err"
