#!/bin/sh

set -eu

hotkeys="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/hotkeys.toml"
# The stock TOML binding contains the literal variable name "$webapp".
# shellcheck disable=SC2016
legacy_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["$webapp", "https://chatgpt.com"] },'
replacement_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["dwm-quickshell-launcher", "launch-chatgpt"] },'
temp_file=

cleanup() {
	if [ -n "$temp_file" ]; then
		rm -f -- "$temp_file"
	fi
}

trap cleanup EXIT HUP INT TERM

if [ ! -e "$hotkeys" ]; then
	exit 0
fi

if [ -L "$hotkeys" ] || [ ! -f "$hotkeys" ]; then
	printf 'dwm-titus: warning: preserving non-regular hotkeys file at %s\n' \
		"$hotkeys" >&2
	exit 0
fi

match_count=$(awk -v legacy="$legacy_binding" '
	$0 == legacy { count++ }
	END { print count + 0 }
' "$hotkeys")

case $match_count in
0)
	exit 0
	;;
1) ;;
*)
	printf 'dwm-titus: warning: preserving %s because the legacy ChatGPT binding appears more than once\n' \
		"$hotkeys" >&2
	exit 0
	;;
esac

config_dir=${hotkeys%/*}
temp_file=$(mktemp "$config_dir/.hotkeys.toml.XXXXXX")
awk -v legacy="$legacy_binding" -v replacement="$replacement_binding" '
	$0 == legacy { print replacement; next }
	{ print }
' "$hotkeys" >"$temp_file"
chmod --reference="$hotkeys" "$temp_file"
mv -f -- "$temp_file" "$hotkeys"
temp_file=

printf 'dwm-titus: migrated the stock ChatGPT hotkey to prefer the desktop application\n'
