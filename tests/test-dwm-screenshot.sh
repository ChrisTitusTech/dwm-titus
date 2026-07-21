#!/bin/sh
set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/bin" "$work/home/Pictures"

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
	HOME="$work/home" \
	PATH="$work/bin:/usr/bin:/bin" \
	TEST_LOG="$log" \
	"$repo_dir/scripts/dwm-screenshot" clip

grep -Fqx 'systemctl:--user unset-environment WAYLAND_DISPLAY' "$log"
grep -Fqx 'systemctl:--user import-environment DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'dbus:--systemd DISPLAY XDG_SESSION_TYPE QT_QPA_PLATFORM XAUTHORITY' "$log"
grep -Fqx 'flameshot:gui --clipboard' "$log"
test -d "$work/home/Pictures/Screenshots"

printf '%s\n' "Flameshot environment and clipboard command: PASS"
