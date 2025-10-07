#!/usr/bin/env bash

THEME="minimal"

# Kill all existing polybar instances
killall polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

CONFIG_FILE="$HOME/.local/share/dwm-titus/polybar/themes/$THEME/config.ini"
LAPTOP_CONFIG_FILE="$HOME/.local/share/dwm-titus/polybar/themes/$THEME/laptop-config.ini"

if ls /sys/class/power_supply/ 2>/dev/null | grep -q '^BAT'; then
	CONFIG_FILE=$LAPTOP_CONFIG_FILE
fi

# Check if xrandr is available and get monitor list
if command -v xrandr > /dev/null 2>&1; then
    # Get list of connected monitors
    mapfile -t MONITORS < <(xrandr --query | grep " connected" | cut -d" " -f1)
    MONITOR_COUNT=${#MONITORS[@]}
    
    # Detect primary monitor
    PRIMARY_MONITOR=$(xrandr --query | grep " connected primary" | cut -d" " -f1)
    
    # If no primary monitor is explicitly set, use the first one
    if [ -z "$PRIMARY_MONITOR" ]; then
        PRIMARY_MONITOR=${MONITORS[0]}
        echo "No primary monitor detected, using first monitor: $PRIMARY_MONITOR"
    else
        echo "Primary monitor detected: $PRIMARY_MONITOR"
    fi
    
    echo "Detected $MONITOR_COUNT monitors: ${MONITORS[*]}"
    
    if [ $MONITOR_COUNT -eq 1 ]; then
        # Single monitor setup - launch main bar with tray and EWMH
        echo "Single monitor setup - launching main polybar with tray and EWMH on ${MONITORS[0]}"
        MONITOR=${MONITORS[0]} polybar main -c "$CONFIG_FILE" &
    else
        # Multi-monitor setup
        echo "Multi-monitor setup - EWMH and systray only on primary monitor"
        
        # Launch polybar on all connected monitors
        for monitor in "${MONITORS[@]}"; do
            if [ "$monitor" = "$PRIMARY_MONITOR" ]; then
                # Primary monitor gets the tray and EWMH
                MONITOR=$monitor polybar main -c "$CONFIG_FILE" &
                echo "Launched primary polybar with tray and EWMH on $monitor"
            else
                # Secondary monitors don't get the tray or EWMH
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
