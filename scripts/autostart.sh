#!/bin/sh
# dwm-titus autostart — runs in the background after the event loop starts
# Launches services first, starts Polybar, waits for tray, then runs XDG apps.

# Compositor
picom -b 2>/dev/null &

# Notification daemon
dunst 2>/dev/null &

# Polkit authentication agent (try common agents)
for agent in \
    /usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
    /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
    /usr/libexec/polkit-gnome-authentication-agent-1 \
    /usr/lib/polkit-kde-authentication-agent-1 \
    /usr/libexec/polkit-kde-authentication-agent-1 \
    /usr/bin/lxpolkit \
    /usr/lib/lxpolkit/lxpolkit; do
    if [ -x "$agent" ]; then
        "$agent" &
        break
    fi
done

# Launch Polybar (skip if already running, e.g. started by .xinitrc)
if ! pgrep -x polybar >/dev/null 2>&1; then
    for pb_launch in \
        "$HOME/.config/polybar/launch.sh" \
        "$HOME/.local/share/dwm-titus/polybar/launch.sh"; do
        if [ -x "$pb_launch" ]; then
            "$pb_launch" &
            break
        fi
    done
fi

# Wait for Polybar's tray to be ready before launching tray apps
# Polybar needs time to claim _NET_SYSTEM_TRAY_S0 after its window appears
timeout=50
i=0
while [ $i -lt $timeout ]; do
    if xdotool search --class Polybar >/dev/null 2>&1; then
        sleep 1  # extra delay for tray module initialization
        break
    fi
    sleep 0.2
    i=$((i + 1))
done

# XDG Desktop Autostart — launches tray apps (nm-applet, blueman, etc.)
dex -a 2>/dev/null
