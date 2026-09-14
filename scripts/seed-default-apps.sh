#!/bin/bash
# Seed fresh Fedora accounts; never replace existing application preferences.
set -euo pipefail
[[ $(id -u) != 0 ]]
[[ $# == 0 || ($# == 1 && $1 == --image) ]]
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
# Desktop-specific files take precedence over the generic MIME file too.
shopt -s nullglob
for file in "$config_home/mimeapps.list" "$config_home/"*-mimeapps.list \
	"$data_home/applications/mimeapps.list" "$data_home/applications/"*-mimeapps.list \
	"$data_home/applications/defaults.list"; do
	if [[ -e $file || -L $file ]]; then
		printf 'Preserving existing application defaults: %s\n' "$file"
		exit 0
	fi
done
# Resolve installed XDG entries, validate all handlers before writing, and
# advertise only the media/image formats supported by those entries.
associations=$(
	python3 - "${1:-}" <<'PY'
import configparser
import os
from pathlib import Path
import shutil
import sys

roots = [Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))]
roots += [Path(p) for p in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':') if p]

def entry(desktop, command, prefixes, required=True):
    path = next((root / 'applications' / desktop for root in roots
                 if (root / 'applications' / desktop).is_file()), None)
    if path is None or shutil.which(command) is None:
        if required:
            sys.exit(f'Missing default application: {desktop} ({command})')
        return
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    parser.read(path)
    app = parser['Desktop Entry']
    if app.get('Hidden', 'false').lower() == 'true' or app.get('Type') != 'Application':
        sys.exit(f'Unusable default application: {desktop}')
    mimes = [m for m in app.get('MimeType', '').split(';') if m.startswith(prefixes)]
    if not mimes:
        sys.exit(f'No supported MIME types advertised by {desktop}')
    for mime in mimes:
        print(f'{mime}={desktop};')

entry('io.github.celluloid_player.Celluloid.desktop', 'celluloid', ('audio/', 'video/', 'application/'))
entry('sxiv.desktop', 'sxiv', ('image/',))
entry('brave-origin.desktop', 'brave-origin', ('text/html', 'x-scheme-handler/http', 'application/xhtml', 'application/pdf'), required=sys.argv[1] == '--image')
entry('thunar.desktop', 'thunar', ('inode/directory',), required=False)
PY
)
# Atomic publication avoids leaving a partial MIME file after an error.
mkdir -p "$config_home"
target=$(mktemp "$config_home/.dwm-mimeapps.XXXXXX")
trap 'rm -f "$target"' EXIT
printf '[Default Applications]\n%s\n' "$associations" >"$target"
# Link the complete file without replacing a preference written since the
# initial check. A rename would silently overwrite that concurrent choice.
if ! ln -T -- "$target" "$config_home/mimeapps.list"; then
	if [[ -e $config_home/mimeapps.list || -L $config_home/mimeapps.list ]]; then
		printf 'Preserving existing application defaults: %s\n' "$config_home/mimeapps.list"
		exit 0
	fi
	printf 'Could not publish application defaults: %s\n' "$config_home/mimeapps.list" >&2
	exit 1
fi
printf 'Configured fresh-account media, image, and available browser/file-manager defaults.\n'
