#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

# These TOML fixtures intentionally contain the literal variable name "$webapp".
# shellcheck disable=SC2016
legacy_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["$webapp", "https://chatgpt.com"] },'
replacement_binding='  { mod="SUPER",            key="a",       desc="ChatGPT",                 func="spawn",       exec=["dwm-quickshell-launcher", "launch-chatgpt"] },'
migration="$repo_dir/scripts/migrate-chatgpt-hotkey.sh"
config_home="$work/config"
hotkeys="$config_home/dwm-titus/hotkeys.toml"

mkdir -p "${hotkeys%/*}"

# Missing configuration is a successful no-op.
XDG_CONFIG_HOME="$work/missing" HOME="$work/home" "$migration"

{
	printf '%s\n' '# retain custom header'
	printf '%s\n' "$legacy_binding"
	printf '%s\n' '# retain custom footer'
} >"$hotkeys"
chmod 640 "$hotkeys"

XDG_CONFIG_HOME="$config_home" HOME="$work/home" "$migration"
grep -Fqx "$replacement_binding" "$hotkeys"
if grep -Fqx "$legacy_binding" "$hotkeys"; then
	printf 'Legacy ChatGPT binding remained after migration.\n' >&2
	exit 1
fi
grep -Fqx '# retain custom header' "$hotkeys"
grep -Fqx '# retain custom footer' "$hotkeys"
test "$(stat -c %a "$hotkeys")" = 640

# Repeated migration is idempotent.
before=$(sha256sum "$hotkeys")
XDG_CONFIG_HOME="$config_home" HOME="$work/home" "$migration"
test "$(sha256sum "$hotkeys")" = "$before"

# Customized bindings are never rewritten.
# shellcheck disable=SC2016
custom_binding='  { mod="SUPER", key="a", desc="My assistant", func="spawn", exec=["$webapp", "https://chatgpt.com"] },'
printf '%s\n' "$custom_binding" >"$hotkeys"
before=$(sha256sum "$hotkeys")
XDG_CONFIG_HOME="$config_home" HOME="$work/home" "$migration"
test "$(sha256sum "$hotkeys")" = "$before"

# Ambiguous duplicate stock bindings are preserved for manual resolution.
{
	printf '%s\n' "$legacy_binding"
	printf '%s\n' "$legacy_binding"
} >"$hotkeys"
before=$(sha256sum "$hotkeys")
XDG_CONFIG_HOME="$config_home" HOME="$work/home" "$migration" \
	2>"$work/duplicate.err"
test "$(sha256sum "$hotkeys")" = "$before"
grep -Fq 'legacy ChatGPT binding appears more than once' "$work/duplicate.err"

# Symlinked user configuration remains untouched.
printf '%s\n' "$legacy_binding" >"$work/symlink-target.toml"
rm -f "$hotkeys"
ln -s "$work/symlink-target.toml" "$hotkeys"
XDG_CONFIG_HOME="$config_home" HOME="$work/home" "$migration" \
	2>"$work/symlink.err"
test -L "$hotkeys"
grep -Fqx "$legacy_binding" "$work/symlink-target.toml"
grep -Fq 'preserving non-regular hotkeys file' "$work/symlink.err"

install_recipe=$(sed -n '/^install-user:/,/^uninstall:/p' "$repo_dir/Makefile")
printf '%s\n' "$install_recipe" |
	grep -Fq 'scripts/migrate-chatgpt-hotkey.sh'

printf 'ChatGPT hotkey migration: PASS\n'
