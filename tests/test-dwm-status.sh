#!/usr/bin/env bash
set -euo pipefail

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/power/BAT0"
printf '82\n' >"$work/power/BAT0/capacity"
printf 'Discharging\n' >"$work/power/BAT0/status"

cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
case "$*" in
*"get-sink-mute"*) printf 'Mute: no\n' ;;
*"get-sink-volume"*) printf 'Volume: front-left: 0 / 0%% / -inf dB\n' ;;
*) exit 1 ;;
esac
SH
chmod +x "$work/bin/pactl"

cat >"$work/bin/xsetroot" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in
	-name)
		printf '%s\n' "$2" >>"$DWM_STATUS_TEST_LOG"
		exit 0
		;;
	esac
	shift
done
SH
chmod +x "$work/bin/xsetroot"

PATH="$work/bin:/usr/bin:/bin" \
	DWM_STATUS_TEST_LOG="$work/status.log" \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=0.1 \
	timeout 2s "$repo/scripts/dwm-status" &
status_runner=$!

sleep 0.3
printf '81\n' >"$work/power/BAT0/capacity"
wait "$status_runner" || status=$?

case ${status:-0} in
0 | 124 | 143) ;;
*) exit "$status" ;;
esac

grep -Fq 'BAT 82% Discharging |' "$work/status.log"
grep -Fq 'BAT 81% Discharging |' "$work/status.log"
printf 'dwm-status power polling: PASS\n'
