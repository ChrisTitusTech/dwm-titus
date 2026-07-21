#!/bin/sh

set -eu

repo_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
helper="$repo_dir/scripts/dwm-lock"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/bin"

cat >"$work/bin/id" <<'SCRIPT'
#!/bin/sh
printf '%s\n' 1000
SCRIPT

cat >"$work/bin/pgrep" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT

cat >"$work/bin/light-locker" <<'SCRIPT'
#!/bin/sh
printf '%s\n' started >"${DWM_LOCK_TEST_DIR:?}/light-locker"
: >"${DWM_LOCK_TEST_DIR:?}/light-locker.running"
trap '/bin/rm -f "${DWM_LOCK_TEST_DIR:?}/light-locker.running"; exit 0' TERM
while :; do
	:
done
SCRIPT

cat >"$work/bin/light-locker-command" <<'SCRIPT'
#!/bin/sh
case $* in
	--lock)
		printf '%s\n' "$*" >"${DWM_LOCK_TEST_DIR:?}/light-locker-command"
		[ "${DWM_LOCK_TEST_FAIL:-0}" != 1 ]
		;;
--query)
	if [ -f "${DWM_LOCK_TEST_DIR:?}/light-locker.queried" ]; then
		printf '%s\n' 'The screensaver is inactive'
	else
		: >"${DWM_LOCK_TEST_DIR:?}/light-locker.queried"
		printf '%s\n' 'The screensaver is active'
	fi
	;;
esac
SCRIPT

cat >"$work/bin/sleep" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT

chmod +x "$work/bin/"*

DWM_LOCK_TEST_DIR="$work" \
	DWM_LOCK_START_DELAY=0 \
	PATH="$work/bin" \
	"$helper"
grep -Fxq started "$work/light-locker"
grep -Fxq -- "--lock" "$work/light-locker-command"
i=0
while [ -e "$work/light-locker.running" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	/bin/sleep 0.01
done
test ! -e "$work/light-locker.running"
grep -Fq '"command": Commands.lockHelperCommand()' \
	"$repo_dir/config/quickshell/power/PowerMenuModel.qml"
grep -Fq 'return helperCommand("dwm-lock", undefined, [], true)' \
	"$repo_dir/config/quickshell/core/Commands.qml"

cat >"$work/bin/loginctl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >"${DWM_LOCK_TEST_DIR:?}/loginctl"
SCRIPT
chmod +x "$work/bin/loginctl"

DWM_LOCK_TEST_DIR="$work" \
	DWM_LOCK_START_DELAY=0 \
	DWM_LOCK_TEST_FAIL=1 \
	XDG_SESSION_ID=8 \
	PATH="$work/bin" \
	"$helper"
grep -Fxq 'lock-session 8' "$work/loginctl"
test ! -e "$work/light-locker.running"

rm -f "$work/bin/loginctl" "$work/loginctl" "$work/light-locker-command"

rm -f "$work/bin/light-locker" "$work/bin/light-locker-command" \
	"$work/light-locker" "$work/light-locker-command"

cat >"$work/bin/loginctl" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >"${DWM_LOCK_TEST_DIR:?}/loginctl"
SCRIPT
chmod +x "$work/bin/loginctl"

DWM_LOCK_TEST_DIR="$work" \
	XDG_SESSION_ID=7 \
	PATH="$work/bin" \
	"$helper"
grep -Fxq "lock-session 7" "$work/loginctl"

rm -f "$work/bin/loginctl" "$work/loginctl"

if DWM_LOCK_TEST_DIR="$work" PATH="$work/bin" "$helper" 2>"$work/err"; then
	echo "dwm-lock succeeded without a locker" >&2
	exit 1
fi
grep -Fq "no usable screen locker found" "$work/err"

cat >"$work/bin/busctl" <<'SCRIPT'
#!/bin/sh
printf 'address=%s\nargs=%s\n' \
	"${DBUS_SYSTEM_BUS_ADDRESS:-}" "$*" >"${DWM_LOCK_TEST_DIR:?}/busctl"
printf '%s\n' '{"type":"o","data":["/org/freedesktop/login1/session/_37"]}'
SCRIPT

cat >"$work/bin/loginctl" <<'SCRIPT'
#!/bin/sh
case $* in
"show-session self -p Id --value") printf '%s\n' 7 ;;
*) exit 1 ;;
esac
SCRIPT

cat >"$work/bin/dbus-monitor" <<'SCRIPT'
#!/bin/sh
printf 'address=%s\nargs=%s\n' \
	"${DBUS_SYSTEM_BUS_ADDRESS:-}" "$*" >"${DWM_LOCK_TEST_DIR:?}/dbus-monitor"
printf '%s\n' 'signal path=/org/freedesktop/login1/session/_37; interface=org.freedesktop.login1.Session; member=Lock'
SCRIPT

cat >"$work/bin/dwm-lock" <<'SCRIPT'
#!/bin/sh
printf 'no_loginctl=%s\n' "${DWM_LOCK_NO_LOGINCTL:-0}" >"${DWM_LOCK_TEST_DIR:?}/watch-lock"
SCRIPT
chmod +x "$work/bin/busctl" "$work/bin/dbus-monitor" "$work/bin/dwm-lock" "$work/bin/loginctl"

DWM_LOCK_TEST_DIR="$work" \
	DWM_LOCK_HELPER="$work/bin/dwm-lock" \
	DWM_LOCK_WATCH_SYNC=1 \
	XDG_SESSION_ID='' \
	PATH="$work/bin:/usr/bin:/bin" \
	"$repo_dir/scripts/dwm-lock-watch"
grep -Fxq 'address=unix:path=/run/dbus/system_bus_socket' "$work/busctl"
grep -Fq 'args=--system --json=short call org.freedesktop.login1' "$work/busctl"
grep -Fq 'GetSession s 7' "$work/busctl"
grep -Fxq 'address=unix:path=/run/dbus/system_bus_socket' "$work/dbus-monitor"
grep -Fq "path='/org/freedesktop/login1/session/_37'" "$work/dbus-monitor"
grep -Fxq 'no_loginctl=1' "$work/watch-lock"

printf '%s\n' "dwm-lock fallback behavior: PASS"
