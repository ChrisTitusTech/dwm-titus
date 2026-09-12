#!/bin/bash
# Called as the newly created image user; never rewrite a customized shell.
set -euo pipefail
[[ $(id -u) != 0 ]]
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
skel_dir=${SKEL_DIR:-/etc/skel}
bashrc=$HOME/.bashrc
if [[ -L $bashrc ]]; then
	exit 0
fi
if [[ -e $bashrc ]] && ! cmp -s "$bashrc" "$skel_dir/.bashrc"; then
	printf 'Preserving existing Bash configuration: %s\n' "$bashrc"
	exit 0
fi
# Fedora's stock .bashrc also sources user-owned .bashrc.d fragments. A stock
# .bashrc alone does not establish that this account has an untouched prompt.
for startup in .bash_profile .bash_login .profile; do
	if [[ -L $HOME/$startup ]] || { [[ -e $HOME/$startup ]] && ! cmp -s "$HOME/$startup" "$skel_dir/$startup"; }; then
		printf 'Preserving existing shell startup: %s\n' "$HOME/$startup"
		exit 0
	fi
done
if [[ -L $HOME/.bashrc.d ]]; then
	exit 0
fi
for fragment in "$HOME/.bashrc.d/"*; do
	if [[ -e $fragment || -L $fragment ]]; then
		printf 'Preserving existing Bash startup fragment: %s\n' "$fragment"
		exit 0
	fi
done
[[ -f $config_home/starship/starship.toml ]]
cat >>"$bashrc" <<'BASH'

# dwm-titus image: initialize the prompt only in interactive Bash sessions.
case $- in
*i*)
	if command -v starship >/dev/null && ! declare -F starship_precmd >/dev/null; then
		if [[ -z ${STARSHIP_CONFIG:-} && ! -e ${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml ]]; then
			export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship/starship.toml"
		fi
		eval "$(starship init bash)"
	fi
	;;
esac
BASH
