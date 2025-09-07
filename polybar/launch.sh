#!/usr/bin/env bash

THEME="minimal"

# Kill all existing polybar instances
killall polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

CONFIG_FILE="$HOME/.local/share/dwm-titus/polybar/themes/$THEME/config.ini"

# Check if xrandr is available and get monitor list
if command -v xrandr > /dev/null 2>&1; then
    # Get list of connected monitors
    mapfile -t MONITORS < <(xrandr --query | grep " connected" | cut -d" " -f1)
    MONITOR_COUNT=${#MONITORS[@]}
    
    echo "Detected $MONITOR_COUNT monitors: ${MONITORS[*]}"
    echo "Using simple EWMH on all monitors - DWM handles tag assignment"
    
    # Launch polybar on all connected monitors with the same config
    for monitor in "${MONITORS[@]}"; do
        MONITOR=$monitor polybar main -c "$CONFIG_FILE" &
        echo "Launched polybar on $monitor"
    done
else
    # Fallback: launch main bar if xrandr is not available
    polybar main -c "$CONFIG_FILE" &
fi
