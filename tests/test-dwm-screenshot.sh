#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home/.config/flameshot" "$work/home/Pictures"

cat >"$work/home/.config/flameshot/flameshot.ini" <<'EOF'
[General]
showHelp=false
useX11LegacyScreenshot=false

[Shortcuts]
TYPE_COPY=Ctrl+C
EOF

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

printf '%s\n' "Flameshot X11 backend, environment, and clipboard command: PASS"
