#!/bin/bash

# Disable DPMS and screen blanking (prevents NVIDIA GPU OOM on display wake)
xset s off
xset s noblank
xset -dpms

# Export display env to systemd user session (needed for XDG autostart apps)
systemctl --user import-environment DISPLAY XAUTHORITY
dbus-update-activation-environment --systemd DISPLAY XAUTHORITY 2>/dev/null

dbus-run-session -- sh -c '~/.local/share/dwm-titus/polybar/launch.sh & exec dwm'
