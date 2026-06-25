#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TEST_REPO="$WORK_DIR/repo"
TEST_HOME="$WORK_DIR/home"
XDG_CONFIG_HOME="$TEST_HOME/.config"
XDG_DATA_HOME="$TEST_HOME/.local/share"
OWNER="$(id -un)"

cp -a "$REPO_DIR/." "$TEST_REPO/"
mkdir -p \
	"$XDG_CONFIG_HOME/dwm-titus" \
	"$XDG_CONFIG_HOME/polybar" \
	"$XDG_CONFIG_HOME/picom" \
	"$XDG_DATA_HOME"

printf '%s\n' '/* local config marker */' >"$TEST_REPO/config.h"
printf '%s\n' '# existing xinitrc marker' >"$TEST_HOME/.xinitrc"
printf '%s\n' '# existing hotkeys marker' >"$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml"
printf '%s\n' '# existing themes marker' >"$XDG_CONFIG_HOME/dwm-titus/themes.toml"
printf '%s\n' '# existing rules marker' >"$XDG_CONFIG_HOME/dwm-titus/window-rules.toml"
printf '%s\n' '# existing polybar marker' >"$XDG_CONFIG_HOME/polybar/config.ini"
printf '%s\n' '# existing picom marker' >"$XDG_CONFIG_HOME/picom/picom.conf"

snapshot_file() {
	local path=$1
	local output=$2

	sha256sum "$path" | awk '{ print $1 }' >"$output"
}

assert_preserved() {
	local label=$1
	local path=$2
	local expected=$3
	local actual="$WORK_DIR/$label.after"

	snapshot_file "$path" "$actual"
	if ! cmp -s "$expected" "$actual"; then
		printf 'Install did not preserve %s: %s\n' "$label" "$path" >&2
		exit 1
	fi
}

snapshot_file "$TEST_REPO/config.h" "$WORK_DIR/config-h.before"
snapshot_file "$TEST_HOME/.xinitrc" "$WORK_DIR/xinitrc.before"
snapshot_file "$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml" "$WORK_DIR/hotkeys.before"
snapshot_file "$XDG_CONFIG_HOME/dwm-titus/themes.toml" "$WORK_DIR/themes.before"
snapshot_file "$XDG_CONFIG_HOME/dwm-titus/window-rules.toml" "$WORK_DIR/window-rules.before"
snapshot_file "$XDG_CONFIG_HOME/polybar/config.ini" "$WORK_DIR/polybar.before"
snapshot_file "$XDG_CONFIG_HOME/picom/picom.conf" "$WORK_DIR/picom.before"

for _ in 1 2; do
	make -C "$TEST_REPO" install-user \
		USER_HOME="$TEST_HOME" \
		OWNER="$OWNER" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		XDG_DATA_HOME="$XDG_DATA_HOME"
done

assert_preserved config-h "$TEST_REPO/config.h" "$WORK_DIR/config-h.before"
assert_preserved xinitrc "$TEST_HOME/.xinitrc" "$WORK_DIR/xinitrc.before"
assert_preserved hotkeys "$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml" "$WORK_DIR/hotkeys.before"
assert_preserved themes "$XDG_CONFIG_HOME/dwm-titus/themes.toml" "$WORK_DIR/themes.before"
assert_preserved window-rules "$XDG_CONFIG_HOME/dwm-titus/window-rules.toml" "$WORK_DIR/window-rules.before"
assert_preserved polybar "$XDG_CONFIG_HOME/polybar/config.ini" "$WORK_DIR/polybar.before"
assert_preserved picom "$XDG_CONFIG_HOME/picom/picom.conf" "$WORK_DIR/picom.before"

printf 'Repeated install preservation: PASS\n'
