#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-diagnostics"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/home/.config"

for cmd in cc make Xorg startx xrandr xset xsetroot ghostty; do
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

env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/ok"
grep -Fqx "  required_failures=0" "$work/ok"
grep -Fq "Optional desktop" "$work/ok"
grep -Fq "degraded rofi" "$work/ok"

rm -f "$work/bin/ghostty" "$work/bin/Xorg"

if env HOME="$work/home" PATH="$work/bin" "$BASH_BIN" "$HELPER" >"$work/fail" 2>"$work/err"; then
	echo "diagnostics passed despite missing required commands" >&2
	exit 1
fi

grep -Fq "missing X11 server" "$work/fail"
grep -Fq "missing terminal" "$work/fail"
grep -Fq "Required failures must be fixed" "$work/err"
