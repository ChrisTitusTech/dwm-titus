#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

TEST_REPO="$WORK_DIR/repo"
TEST_HOME="$WORK_DIR/home"
XDG_CONFIG_HOME="$TEST_HOME/.config"
XDG_DATA_HOME="$TEST_HOME/.local/share"
XDG_CONFIG_DIRS="$WORK_DIR/etc-xdg"
OWNER="$(id -un)"
OWNER_GROUP="$(id -gn)"

if grep -Eq 'sudo systemctl enable (NetworkManager|bluetooth)\.service' "$REPO_DIR/install.sh"; then
	printf 'Optional Arch services are enabled without the non-fatal guard.\n' >&2
	exit 1
fi
for service in NetworkManager.service bluetooth.service; do
	grep -Fq "enable_optional_service $service" "$REPO_DIR/install.sh"
done
grep -Fq 'Start LightDM now (optional): sudo systemctl start lightdm.service' \
	"$REPO_DIR/install.sh"
grep -Fq "sudo make install-system \\" "$REPO_DIR/install.sh"
grep -Fq "make install-user \\" "$REPO_DIR/install.sh"
if grep -Fq "sudo make install \\" "$REPO_DIR/install.sh"; then
	printf 'Installer still runs the user installation stage as root.\n' >&2
	exit 1
fi
grep -Fq "runuser -u \"\$\$target_user\" -- env -u DBUS_SESSION_BUS_ADDRESS \\" \
	"$REPO_DIR/Makefile"
grep -Fq "HOME=\"\${USER_HOME}\" XDG_RUNTIME_DIR=\"/run/user/\$\$target_uid\" \\" \
	"$REPO_DIR/Makefile"
grep -Fq "\$(MAKE) install-user " "$REPO_DIR/Makefile"
grep -Fq 'dwm.desktop not found (run '\''./install.sh'\'')' \
	"$REPO_DIR/scripts/check-deps.sh"
grep -Fq 'Run: make && sudo make install-system && make install-user' \
	"$REPO_DIR/scripts/check-deps.sh"
if grep -Eq 'sudo make install($|[[:space:]&;])' "$REPO_DIR/scripts/check-deps.sh"; then
	printf 'Dependency check still recommends a root user-install stage.\n' >&2
	exit 1
fi
if grep -Eq 'sudo chown (-R|--recursive)' "$REPO_DIR/install.sh"; then
	printf 'Installer uses a broad recursive ownership repair.\n' >&2
	exit 1
fi

PROBE_OWNER=$(id -un)
if [[ $PROBE_OWNER == root ]] && getent passwd nobody >/dev/null 2>&1; then
	PROBE_OWNER=nobody
fi
PROBE_HOME=$(getent passwd "$PROBE_OWNER" | cut -d: -f6)
OWNER_HOME_MAKEFILE="$WORK_DIR/owner-home.mk"
{
	printf 'include %s/Makefile\n' "$REPO_DIR"
	cat <<'EOF'
print-owner-home:
	@printf '%s\n' "${USER_HOME}"
EOF
} >"$OWNER_HOME_MAKEFILE"
RESOLVED_OWNER_HOME=$(env -u SUDO_USER -u USER_HOME -u XDG_CONFIG_HOME \
	-u XDG_DATA_HOME USER=root make -s --no-print-directory -C "$REPO_DIR" \
	-f "$OWNER_HOME_MAKEFILE" \
	print-owner-home OWNER="$PROBE_OWNER")
if [[ $RESOLVED_OWNER_HOME != "$PROBE_HOME" ]]; then
	printf 'OWNER home resolution mismatch: expected %s, got %s.\n' \
		"$PROBE_HOME" "$RESOLVED_OWNER_HOME" >&2
	exit 1
fi
EXPLICIT_OWNER_HOME=$(env -u SUDO_USER -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
	USER=root make -s --no-print-directory -C "$REPO_DIR" -f "$OWNER_HOME_MAKEFILE" \
	print-owner-home OWNER="$PROBE_OWNER" USER_HOME="$WORK_DIR/explicit-home")
if [[ $EXPLICIT_OWNER_HOME != "$WORK_DIR/explicit-home" ]]; then
	printf 'Explicit USER_HOME override mismatch: expected %s, got %s.\n' \
		"$WORK_DIR/explicit-home" "$EXPLICIT_OWNER_HOME" >&2
	exit 1
fi

cp -a "$REPO_DIR/." "$TEST_REPO/"
mkdir -p \
	"$XDG_CONFIG_HOME/dwm-titus" \
	"$XDG_CONFIG_HOME/picom" \
	"$XDG_CONFIG_HOME/Thunar" \
	"$XDG_CONFIG_HOME/quickshell" \
	"$XDG_CONFIG_HOME/autostart" \
	"$XDG_CONFIG_HOME/systemd/user/default.target.wants" \
	"$XDG_CONFIG_DIRS/autostart" \
	"$XDG_DATA_HOME"

printf '%s\n' '/* local config marker */' >"$TEST_REPO/config.h"
printf '%s\n' '# existing xinitrc marker' >"$TEST_HOME/.xinitrc"
printf '%s\n' '# existing hotkeys marker' >"$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml"
printf '%s\n' '# existing themes marker' >"$XDG_CONFIG_HOME/dwm-titus/themes.toml"
printf '%s\n' '# existing rules marker' >"$XDG_CONFIG_HOME/dwm-titus/window-rules.toml"
printf '%s\n' '# existing picom marker' >"$XDG_CONFIG_HOME/picom/picom.conf"
printf '%s\n' '<!-- existing Thunar actions marker -->' >"$XDG_CONFIG_HOME/Thunar/uca.xml"
printf '%s\n' '# unrelated user service marker' >"$XDG_CONFIG_HOME/systemd/user/custom.service"
cat >"$XDG_CONFIG_HOME/autostart/picom.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Custom compositor
Exec=custom-picom
OnlyShowIn=XFCE;
EOF
cat >"$XDG_CONFIG_DIRS/autostart/light-locker.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Vendor screen locker
Exec=light-locker --lock-after-screensaver=5
OnlyShowIn=MATE;XFCE;
AutostartCondition=GSettings org.mate.lockdown disable-lock-screen
EOF
cat >"$XDG_CONFIG_DIRS/autostart/polkit-mate-authentication-agent-1.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Vendor PolicyKit agent
Exec=/usr/libexec/polkit-mate-authentication-agent-1
OnlyShowIn=MATE;
NotShowIn=GNOME;KDE;
X-MATE-Autostart-Phase=Initialization
EOF
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
snapshot_file "$XDG_CONFIG_HOME/Thunar/uca.xml" "$WORK_DIR/thunar-uca.before"
snapshot_file "$XDG_CONFIG_HOME/autostart/picom.desktop" "$WORK_DIR/picom-autostart.before"
snapshot_file "$XDG_CONFIG_HOME/systemd/user/custom.service" "$WORK_DIR/custom-service.before"

for _ in 1 2; do
	make -C "$TEST_REPO" install-user \
		USER_HOME="$TEST_HOME" \
		OWNER="$OWNER" \
		XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
		XDG_CONFIG_DIRS="$XDG_CONFIG_DIRS" \
		XDG_DATA_HOME="$XDG_DATA_HOME"
done

assert_preserved config-h "$TEST_REPO/config.h" "$WORK_DIR/config-h.before"
assert_preserved xinitrc "$TEST_HOME/.xinitrc" "$WORK_DIR/xinitrc.before"
assert_preserved hotkeys "$XDG_CONFIG_HOME/dwm-titus/hotkeys.toml" "$WORK_DIR/hotkeys.before"
assert_preserved themes "$XDG_CONFIG_HOME/dwm-titus/themes.toml" "$WORK_DIR/themes.before"
assert_preserved window-rules "$XDG_CONFIG_HOME/dwm-titus/window-rules.toml" "$WORK_DIR/window-rules.before"
assert_preserved picom "$XDG_CONFIG_HOME/picom/picom.conf" "$WORK_DIR/picom.before"
assert_preserved thunar-uca "$XDG_CONFIG_HOME/Thunar/uca.xml" \
	"$WORK_DIR/thunar-uca.before"
assert_preserved picom-autostart "$XDG_CONFIG_HOME/autostart/picom.desktop" \
	"$WORK_DIR/picom-autostart.before"
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

LOCKER_OVERRIDE="$XDG_CONFIG_HOME/autostart/light-locker.desktop"
grep -Fqx 'Exec=light-locker --lock-after-screensaver=5' "$LOCKER_OVERRIDE"
grep -Fqx 'OnlyShowIn=MATE;XFCE;' "$LOCKER_OVERRIDE"
grep -Fqx 'AutostartCondition=GSettings org.mate.lockdown disable-lock-screen' \
	"$LOCKER_OVERRIDE"
grep -Fqx 'NotShowIn=X-DWM;' "$LOCKER_OVERRIDE"

POLKIT_OVERRIDE="$XDG_CONFIG_HOME/autostart/polkit-mate-authentication-agent-1.desktop"
grep -Fqx 'Exec=/usr/libexec/polkit-mate-authentication-agent-1' "$POLKIT_OVERRIDE"
grep -Fqx 'OnlyShowIn=MATE;' "$POLKIT_OVERRIDE"
grep -Fqx 'X-MATE-Autostart-Phase=Initialization' "$POLKIT_OVERRIDE"
grep -Fqx 'NotShowIn=GNOME;KDE;X-DWM;' "$POLKIT_OVERRIDE"
test "$(grep -o 'X-DWM;' "$POLKIT_OVERRIDE" | wc -l)" -eq 1
test "$(stat -c %U "$LOCKER_OVERRIDE")" = "$OWNER"
test "$(stat -c %U "$POLKIT_OVERRIDE")" = "$OWNER"
test "$(stat -c %U "$XDG_CONFIG_HOME/autostart")" = "$OWNER"

FRESH_HOME="$WORK_DIR/fresh-home"
FRESH_CONFIG_HOME="$FRESH_HOME/.config"
FRESH_DATA_HOME="$FRESH_HOME/.local/share"
FRESH_CONFIG_DIRS="$WORK_DIR/fresh-etc-xdg"
mkdir -p "$FRESH_CONFIG_DIRS/autostart"
make -C "$TEST_REPO" install-user \
	USER_HOME="$FRESH_HOME" \
	OWNER="$OWNER" \
	XDG_CONFIG_HOME="$FRESH_CONFIG_HOME" \
	XDG_CONFIG_DIRS="$FRESH_CONFIG_DIRS" \
	XDG_DATA_HOME="$FRESH_DATA_HOME"
cmp "$TEST_REPO/config/Thunar/uca.xml" "$FRESH_CONFIG_HOME/Thunar/uca.xml"
grep -Fqx '    <command>alacritty --working-directory %f</command>' \
	"$FRESH_CONFIG_HOME/Thunar/uca.xml"
for user_path in \
	"$FRESH_HOME/.local" \
	"$FRESH_DATA_HOME" \
	"$FRESH_CONFIG_HOME" \
	"$FRESH_CONFIG_HOME/dwm-titus" \
	"$FRESH_DATA_HOME/dwm-titus"; do
	test "$(stat -c %U "$user_path")" = "$OWNER"
	test "$(stat -c %G "$user_path")" = "$OWNER_GROUP"
done

EMPTY_CONFIG_HOME="$WORK_DIR/empty-config"
EMPTY_CONFIG_DIRS="$WORK_DIR/empty-etc-xdg"
mkdir -p "$EMPTY_CONFIG_DIRS/autostart"
HOME="$TEST_HOME" XDG_CONFIG_HOME="$EMPTY_CONFIG_HOME" \
	XDG_CONFIG_DIRS="$EMPTY_CONFIG_DIRS" \
	DWM_INSTALL_OWNER="$OWNER" \
	"$TEST_REPO/scripts/seed-autostart-overrides.sh"
if find "$EMPTY_CONFIG_HOME/autostart" -type f -print -quit | grep -q .; then
	printf 'Autostart override created without a matching vendor entry.\n' >&2
	exit 1
fi
test "$(stat -c %U "$EMPTY_CONFIG_HOME/autostart")" = "$OWNER"

printf 'Repeated install preservation: PASS\n'
