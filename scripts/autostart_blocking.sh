#!/bin/sh
# dwm-titus blocking autostart — runs BEFORE the event loop
# Keep this fast: only things that must complete before windows appear.

# D-Bus — required for XDG autostart, notifications, and polkit
dbus-update-activation-environment --systemd --all 2>/dev/null

# Wallpaper
feh --randomize --bg-fill ~/Pictures/backgrounds/* 2>/dev/null
