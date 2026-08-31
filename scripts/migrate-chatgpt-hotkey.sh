#!/bin/sh

set -eu

hotkeys="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/hotkeys.toml"
backup="${hotkeys}.pre-chatgpt-native.bak"
# The stock TOML binding contains the literal variable name "$webapp".
# shellcheck disable=SC2016
legacy_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["$webapp", "https://chatgpt.com"] },'
replacement_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["dwm-quickshell-launcher", "launch-chatgpt"] },'
backup_temp=
migration_temp=

cleanup() {
	[ -z "$backup_temp" ] || rm -f -- "$backup_temp"
	[ -z "$migration_temp" ] || rm -f -- "$migration_temp"
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
if [ -e "$backup" ] || [ -L "$backup" ]; then
	printf 'dwm-titus: warning: preserving %s because migration backup already exists at %s\n' \
		"$hotkeys" "$backup" >&2
	exit 0
fi

backup_temp=$(mktemp "$config_dir/.hotkeys.toml.backup.XXXXXX")
cp --preserve=all -- "$hotkeys" "$backup_temp"
mv --no-clobber -- "$backup_temp" "$backup"
if [ -e "$backup_temp" ]; then
	printf 'dwm-titus: warning: preserving %s because migration backup appeared concurrently at %s\n' \
		"$hotkeys" "$backup" >&2
	exit 0
fi
backup_temp=

migration_temp=$(mktemp "$config_dir/.hotkeys.toml.XXXXXX")
cp --preserve=all -- "$hotkeys" "$migration_temp"
awk -v legacy="$legacy_binding" -v replacement="$replacement_binding" '
	$0 == legacy { print replacement; next }
	{ print }
' "$hotkeys" >"$migration_temp"
mv -f -- "$migration_temp" "$hotkeys"
migration_temp=

printf 'dwm-titus: migrated the stock ChatGPT hotkey; backup: %s\n' "$backup"
