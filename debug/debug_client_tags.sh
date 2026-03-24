#!/bin/bash

echo "=== Detailed Client Tag Analysis ==="
echo ""
echo "Getting window list..."
window_ids=$(xprop -root _NET_CLIENT_LIST | cut -d'#' -f2 | tr ',' '\n' | tr -d ' ' | grep -v '^$')

for win_id in $window_ids; do
    echo "=========================================="
    echo "Window ID: $win_id"
    
    # Get window name
    name=$(xprop -id "$win_id" WM_NAME 2>/dev/null | cut -d'=' -f2 | tr -d '"' | xargs)
    echo "Name: $name"
    
    # Get desktop assignment
    desktop=$(xprop -id "$win_id" _NET_WM_DESKTOP 2>/dev/null | awk '{print $NF}')
    echo "Desktop (_NET_WM_DESKTOP): $desktop"
    
    # Get window state (mapped/unmapped)
    state=$(xprop -id "$win_id" WM_STATE 2>/dev/null | awk '{print $3}')
    echo "WM_STATE: $state"
    
    # Get window geometry
    geom=$(xwininfo -id "$win_id" 2>/dev/null | grep "Absolute upper-left")
    if [ -n "$geom" ]; then
        x_pos=$(echo "$geom" | grep "X:" | awk '{print $4}')
        y_pos=$(echo "$geom" | grep "Y:" | awk '{print $4}')
        echo "Position: x=$x_pos, y=$y_pos"
        
        if [ "$x_pos" -lt "-1000" ]; then
            echo "Visibility: HIDDEN (off-screen)"
        else
            echo "Visibility: VISIBLE"
        fi
    fi
    
    echo ""
done

echo "=========================================="
echo "Current Desktop: $(xprop -root _NET_CURRENT_DESKTOP | awk '{print $NF}')"
echo "Number of Desktops: $(xprop -root _NET_NUMBER_OF_DESKTOPS | awk '{print $NF}')"
