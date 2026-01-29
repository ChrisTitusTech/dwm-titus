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
            echo -e "\n--- Window ID: $win_id ---"
            xprop -id "$win_id" WM_NAME 2>/dev/null | cut -d'=' -f2 || echo "  Name: (unknown)"
            xprop -id "$win_id" _NET_WM_DESKTOP 2>/dev/null || echo "  Desktop: (not set)"
            
            # Get window geometry to check if visible
            win_geom=$(xwininfo -id "$win_id" 2>/dev/null | grep "Absolute upper-left X")
            if [ -n "$win_geom" ]; then
                x_pos=$(echo "$win_geom" | awk '{print $4}')
                if [ "$x_pos" -lt "-1000" ]; then
                    echo "  Status: HIDDEN (off-screen at x=$x_pos)"
                else
                    echo "  Status: VISIBLE (at x=$x_pos)"
                fi
            fi
        fi
    done
else
    echo "No client windows found"
fi

echo -e "\n=== DWM Tag Distribution Analysis ==="
echo "With 9 tags and 2 monitors:"
echo "  Monitor 0 should handle tags: 1-4 (indices 0-3)"
echo "  Monitor 1 should handle tags: 5-9 (indices 4-8)"
echo ""
echo "Current _NET_CURRENT_DESKTOP value represents the active tag INDEX (0-based)"
echo "Windows should have _NET_WM_DESKTOP set to their tag INDEX"
