#!/bin/bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ $(id -u) == 0 ]]; then
	# Exercise the real unprivileged guard even in root-run Fedora containers.
	mkdir -p "$work/repo/tests" "$work/repo/scripts/image" "$work/repo/config/starship"
	cp "$0" "$work/repo/tests/"
	cp "$repo/scripts/image/seed-terminal.sh" "$repo/scripts/image/seed-apps.sh" "$work/repo/scripts/image/"
	cp "$repo/config/starship/starship.toml" "$work/repo/config/starship/"
	cp "$repo/scripts/seed-default-apps.sh" "$work/repo/scripts/"
	chown -R nobody:"$(id -gn nobody)" "$work"
	runuser -u nobody -- env TMPDIR="$work" bash "$work/repo/tests/test-image-user-defaults.sh"
	exit
fi
export HOME=$work/home XDG_CONFIG_HOME=$work/home/.config XDG_DATA_HOME=$work/home/.local/share
export SKEL_DIR=$work/skel
mkdir -p "$XDG_CONFIG_HOME/starship" "$work/bin" "$SKEL_DIR"
cat >"$SKEL_DIR/.bashrc" <<'RC'
# Stock Fedora .bashrc
export PATH=$PATH:$HOME/.local/bin:$HOME/bin
if [ -d ~/.bashrc.d ]; then
	for rc in ~/.bashrc.d/*; do
		if [ -f "$rc" ]; then
			. "$rc"
		fi
	done
fi
unset rc
RC
cat >"$SKEL_DIR/.bash_profile" <<'RC'
# Stock Fedora .bash_profile
[ -f ~/.bashrc ] && . ~/.bashrc
export PATH=$PATH:$HOME/.local/bin:$HOME/bin
RC
cp "$repo/config/starship/starship.toml" "$XDG_CONFIG_HOME/starship/"
cp "$SKEL_DIR/.bashrc" "$HOME/.bashrc"
cp "$SKEL_DIR/.bash_profile" "$HOME/.bash_profile"
cat >"$work/bin/starship" <<'SH'
#!/bin/sh
printf 'init\n' >>"$HOME/invocations"
printf 'export STARSHIP_SHELL=bash\nstarship_precmd() { :; }\n'
SH
chmod +x "$work/bin/starship"
export PATH="$work/bin:$PATH"
bash "$repo/scripts/image/seed-terminal.sh"
cp "$HOME/.bashrc" "$work/seeded"
bash "$repo/scripts/image/seed-terminal.sh"
cmp "$HOME/.bashrc" "$work/seeded"
unset STARSHIP_CONFIG STARSHIP_SHELL
bash --noprofile --rcfile "$HOME/.bashrc" -ic 'source "$HOME/.bashrc"; test "$STARSHIP_SHELL" = bash; test "$STARSHIP_CONFIG" = "$XDG_CONFIG_HOME/starship/starship.toml"; bash --noprofile --rcfile "$HOME/.bashrc" -ic "declare -F starship_precmd >/dev/null"' 2>"$work/interactive.err"
[[ $(wc -l <"$HOME/invocations") == 2 ]]
rm "$HOME/invocations"
bash --noprofile -c 'source "$HOME/.bashrc"; printf "noninteractive\n"' >"$work/output"
[[ $(cat "$work/output") == noninteractive && ! -e $HOME/invocations ]]
printf '# my custom prompt\nPS1="custom> "\n' >"$HOME/.bashrc"
cp "$HOME/.bashrc" "$work/custom"
bash "$repo/scripts/image/seed-terminal.sh"
cmp "$HOME/.bashrc" "$work/custom"
rm "$HOME/.bashrc"
ln -s "$work/custom" "$HOME/.bashrc"
bash "$repo/scripts/image/seed-terminal.sh"
[[ -L $HOME/.bashrc ]]
cmp "$work/custom" "$HOME/.bashrc"
# A stock .bashrc can still source a customized prompt from .bashrc.d.
rm "$HOME/.bashrc"
cp "$SKEL_DIR/.bashrc" "$HOME/.bashrc"
cp "$HOME/.bashrc" "$work/stock"
mkdir "$HOME/.bashrc.d"
printf 'PS1="fragment> "\n' >"$HOME/.bashrc.d/prompt.sh"
bash "$repo/scripts/image/seed-terminal.sh"
cmp "$work/stock" "$HOME/.bashrc"
bash --noprofile --rcfile "$HOME/.bashrc" -ic 'test "$PS1" = "fragment> "' 2>"$work/fragment.err"
[[ ! -e $HOME/invocations ]]
rm "$HOME/.bashrc.d/prompt.sh"
printf '# custom login startup\n' >"$HOME/.bash_profile"
bash "$repo/scripts/image/seed-terminal.sh"
cmp "$work/stock" "$HOME/.bashrc"
# An existing MIME file must prevent any default-setting operation.
printf '[Default Applications]\nimage/png=custom.desktop;\n' >"$XDG_CONFIG_HOME/mimeapps.list"
cp "$XDG_CONFIG_HOME/mimeapps.list" "$work/mime"
bash "$repo/scripts/image/seed-apps.sh"
cmp "$work/mime" "$XDG_CONFIG_HOME/mimeapps.list"
# Exercise a fresh account with real xdg-mime and isolated desktop entries.
export XDG_DATA_DIRS="$work/system-data"
mkdir -p "$XDG_DATA_DIRS/applications"
for app in celluloid sxiv brave-origin thunar; do
	printf '#!/bin/sh\nexit 0\n' >"$work/bin/$app"
	chmod +x "$work/bin/$app"
done
cat >"$XDG_DATA_DIRS/applications/io.github.celluloid_player.Celluloid.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=Celluloid
Exec=celluloid %U
MimeType=audio/mpeg;audio/flac;video/mp4;application/ogg;application/x-matroska;
APP
cat >"$XDG_DATA_DIRS/applications/sxiv.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=sxiv
Exec=sxiv %F
NoDisplay=true
MimeType=image/png;image/jpeg;
APP
cat >"$XDG_DATA_DIRS/applications/brave-origin.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=Brave Origin
Exec=brave-origin %U
MimeType=text/html;x-scheme-handler/http;x-scheme-handler/https;image/png;application/pdf;
APP
cat >"$XDG_DATA_DIRS/applications/thunar.desktop" <<'APP'
[Desktop Entry]
Type=Application
Name=Thunar
Exec=thunar %U
MimeType=inode/directory;
APP
rm "$XDG_CONFIG_HOME/mimeapps.list"
bash "$repo/scripts/image/seed-apps.sh"
for mime in audio/mpeg audio/flac video/mp4 application/ogg application/x-matroska; do
	[[ $(xdg-mime query default "$mime") == io.github.celluloid_player.Celluloid.desktop ]]
done
for mime in image/png image/jpeg; do
	[[ $(xdg-mime query default "$mime") == sxiv.desktop ]]
done
[[ $(xdg-mime query default x-scheme-handler/https) == brave-origin.desktop ]]
[[ $(xdg-mime query default inode/directory) == thunar.desktop ]]
if grep -q 'image/webp=' "$XDG_CONFIG_HOME/mimeapps.list"; then exit 1; fi
cp "$XDG_CONFIG_HOME/mimeapps.list" "$work/seeded-mimes"
bash "$repo/scripts/image/seed-apps.sh"
cmp "$XDG_CONFIG_HOME/mimeapps.list" "$work/seeded-mimes"
# Missing required desktop entries must fail without leaving a partial seed.
rm "$XDG_CONFIG_HOME/mimeapps.list"
mv "$XDG_DATA_DIRS/applications/sxiv.desktop" "$work/sxiv.desktop"
if bash "$repo/scripts/image/seed-apps.sh"; then
	echo 'Missing image handler was accepted' >&2
	exit 1
fi
[[ ! -e $XDG_CONFIG_HOME/mimeapps.list ]]
mv "$work/sxiv.desktop" "$XDG_DATA_DIRS/applications/sxiv.desktop"
# The existing-system path works without enabling a Brave repository.
rm "$XDG_DATA_DIRS/applications/brave-origin.desktop"
bash "$repo/scripts/seed-default-apps.sh"
[[ $(xdg-mime query default video/mp4) == io.github.celluloid_player.Celluloid.desktop ]]
if grep -q brave-origin "$XDG_CONFIG_HOME/mimeapps.list"; then exit 1; fi
rm "$XDG_CONFIG_HOME/mimeapps.list"
printf '[Default Applications]\nimage/png=custom.desktop;\n' >"$XDG_CONFIG_HOME/dwm-mimeapps.list"
bash "$repo/scripts/seed-default-apps.sh"
[[ ! -e $XDG_CONFIG_HOME/mimeapps.list ]]
rm "$XDG_CONFIG_HOME/dwm-mimeapps.list"
# A preference created after discovery but before publication must win.
real_ln=$(command -v ln)
export DWM_TEST_REAL_LN=$real_ln
cat >"$work/bin/ln" <<'SH'
#!/bin/sh
printf '[Default Applications]\ntext/plain=user-editor.desktop;\n' >"$XDG_CONFIG_HOME/mimeapps.list"
exec "$DWM_TEST_REAL_LN" "$@"
SH
chmod +x "$work/bin/ln"
bash "$repo/scripts/seed-default-apps.sh"
printf '[Default Applications]\ntext/plain=user-editor.desktop;\n' >"$work/concurrent-mimes"
cmp "$work/concurrent-mimes" "$XDG_CONFIG_HOME/mimeapps.list"
[[ -z $(find "$XDG_CONFIG_HOME" -name '.dwm-mimeapps.*' -print -quit) ]]
printf 'Image and existing-system user defaults: PASS\n'
