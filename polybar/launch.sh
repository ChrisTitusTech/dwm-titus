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
    
    if [ $MONITOR_COUNT -eq 1 ]; then
        # Single monitor setup - launch main bar with tray
        echo "Single monitor setup - launching main polybar with tray on ${MONITORS[0]}"
        MONITOR=${MONITORS[0]} polybar main -c "$CONFIG_FILE" &
    else
        # Multi-monitor setup
        echo "Multi-monitor setup - using EWMH on all monitors, DWM handles tag assignment"
        
        # Launch polybar on all connected monitors
        # First monitor gets the tray, others don't
        for i in "${!MONITORS[@]}"; do
            monitor="${MONITORS[$i]}"
            if [ $i -eq 0 ]; then
                # Primary monitor gets the tray
                MONITOR=$monitor polybar main -c "$CONFIG_FILE" &
                echo "Launched primary polybar with tray on $monitor"
            else
                # Secondary monitors don't get the tray
                MONITOR=$monitor polybar secondary -c "$CONFIG_FILE" &
                echo "Launched secondary polybar without tray on $monitor"
            fi
        done
    fi
else
    # Fallback: launch main bar if xrandr is not available
    echo "xrandr not available - launching fallback main polybar with tray"
    polybar main -c "$CONFIG_FILE" &
fi
