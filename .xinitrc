#!/bin/bash

# Disable DPMS and screen blanking (prevents GPU/display wake issues)
xset s off
xset s noblank
xset -dpms

# Export display env to systemd user session (needed for XDG autostart apps)
if command -v systemctl &>/dev/null; then
    systemctl --user import-environment DISPLAY XAUTHORITY
fi
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY 2>/dev/null

# Launch polybar from installed location, with fallback
POLYBAR_LAUNCH=""
for path in \
    "$HOME/.config/polybar/launch.sh" \
    "$HOME/.local/share/dwm-titus/polybar/launch.sh"; do
    if [ -x "$path" ]; then
        POLYBAR_LAUNCH="$path"
        break
    fi
done

if [ -n "$POLYBAR_LAUNCH" ]; then
    dbus-run-session -- sh -c "'$POLYBAR_LAUNCH' & exec dwm"
else
    dbus-run-session -- sh -c 'exec dwm'
fi
