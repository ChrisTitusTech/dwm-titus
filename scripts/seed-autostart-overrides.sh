#!/bin/sh

set -eu

config_home=${XDG_CONFIG_HOME:-${HOME:?HOME is not set}/.config}
config_dirs=${XDG_CONFIG_DIRS:-/etc/xdg}
destination_dir=$config_home/autostart
target_owner=${DWM_INSTALL_OWNER:-}
target_group=
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

if [ -n "$target_owner" ]; then
	target_group=$(id -gn "$target_owner")
fi

find_vendor_entry() {
	entry=$1
	old_ifs=$IFS
	IFS=:
	# XDG_CONFIG_DIRS is a colon-delimited search path.
	# shellcheck disable=SC2086
	set -- $config_dirs
	IFS=$old_ifs

	for config_dir; do
		[ -n "$config_dir" ] || continue
		candidate=$config_dir/autostart/$entry
		if [ -f "$candidate" ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

add_dwm_exclusion() {
	awk '
		function with_dwm_exclusion(value) {
			if (value ~ /(^|;)X-DWM(;|$)/)
				return value
			if (value != "" && value !~ /;$/)
				value = value ";"
			return value "X-DWM;"
		}

		$0 == "[Desktop Entry]" {
			in_desktop = 1
			seen_desktop = 1
			print
			next
		}

		in_desktop && /^\[/ {
			if (!updated)
				print "NotShowIn=X-DWM;"
			in_desktop = 0
		}

		in_desktop && /^NotShowIn=/ {
			print "NotShowIn=" with_dwm_exclusion(substr($0, 11))
			updated = 1
			next
		}

		{ print }

		END {
			if (in_desktop && !updated)
				print "NotShowIn=X-DWM;"
			if (!seen_desktop)
				exit 1
		}
	' "$1"
}

if [ ! -e "$destination_dir" ] && [ ! -L "$destination_dir" ]; then
	if [ -n "$target_owner" ]; then
		install -d -o "$target_owner" -g "$target_group" -m 755 \
			"$destination_dir"
	else
		mkdir -p "$destination_dir"
	fi
else
	mkdir -p "$destination_dir"
fi

for entry in \
	light-locker.desktop \
	picom.desktop \
	polkit-mate-authentication-agent-1.desktop; do
	destination=$destination_dir/$entry
	if [ -e "$destination" ] || [ -L "$destination" ]; then
		printf '  Preserving existing %s\n' "$destination"
		continue
	fi

	if ! source_entry=$(find_vendor_entry "$entry"); then
		continue
	fi
	if ! add_dwm_exclusion "$source_entry" >"$tmp"; then
		printf 'Warning: could not scope invalid autostart entry: %s\n' \
			"$source_entry" >&2
		continue
	fi

	if [ -n "$target_owner" ]; then
		install -o "$target_owner" -g "$target_group" -m 644 \
			"$tmp" "$destination"
	else
		install -m 644 "$tmp" "$destination"
	fi
	printf '  Seeded dwm-scoped autostart override: %s\n' "$entry"
done
