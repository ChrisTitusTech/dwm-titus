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
printf 'Image user defaults preservation: PASS\n'
