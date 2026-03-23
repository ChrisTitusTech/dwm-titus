#!/bin/bash

# .xinitrc — only used when starting dwm via startx (not SDDM)
# All setup (DPMS, dbus env, services) is handled by autostart.sh

dbus-run-session -- sh -c 'exec dwm'
