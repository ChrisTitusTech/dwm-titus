#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH="$ROOT_DIR/config/polybar/launch.sh"
BASH_BIN="${BASH:-/usr/bin/bash}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p \
	"$work/bin" \
	"$work/home/.config/polybar" \
	"$work/net/wlan0/wireless" \
	"$work/net/eth0" \
	"$work/power/BAT0" \
	"$work/power/AC" \
	"$work/thermal/thermal_zone2"

printf '%s\n' 42000 >"$work/thermal/thermal_zone2/temp"

cat >"$work/bin/pgrep" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT

cat >"$work/bin/xrandr" <<'SCRIPT'
#!/bin/sh
cat <<'XRANDR'
HDMI-1 connected primary 1920x1080+0+0
DP-1 connected 1920x1080+1920+0
XRANDR
SCRIPT

cat >"$work/bin/pactl" <<'SCRIPT'
#!/bin/sh
test "$1" = info
SCRIPT

cat >"$work/bin/polybar" <<'SCRIPT'
#!/bin/sh
{
    printf 'bar=%s\n' "$1"
    printf 'monitor=%s\n' "$MONITOR"
    printf 'main=%s\n' "$DWM_POLYBAR_MAIN_RIGHT"
    printf 'secondary=%s\n' "$DWM_POLYBAR_SECONDARY_RIGHT"
    printf 'battery=%s adapter=%s wlan=%s wired=%s thermal=%s\n' \
        "${DWM_BATTERY:-}" "${DWM_ADAPTER:-}" "${DWM_WLAN_INTERFACE:-}" \
        "${DWM_WIRED_INTERFACE:-}" "${DWM_THERMAL_ZONE:-}"
} >>"$DWM_POLYBAR_TEST_LOG"
SCRIPT

cat >"$work/bin/xdotool" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT

chmod +x "$work/bin/"*

env \
	DWM_POLYBAR_POWER_SUPPLY_DIR="$work/power" \
	DWM_POLYBAR_NET_DIR="$work/net" \
	DWM_POLYBAR_THERMAL_DIR="$work/thermal" \
	DWM_POLYBAR_TEST_LOG="$work/polybar.log" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$LAUNCH"

for _ in 1 2 3 4 5; do
	[ -f "$work/polybar.log" ] && break
	sleep 0.1
done

grep -Fq "bar=main" "$work/polybar.log"
grep -Fq "bar=secondary" "$work/polybar.log"
grep -Fq "main=battery pulseaudio wlan wired temperature date powermenu tray" "$work/polybar.log"
grep -Fq "secondary=pulseaudio wlan wired temperature date" "$work/polybar.log"
grep -Fq "battery=BAT0 adapter=AC wlan=wlan0 wired=eth0 thermal=2" "$work/polybar.log"

rm -f "$work/polybar.log" "$work/bin/pactl"
rm -rf "$work/power/BAT0" "$work/net/wlan0" "$work/thermal/thermal_zone2"

env \
	DWM_POLYBAR_POWER_SUPPLY_DIR="$work/power" \
	DWM_POLYBAR_NET_DIR="$work/net" \
	DWM_POLYBAR_THERMAL_DIR="$work/thermal" \
	DWM_POLYBAR_ENABLE_AUDIO=0 \
	DWM_POLYBAR_ENABLE_TRAY=0 \
	DWM_POLYBAR_TEST_LOG="$work/polybar.log" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$BASH_BIN" "$LAUNCH"

for _ in 1 2 3 4 5; do
	[ -f "$work/polybar.log" ] && break
	sleep 0.1
done

grep -Fq "main=wired date powermenu" "$work/polybar.log"
if grep -Eq '^main=.*(battery|pulseaudio|wlan|temperature|tray)' "$work/polybar.log"; then
	echo "disabled capabilities leaked into module list" >&2
	exit 1
fi
