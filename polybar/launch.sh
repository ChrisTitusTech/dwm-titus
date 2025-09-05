#!/usr/bin/env bash

THEME="minimal"

# Kill all existing polybar instances
killall polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

CONFIG_DIR=$HOME/.local/share/dwm-titus/polybar/themes/$THEME/config.ini

# Check if xrandr is available and get monitor list
if command -v xrandr > /dev/null 2>&1; then
    # Get the primary monitor (or first connected monitor as fallback)
    PRIMARY_MONITOR=$(xrandr --query | grep " connected primary" | cut -d" " -f1)
    if [ -z "$PRIMARY_MONITOR" ]; then
        PRIMARY_MONITOR=$(xrandr --query | grep " connected" | head -n1 | cut -d" " -f1)
    fi
    
    # Launch polybar on all connected monitors
    for monitor in $(xrandr --query | grep " connected" | cut -d" " -f1); do
        if [ "$monitor" = "$PRIMARY_MONITOR" ]; then
            # Launch main bar (with EWMH) on primary monitor
            MONITOR=$monitor polybar main -c $CONFIG_DIR &
        else
            # Launch secondary bar (without EWMH) on other monitors
            MONITOR=$monitor polybar secondary -c $CONFIG_DIR &
        fi
    done
else
    # Fallback: launch main bar on primary monitor if xrandr is not available
    polybar main -c $CONFIG_DIR &
fi
