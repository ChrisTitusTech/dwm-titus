#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home/.config/flameshot" "$work/home/Pictures"

cat >"$work/home/flameshot-target.ini" <<'EOF'
[General]
showHelp=false

[Shortcuts]
TYPE_COPY=Ctrl+C
EOF
chmod 640 "$work/home/flameshot-target.ini"
ln -s "$work/home/flameshot-target.ini" \
	"$work/home/.config/flameshot/flameshot.ini"
config_inode=$(stat -Lc %i "$work/home/flameshot-target.ini")
config_mode=$(stat -Lc %a "$work/home/flameshot-target.ini")

cat >"$work/bin/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/dbus-update-activation-environment" <<'EOF'
#!/bin/sh
printf 'dbus:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/flameshot" <<'EOF'
#!/bin/sh
printf 'flameshot:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$work/bin/xdg-user-dir" <<EOF
#!/bin/sh
printf '%s\n' '$work/home/Pictures'
EOF

chmod +x "$work/bin/"*

log=$work/calls.log
env -u XDG_CURRENT_DESKTOP -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XAUTHORITY="$work/Xauthority" \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/home/.config" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" clip

grep -Fqx 'systemctl:--user unset-environment WAYLAND_DISPLAY' "$log"
grep -Fqx 'systemctl:--user import-environment DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'dbus:WAYLAND_DISPLAY=' "$log"
grep -Fqx 'dbus:--systemd DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'flameshot:gui --clipboard' "$log"
grep -Fqx 'useX11LegacyScreenshot=true' \
	"$work/home/.config/flameshot/flameshot.ini"
grep -Fqx 'showHelp=false' "$work/home/.config/flameshot/flameshot.ini"
grep -Fqx 'TYPE_COPY=Ctrl+C' "$work/home/.config/flameshot/flameshot.ini"
test -L "$work/home/.config/flameshot/flameshot.ini"
test "$(stat -Lc %i "$work/home/flameshot-target.ini")" = "$config_inode"
test "$(stat -Lc %a "$work/home/flameshot-target.ini")" = "$config_mode"
test -d "$work/home/Pictures/Screenshots"

: >"$log"
env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/home/.config" \
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup
if grep -q '^flameshot:' "$log"; then
	printf '%s\n' "Flameshot setup must not start a capture" >&2
	exit 1
fi

mkdir -p "$work/explicit/.config/flameshot"
cat >"$work/explicit/.config/flameshot/flameshot.ini" <<'EOF'
[General]
useX11LegacyScreenshot=false
EOF
env -u WAYLAND_DISPLAY \
	DISPLAY=:99 \
	XDG_SESSION_TYPE=x11 \
	XDG_CONFIG_HOME="$work/explicit/.config" \
	HOME="$work/explicit" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" setup
grep -Fqx 'useX11LegacyScreenshot=false' \
	"$work/explicit/.config/flameshot/flameshot.ini"
if grep -Fqx 'useX11LegacyScreenshot=true' \
	"$work/explicit/.config/flameshot/flameshot.ini"; then
	printf '%s\n' "Flameshot setup must preserve an explicit backend preference" >&2
	exit 1
fi

theme_bin=$work/theme-bin
theme_home=$work/theme-home
mkdir -p "$theme_bin" "$theme_home/.config/dwm-titus"
cp "$repo_dir/config/themes.toml" \
	"$theme_home/.config/dwm-titus/themes.toml"

cat >"$theme_bin/pgrep" <<'EOF'
#!/bin/sh
test "$1" = "-x" && test "$2" = "flameshot"
EOF

cat >"$theme_bin/pkill" <<'EOF'
#!/bin/sh
printf 'pkill:%s\n' "$*" >>"${TEST_LOG:?}"
EOF

cat >"$theme_bin/dwm-screenshot" <<'EOF'
#!/bin/sh
printf 'dwm-screenshot:%s\n' "$*" >>"${TEST_LOG:?}"
test "${TEST_SETUP_FAIL:-0}" != "1"
EOF

cat >"$theme_bin/flameshot" <<'EOF'
#!/bin/sh
printf 'flameshot-env:%s:%s:%s:%s\n' \
	"${WAYLAND_DISPLAY-unset}" \
	"${XDG_SESSION_TYPE-unset}" \
	"${QT_QPA_PLATFORM-unset}" \
	"${QT_QPA_PLATFORMTHEME-unset}" >>"${TEST_LOG:?}"
EOF

for command_name in dbus-update-activation-environment gsettings qt6ct \
	sleep systemctl xfconf-query xrdb; do
	cat >"$theme_bin/$command_name" <<'EOF'
#!/bin/sh
:
EOF
done
chmod +x "$theme_bin/"*

: >"$log"
DISPLAY=:99 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$theme_home/.config" \
	HOME="$theme_home" \
	PATH="$theme_bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/theme-apply.sh"

grep -Fqx 'dwm-screenshot:setup' "$log"
grep -Fqx 'pkill:-x flameshot' "$log"
grep -Fqx 'flameshot-env:unset:x11:xcb:qt6ct' "$log"

: >"$log"
DISPLAY=:99 \
	WAYLAND_DISPLAY=wayland-0 \
	XDG_SESSION_TYPE=wayland \
	QT_QPA_PLATFORM=wayland \
	XDG_CONFIG_HOME="$theme_home/.config" \
	HOME="$theme_home" \
	PATH="$theme_bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	TEST_SETUP_FAIL=1 \
	"$repo_dir/scripts/theme-apply.sh" 2>/dev/null

grep -Fqx 'dwm-screenshot:setup' "$log"
if grep -Eq '^(pkill|flameshot-env):' "$log"; then
	printf '%s\n' "Theme reload must keep Flameshot running when X11 setup fails" >&2
	exit 1
fi

printf '%s\n' "Flameshot X11 backend, environment, and clipboard command: PASS"
