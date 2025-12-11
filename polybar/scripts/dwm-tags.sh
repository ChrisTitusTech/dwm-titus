#!/bin/bash

# Color configuration (using colors from colors.ini)
COLOR_ACTIVE="${DWM_TAG_ACTIVE_COLOR:-#eceff4}"      # white from colors.ini
COLOR_OCCUPIED="${DWM_TAG_OCCUPIED_COLOR:-#d8dee9}"  # fg from colors.ini
COLOR_URGENT="${DWM_TAG_URGENT_COLOR:-#bf616a}"      # red from colors.ini
FONT_ACTIVE="${DWM_TAG_ACTIVE_FONT:-2}"              # Font index for active
FONT_OCCUPIED="${DWM_TAG_OCCUPIED_FONT:-4}"          # Font index for occupied
FONT_URGENT="${DWM_TAG_URGENT_FONT:-3}"              # Font index for urgent

# Function to generate and output the tag display
update_tags() {

# Get all client windows from EWMH (much faster than xdotool)
declare -A occupied_tags
declare -A urgent_tags
client_list=$(xprop -root _NET_CLIENT_LIST 2>/dev/null | cut -d'#' -f2)

if [ -n "$client_list" ]; then
    # Parse window IDs and query their desktops
    for win_id in $(echo "$client_list" | tr ',' '\n' | tr -d ' '); do
        if [ -n "$win_id" ]; then
            desktop=$(xprop -id "$win_id" _NET_WM_DESKTOP 2>/dev/null | awk '{print $3}')
            # Skip if not set or is 4294967295 (sticky/all desktops)
            if [ -n "$desktop" ] && [ "$desktop" != "4294967295" ]; then
                occupied_tags[$desktop]=1
                
                # Check for urgent hint
                hints=$(xprop -id "$win_id" WM_HINTS 2>/dev/null)
                if echo "$hints" | grep -q "urgency hint"; then
                    urgent_tags[$desktop]=1
                fi
            fi
        fi
    done
fi

    # Get current desktop from all monitors
    current=$(xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | awk '{print $3}')
    current=${current:-0}

    # Output tags 1-9 - always show at least active tag and occupied tags
    output=""
    has_output=false
    for i in {0..8}; do
        tag=$((i + 1))
        if [ "$i" = "$current" ]; then
            # Active tag (currently selected)
            output+="%{F${COLOR_ACTIVE}}%{T${FONT_ACTIVE}}$tag%{T-}%{F-} "
            has_output=true
        elif [ "${urgent_tags[$i]}" = "1" ]; then
            # Urgent tag (has urgent window)
            output+="%{F${COLOR_URGENT}}%{T${FONT_URGENT}}$tag%{T-}%{F-} "
            has_output=true
        elif [ "${occupied_tags[$i]}" = "1" ]; then
            # Occupied tag (has windows)
            output+="%{F${COLOR_OCCUPIED}}%{T${FONT_OCCUPIED}}$tag%{T-}%{F-} "
            has_output=true
        fi
    done

    # Always output something, even if empty, to prevent polybar from breaking
    if [ "$has_output" = true ]; then
        echo "$output"
    else
        echo " "
    fi
}

# Check if tail mode is enabled (for event-driven updates)
if [ "$1" = "--tail" ]; then
    # Output initial state
    update_tags
    
    # Listen for property changes that indicate desktop/tag changes
    # Monitors: DWM_TAG_UPDATE (custom signal), _NET_CURRENT_DESKTOP (active desktop), 
    # and _NET_CLIENT_LIST (window list changes)
    xprop -root -spy DWM_TAG_UPDATE _NET_CURRENT_DESKTOP _NET_CLIENT_LIST 2>/dev/null | \
    while read -r line; do
        update_tags
    done
else
    # Legacy polling mode - just run once
    update_tags
fi
