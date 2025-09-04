#!/bin/bash

# Example bar script for Polybar with dwm-anybar patch
# This script should launch your Polybar configuration

# Set the bar height (this should match your Polybar height)
BAR_HEIGHT=30

# Kill any existing Polybar instances
killall -q polybar

# Wait until the processes have been shut down
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

# Launch Polybar
# Replace 'example' with your Polybar configuration name
polybar &

# For demonstration, we'll create a simple xterm bar
# In practice, you would uncomment the polybar line above and remove this
#xterm -geometry 100x1+0+0 -name "Polybar" -e "echo 'Polybar placeholder - configure your actual bar here'; sleep infinity" &

echo "Bar launched."
