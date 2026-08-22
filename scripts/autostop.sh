#!/bin/sh

set -eu

command -v loginctl >/dev/null 2>&1 || exit 0
self_session_id=$(loginctl show-session self -p Id --value 2>/dev/null) || exit 0
[ -n "$self_session_id" ] || exit 0
case "${XDG_SESSION_ID:-$self_session_id}" in
"$self_session_id") session_id=$self_session_id ;;
*) exit 0 ;;
esac

session_details=$(loginctl show-session "$session_id" \
	-p Name -p Type -p Class -p Active -p Display 2>/dev/null) || exit 0
session_owner=$(printf '%s\n' "$session_details" | sed -n 's/^Name=//p')
session_type=$(printf '%s\n' "$session_details" | sed -n 's/^Type=//p')
session_class=$(printf '%s\n' "$session_details" | sed -n 's/^Class=//p')
session_display=$(printf '%s\n' "$session_details" | sed -n 's/^Display=//p')
user_name=$(id -un)
user_id=$(id -u)
[ "$session_owner" = "$user_name" ] || exit 0

status_process_matches() {
	status_current=$(awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			if (fields[1] != "Z" && fields[20] ~ /^[0-9]+$/) print fields[20]
		}
	' "/proc/$status_pid/stat" 2>/dev/null) || return 1
	[ "$status_current" = "$status_starttime" ] || return 1
	[ "$(stat -c %u "/proc/$status_pid" 2>/dev/null)" = "$user_id" ] || return 1
	status_process_display=$({
		tr '\0' '\n' <"/proc/$status_pid/environ"
	} 2>/dev/null | awk '
		index($0, "DISPLAY=") == 1 {
			value = substr($0, 9)
			matches++
		}
		END {
			if (matches == 1) print value
			exit(matches == 1 ? 0 : 1)
		}
	') || return 1
	[ "$status_process_display" = "${DISPLAY:-}" ] || return 1
	status_process_command=$({
		tr '\0' '\n' <"/proc/$status_pid/cmdline"
	} 2>/dev/null) || return 1
	status_arg1=$(printf '%s\n' "$status_process_command" | sed -n '2p')
	status_arg2=$(printf '%s\n' "$status_process_command" | sed -n '3p')
	[ -n "$status_arg1" ] && [ -z "$status_arg2" ] || return 1
	status_script=$(readlink -f -- "$status_arg1" 2>/dev/null) || return 1
	[ "$status_script" = "$status_command_path" ]
}

remove_scoped_status_identity() {
	status_current_identity=
	IFS= read -r status_current_identity <"$status_identity_file" || true
	[ "$status_current_identity" = "$status_identity" ] || return 0
	rm -f -- "$status_identity_file"
}

stop_scoped_status() {
	[ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] &&
		[ ! -L "$XDG_RUNTIME_DIR" ] || return 0
	command -v sha256sum >/dev/null 2>&1 || return 0
	status_command=$(command -v dwm-status 2>/dev/null) || return 0
	status_command_path=$(readlink -f -- "$status_command" 2>/dev/null) || return 0
	status_display_key=$(printf '%s' "${DISPLAY:-}" | sha256sum | awk '{ print $1 }')
	case $status_display_key in *[!0-9a-f]* | '') return 0 ;; esac
	status_identity_file=$XDG_RUNTIME_DIR/dwm-titus/dwm-status.$status_display_key.identity
	[ -f "$status_identity_file" ] && [ ! -L "$status_identity_file" ] || return 0
	status_pid=
	status_starttime=
	status_extra=
	IFS=: read -r status_pid status_starttime status_extra <"$status_identity_file" || true
	case $status_pid in *[!0-9]* | '') return 0 ;; esac
	case $status_starttime in *[!0-9]* | '') return 0 ;; esac
	[ -z "$status_extra" ] || return 0
	status_identity=$status_pid:$status_starttime
	if ! status_process_matches; then
		remove_scoped_status_identity
		return 0
	fi
	kill -TERM "$status_pid" 2>/dev/null || true
	status_attempt=0
	while [ "$status_attempt" -lt 20 ] && status_process_matches; do
		status_attempt=$((status_attempt + 1))
		sleep 0.05
	done
	if status_process_matches; then
		kill -KILL "$status_pid" 2>/dev/null || true
	fi
	status_attempt=0
	while [ "$status_attempt" -lt 20 ] && status_process_matches; do
		status_attempt=$((status_attempt + 1))
		sleep 0.05
	done
	status_process_matches && return 0
	remove_scoped_status_identity
}

stop_scoped_status

# A nested X server inherits the parent login's logind and XDG session IDs.
# Refuse to clean up that login unless this dwm instance is attached to the
# display that logind records for it. Accept an explicit X11 screen suffix,
# such as :0.0, in addition to the session-wide :0 display name.
case "$session_type:$session_class:$session_display" in
x11:user:?*)
	case "${DISPLAY:-}" in
	"$session_display" | "$session_display".[0-9]*) ;;
	*) exit 0 ;;
	esac
	;;
esac

# The systemd user manager and its graphical targets are shared across all
# sessions for this user. Leave them active when another graphical login still
# needs them.
stop_targets=1
user_sessions=$(loginctl show-user "$user_id" -p Sessions --value 2>/dev/null) || stop_targets=0
if [ "$stop_targets" -eq 1 ]; then
	for other_id in $user_sessions; do
		[ "$other_id" != "$session_id" ] || continue
		other_details=$(loginctl show-session "$other_id" \
			-p Name -p Type -p Class -p Active 2>/dev/null) || {
			stop_targets=0
			break
		}
		other_owner=$(printf '%s\n' "$other_details" | sed -n 's/^Name=//p')
		other_type=$(printf '%s\n' "$other_details" | sed -n 's/^Type=//p')
		other_class=$(printf '%s\n' "$other_details" | sed -n 's/^Class=//p')
		other_active=$(printf '%s\n' "$other_details" | sed -n 's/^Active=//p')
		case "$other_type:$other_class:$other_active" in
		x11:user:yes | wayland:user:yes)
			if [ "$other_owner" = "$user_name" ]; then
				stop_targets=0
				break
			fi
			;;
		esac
	done
fi

# A display manager can start a new X11 login before the per-user systemd
# manager has stopped the previous graphical target. Stop it explicitly only
# when no other graphical login shares the user manager.
if [ "$stop_targets" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
	systemctl --user stop \
		xdg-desktop-autostart.target \
		wm-graphical-session.service \
		graphical-session.target \
		>/dev/null 2>&1 || true
fi

# A display-manager X11 session has its own logind scope, so terminate it to
# remove detached helpers before LightDM starts the next login. startx inherits
# a TTY session instead; let dwm return to that TTY without logging the user out.
case "$session_type:$session_class:$session_display" in
x11:user:?*) loginctl terminate-session "$session_id" >/dev/null 2>&1 || true ;;
esac
