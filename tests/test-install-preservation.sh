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

if grep -Eq 'sudo systemctl enable (NetworkManager|bluetooth)\.service' "$REPO_DIR/install.sh"; then
	printf 'Optional Arch services are enabled without the non-fatal guard.\n' >&2
	exit 1
fi
for service in NetworkManager.service bluetooth.service; do
	grep -Fq "enable_optional_service $service" "$REPO_DIR/install.sh"
done

cp -a "$REPO_DIR/." "$TEST_REPO/"
mkdir -p \
	"$XDG_CONFIG_HOME/dwm-titus" \
	"$XDG_CONFIG_HOME/picom" \
	"$XDG_CONFIG_HOME/quickshell" \
	"$XDG_CONFIG_HOME/systemd/user/default.target.wants" \
	"$XDG_DATA_HOME"

printf '%s\n' '/* local config marker */' >"$TEST_REPO/config.h"
printf '%s\n' '# existing xinitrc marker' >"$TEST_HOME/.xinitrc"
printf '%s\n' '# existing hotkeys marker' >"$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml"
printf '%s\n' '# existing themes marker' >"$XDG_CONFIG_HOME/dwm-titus/themes.toml"
printf '%s\n' '# existing rules marker' >"$XDG_CONFIG_HOME/dwm-titus/window-rules.toml"
printf '%s\n' '# existing picom marker' >"$XDG_CONFIG_HOME/picom/picom.conf"
printf '%s\n' '# unrelated user service marker' >"$XDG_CONFIG_HOME/systemd/user/custom.service"
cat >"$XDG_CONFIG_HOME/systemd/user/dwm-graphical-session.service" <<'EOF'
[Unit]
Description=DWM Graphical Session
BindsTo=graphical-session.target
Wants=graphical-session.target xdg-desktop-autostart.target
After=basic.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
[Install]
WantedBy=default.target
EOF
ln -s ../dwm-graphical-session.service \
	"$XDG_CONFIG_HOME/systemd/user/default.target.wants/dwm-graphical-session.service"
ln -s ../wm-graphical-session.service \
	"$XDG_CONFIG_HOME/systemd/user/default.target.wants/wm-graphical-session.service"
printf '%s\n' '// stale quickshell marker' >"$XDG_CONFIG_HOME/quickshell/shell.qml"
printf '%s\n' 'stale quickshell file' >"$XDG_CONFIG_HOME/quickshell/stale.txt"

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
snapshot_file "$XDG_CONFIG_HOME/picom/picom.conf" "$WORK_DIR/picom.before"
snapshot_file "$XDG_CONFIG_HOME/systemd/user/custom.service" "$WORK_DIR/custom-service.before"

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
assert_preserved picom "$XDG_CONFIG_HOME/picom/picom.conf" "$WORK_DIR/picom.before"
assert_preserved custom-service "$XDG_CONFIG_HOME/systemd/user/custom.service" "$WORK_DIR/custom-service.before"

if [ -e "$XDG_CONFIG_HOME/systemd/user/dwm-graphical-session.service" ] ||
	[ -e "$XDG_CONFIG_HOME/systemd/user/default.target.wants/dwm-graphical-session.service" ] ||
	[ -e "$XDG_CONFIG_HOME/systemd/user/default.target.wants/wm-graphical-session.service" ]; then
	printf 'Makefile install did not migrate legacy graphical-session startup.\n' >&2
	exit 1
fi

SESSION_UNIT="$XDG_CONFIG_HOME/systemd/user/wm-graphical-session.service"
if ! cmp -s "$TEST_REPO/config/systemd/user/wm-graphical-session.service" "$SESSION_UNIT"; then
	printf 'Install did not seed the static graphical-session unit.\n' >&2
	exit 1
fi
if grep -q '^WantedBy=default.target$' "$SESSION_UNIT"; then
	printf 'Installed graphical-session unit would start before DISPLAY import.\n' >&2
	exit 1
fi

if ! cmp -s "$TEST_REPO/config/quickshell/shell.qml" "$XDG_CONFIG_HOME/quickshell/shell.qml"; then
	printf 'Install did not refresh managed Quickshell config.\n' >&2
	exit 1
fi
if [ -e "$XDG_CONFIG_HOME/quickshell/stale.txt" ]; then
	printf 'Install did not replace managed Quickshell config directory.\n' >&2
	exit 1
fi

printf 'Repeated install preservation: PASS\n'
