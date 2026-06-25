#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$ROOT_DIR/scripts/dwm-display-profile"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/profiles"

cat >"$work/profiles/desk.conf" <<'PROFILE'
# primary monitor
HDMI-1 --primary --mode 2560x1440 --rate 144

# disabled monitor
DP-1 --off
PROFILE

cat >"$work/bin/xrandr" <<'SCRIPT'
#!/bin/sh
if [ "$1" = "--query" ]; then
	printf '%s\n' "HDMI-1 connected primary 2560x1440+0+0"
	exit 0
fi
printf '%s\n' "$*" >"$DWM_XRANDR_OUT"
SCRIPT
chmod +x "$work/bin/xrandr"

env_common=(
	DWM_DISPLAY_PROFILE_DIR="$work/profiles"
	DWM_XRANDR_OUT="$work/xrandr"
	HOME="$work/home"
	PATH="$work/bin:/usr/bin:/bin"
)

mkdir -p "$work/home"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" dir >"$work/dir"
grep -Fqx "$work/profiles" "$work/dir"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" list >"$work/list"
grep -Fqx "desk" "$work/list"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" apply desk
grep -Fqx -- "--output HDMI-1 --primary --mode 2560x1440 --rate 144 --output DP-1 --off" "$work/xrandr"

env "${env_common[@]}" "$BASH_BIN" "$HELPER" current >"$work/current"
grep -Fqx "HDMI-1 connected primary 2560x1440+0+0" "$work/current"

if env "${env_common[@]}" "$BASH_BIN" "$HELPER" apply ../bad 2>"$work/err"; then
	echo "invalid profile name was accepted" >&2
	exit 1
fi
grep -Fq "invalid profile name" "$work/err"
