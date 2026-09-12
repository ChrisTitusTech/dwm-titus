#!/bin/bash
# Apply defaults only to a fresh image account, preserving any local MIME file.
set -euo pipefail
[[ $(id -u) != 0 ]]
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
for file in "$config_home/mimeapps.list" "$data_home/applications/mimeapps.list" \
	"$data_home/applications/defaults.list"; do
	if [[ -e $file || -L $file ]]; then
		printf 'Preserving existing application defaults: %s\n' "$file"
		exit 0
	fi
done
dwm-default-apps set-role browser brave-origin.desktop
# Use exactly the image formats advertised by Fedora's installed sxiv entry.
mapfile -t image_mimes < <(
	python3 - <<'PY'
import configparser
p = configparser.ConfigParser(interpolation=None)
p.read('/usr/local/share/applications/sxiv.desktop')
for mime in p['Desktop Entry']['MimeType'].split(';'):
    if mime.startswith('image/'):
        print(mime)
PY
)
((${#image_mimes[@]} > 0))
xdg-mime default sxiv.desktop "${image_mimes[@]}"
