#!/bin/bash
# Offline Anaconda %post: system packages and assets are already in the image.
set -euo pipefail
[[ ${1:-} == --installer-target && -f /etc/dwm-titus-image ]]
[[ $(id -u) == 0 ]]
source_dir=/usr/share/dwm-titus-image
mapfile -t users < <(awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ {print $1}' /etc/passwd)
((${#users[@]} > 0)) || {
	echo 'Create a regular user in Anaconda.' >&2
	exit 1
}
for user in "${users[@]}"; do
	home=$(getent passwd "$user" | cut -d: -f6)
	[[ $home == /home/* && ! -L $home ]]
	target="$home/.local/share/dwm-titus"
	for directory in "$home/.local" "$home/.local/share"; do
		[[ ! -L $directory && (! -e $directory || -d $directory) ]] || {
			printf 'Unsafe user data directory: %s\n' "$directory" >&2
			exit 1
		}
		if [[ ! -e $directory ]]; then
			install -d -o "$user" -g "$(id -gn "$user")" "$directory"
		fi
	done
	[[ ! -e $target && ! -L $target ]]
	cp -a "$source_dir" "$target"
	chown -R "$user:$(id -gn "$user")" "$target"
	# Expanded under the real user, not the installer.
	# shellcheck disable=SC2016
	runuser -u "$user" -- env -i HOME="$home" USER="$user" LOGNAME="$user" \
		PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 \
		dbus-run-session -- bash -ec '
export DBUS_SYSTEM_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS
cd "$HOME/.local/share/dwm-titus"
make install-user
# Legacy xz captures predate these tools and seeders. Keep their installation
# path usable; package/default upgrades require rebuilding the factory image.
if [[ -f scripts/image/seed-terminal.sh ]]; then bash scripts/image/seed-terminal.sh; fi
if [[ -f scripts/image/seed-apps.sh ]]; then bash scripts/image/seed-apps.sh; fi
xdg-user-dirs-update
mkdir -p "$HOME/Pictures/backgrounds"
wallpaper="$HOME/Pictures/backgrounds/dwm-titus.jpg"
if [[ ! -e $wallpaper && ! -L $wallpaper ]]; then
	install -m 0644 lightdm/wallpaper.jpg "$wallpaper"
fi
scripts/install-gearlever
'
	if getent group gamemode >/dev/null; then usermod -aG gamemode "$user"; fi
done
systemctl enable NetworkManager lightdm
systemctl set-default graphical.target
