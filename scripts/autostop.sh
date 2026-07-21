#!/bin/sh

set -eu

# A display manager can start a new X11 login before the per-user systemd
# manager has stopped the previous graphical target. Stop it explicitly so
# XDG autostart services are activated again in the next dwm session.
if command -v systemctl >/dev/null 2>&1; then
	systemctl --user stop \
		xdg-desktop-autostart.target \
		wm-graphical-session.service \
		graphical-session.target \
		>/dev/null 2>&1 || true
fi

# setsid(1) does not move Quickshell, Picom, or the other managed helpers out
# of the login session's systemd scope. Explicitly terminating our own session
# prevents stale helpers from making the next autostart pass skip replacements.
session_id=${XDG_SESSION_ID:-}
if [ -n "$session_id" ] && command -v loginctl >/dev/null 2>&1; then
	session_owner=$(loginctl show-session "$session_id" -p Name 2>/dev/null || true)
	if [ "$session_owner" = "Name=$(id -un)" ]; then
		loginctl terminate-session "$session_id" >/dev/null 2>&1 || true
	fi
fi
