#!/usr/bin/env bash
set -euo pipefail

THEME="minimal"
POWER_SUPPLY_DIR="${DWM_POLYBAR_POWER_SUPPLY_DIR:-/sys/class/power_supply}"
NET_DIR="${DWM_POLYBAR_NET_DIR:-/sys/class/net}"
THERMAL_DIR="${DWM_POLYBAR_THERMAL_DIR:-/sys/class/thermal}"

# Kill existing polybar instances only if running
if pgrep -u "$UID" -x polybar >/dev/null 2>&1; then
	killall polybar
	while pgrep -u "$UID" -x polybar >/dev/null; do sleep 0.2; done
fi

# Determine config path: prefer ~/.config/polybar (installed), fallback to repo location
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$HOME/.config/polybar/themes/$THEME/config.ini" ]; then
	CONFIG_DIR="$HOME/.config/polybar"
elif [ -f "$SCRIPT_DIR/themes/$THEME/config.ini" ]; then
	CONFIG_DIR="$SCRIPT_DIR"
else
	CONFIG_DIR="$HOME/.config/polybar"
fi

CONFIG_FILE="$CONFIG_DIR/themes/$THEME/config.ini"

first_power_supply() {
	local pattern=$1
	local entry

	for entry in "$POWER_SUPPLY_DIR"/$pattern; do
		[ -e "$entry" ] || continue
		basename "$entry"
		return 0
	done

	return 1
}

first_network_interface() {
	local kind=$1
	local entry name

	for entry in "$NET_DIR"/*; do
		[ -d "$entry" ] || continue
		name=$(basename "$entry")
		[ "$name" != lo ] || continue

		case "$kind" in
		wireless)
			[ -d "$entry/wireless" ] || continue
			;;
		wired)
			[ ! -d "$entry/wireless" ] || continue
			;;
		esac

		printf '%s\n' "$name"
		return 0
	done

	return 1
}

first_thermal_zone() {
	local entry name

	for entry in "$THERMAL_DIR"/thermal_zone*; do
		[ -r "$entry/temp" ] || continue
		name=$(basename "$entry")
		printf '%s\n' "${name#thermal_zone}"
		return 0
	done

	return 1
}

audio_available() {
	if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
		return 0
	fi

	if command -v wpctl >/dev/null 2>&1 && wpctl status >/dev/null 2>&1; then
		return 0
	fi

	return 1
}

join_modules() {
	local IFS=' '
	printf '%s\n' "$*"
}

main_right=()
secondary_right=()

if DWM_BATTERY=$(first_power_supply 'BAT*'); then
	DWM_ADAPTER=$(first_power_supply 'A*' || true)
	main_right+=(battery)
	export DWM_BATTERY DWM_ADAPTER
fi

if [ "${DWM_POLYBAR_ENABLE_AUDIO:-1}" != 0 ] && audio_available; then
	main_right+=(pulseaudio)
	secondary_right+=(pulseaudio)
fi

if DWM_WLAN_INTERFACE=$(first_network_interface wireless); then
	main_right+=(wlan)
	secondary_right+=(wlan)
	export DWM_WLAN_INTERFACE
fi

if DWM_WIRED_INTERFACE=$(first_network_interface wired); then
	main_right+=(wired)
	secondary_right+=(wired)
	export DWM_WIRED_INTERFACE
fi

if DWM_THERMAL_ZONE=$(first_thermal_zone); then
	main_right+=(temperature)
	secondary_right+=(temperature)
	export DWM_THERMAL_ZONE
fi

main_right+=(date powermenu)
secondary_right+=(date)

if [ "${DWM_POLYBAR_ENABLE_TRAY:-1}" != 0 ]; then
	main_right=("${main_right[@]}" tray)
fi

DWM_POLYBAR_MAIN_RIGHT=$(join_modules "${main_right[@]}")
DWM_POLYBAR_SECONDARY_RIGHT=$(join_modules "${secondary_right[@]}")
export DWM_POLYBAR_MAIN_RIGHT DWM_POLYBAR_SECONDARY_RIGHT

# Check if xrandr is available and get monitor list
if command -v xrandr >/dev/null 2>&1; then
	# Get list of connected monitors
	mapfile -t MONITORS < <(xrandr --query | command grep " connected" | cut -d" " -f1)
	MONITOR_COUNT=${#MONITORS[@]}

	# Detect primary monitor
	PRIMARY_MONITOR=$(xrandr --query | command grep " connected primary" | cut -d" " -f1)

	# If no primary monitor is explicitly set, use the first one
	if [ -z "$PRIMARY_MONITOR" ]; then
		PRIMARY_MONITOR=${MONITORS[0]}
		echo "No primary monitor detected, using first monitor: $PRIMARY_MONITOR"
	else
		echo "Primary monitor detected: $PRIMARY_MONITOR"
	fi

	echo "Detected $MONITOR_COUNT monitors: ${MONITORS[*]}"

	if [ "$MONITOR_COUNT" -eq 1 ]; then
		# Single monitor setup - launch main bar with tray and EWMH
		echo "Single monitor setup - launching main polybar with tray and EWMH on ${MONITORS[0]}"
		MONITOR="${MONITORS[0]}" polybar main -c "$CONFIG_FILE" &
	else
		# Multi-monitor setup
		echo "Multi-monitor setup - EWMH and systray only on primary monitor"

		# Launch polybar on all connected monitors
		for monitor in "${MONITORS[@]}"; do
			if [ "$monitor" = "$PRIMARY_MONITOR" ]; then
				# Primary monitor gets the tray and EWMH
				MONITOR="$monitor" polybar main -c "$CONFIG_FILE" &
				echo "Launched primary polybar with tray and EWMH on $monitor"
			else
				# Secondary monitors don't get the tray or EWMH
				MONITOR="$monitor" polybar secondary -c "$CONFIG_FILE" &
				echo "Launched secondary polybar without tray on $monitor"
			fi
		done
	fi
else
	# Fallback: launch main bar if xrandr is not available
	echo "xrandr not available - launching fallback main polybar with tray"
	polybar main -c "$CONFIG_FILE" &
fi

# Wait for Polybar to be ready before returning.
# This ensures tray apps started after this script can find the tray owner.
attempt=0
while [ "$attempt" -lt 30 ]; do
	if xdotool search --class Polybar >/dev/null 2>&1; then
		break
	fi
	attempt=$((attempt + 1))
	sleep 0.1
done
