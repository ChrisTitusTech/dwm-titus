#!/bin/bash

echo "=== EWMH Desktop Properties ==="
echo "Number of desktops:"
xprop -root _NET_NUMBER_OF_DESKTOPS

echo -e "\nCurrent desktop:"
xprop -root _NET_CURRENT_DESKTOP

echo -e "\nDesktop names:"
xprop -root _NET_DESKTOP_NAMES

echo -e "\nDesktop viewport:"
xprop -root _NET_DESKTOP_VIEWPORT

echo -e "\nClient list:"
xprop -root _NET_CLIENT_LIST

echo -e "\nActive window:"
xprop -root _NET_ACTIVE_WINDOW

echo -e "\n=== Monitor Information ==="
if command -v xrandr > /dev/null 2>&1; then
    echo "Connected monitors:"
    xrandr --query | grep " connected" | while read -r line; do
        monitor=$(echo "$line" | awk '{print $1}')
        geometry=$(echo "$line" | grep -oP '\d+x\d+\+\d+\+\d+')
        primary=$(echo "$line" | grep -o "primary")
        echo "  $monitor: $geometry $([ -n "$primary" ] && echo "(primary)" || echo "")"
    done
else
    echo "xrandr not available"
fi

echo -e "\n=== Window Desktop Assignments ==="
if [ -n "$(xprop -root _NET_CLIENT_LIST | cut -d'#' -f2)" ]; then
    xprop -root _NET_CLIENT_LIST | cut -d'#' -f2 | tr ',' '\n' | while read -r win_id; do
        if [ -n "$win_id" ]; then
            win_id=$(echo "$win_id" | tr -d ' ')
            echo -e "\nWindow ID: $win_id"
            xprop -id "$win_id" WM_NAME 2>/dev/null | cut -d'=' -f2 || echo "  Name: (unknown)"
            xprop -id "$win_id" _NET_WM_DESKTOP 2>/dev/null || echo "  Desktop: (not set)"
        fi
    done
else
    echo "No client windows found"
fi
