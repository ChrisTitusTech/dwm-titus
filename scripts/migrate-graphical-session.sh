#!/bin/sh

set -eu

systemd_user_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
legacy_unit="$systemd_user_dir/dwm-graphical-session.service"
legacy_wants="$systemd_user_dir/default.target.wants/dwm-graphical-session.service"

info() {
	printf '%s\n' "dwm-titus: $*"
}

warn() {
	printf '%s\n' "dwm-titus: warning: $*" >&2
}

legacy_unit_is_managed() {
	[ -f "$legacy_unit" ] || return 1

	actual=$(sed \
		-e '/^[[:space:]]*#/d' \
		-e '/^[[:space:]]*$/d' \
		"$legacy_unit")
	expected='[Unit]
Description=DWM Graphical Session
BindsTo=graphical-session.target
Wants=graphical-session.target xdg-desktop-autostart.target
After=basic.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
[Install]
WantedBy=default.target'

	[ "$actual" = "$expected" ]
}

if command -v systemctl >/dev/null 2>&1; then
	systemctl --user disable dwm-graphical-session.service >/dev/null 2>&1 || true
fi

if [ -L "$legacy_wants" ]; then
	rm -f "$legacy_wants"
	info "removed legacy graphical-session early-start link"
elif [ -e "$legacy_wants" ]; then
	warn "preserving non-symlink path at $legacy_wants"
fi

if legacy_unit_is_managed; then
	rm -f "$legacy_unit"
	info "removed legacy graphical-session unit"
elif [ -e "$legacy_unit" ]; then
	warn "preserving customized $legacy_unit after disabling early startup"
fi

if command -v systemctl >/dev/null 2>&1 &&
	systemctl --user show-environment >/dev/null 2>&1; then
	systemctl --user daemon-reload >/dev/null 2>&1 ||
		warn "could not reload the systemd user manager"
fi
