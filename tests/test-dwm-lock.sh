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
SCRIPT

cat >"$work/bin/light-locker-command" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" >"${DWM_LOCK_TEST_DIR:?}/light-locker-command"
SCRIPT

chmod +x "$work/bin/"*

DWM_LOCK_TEST_DIR="$work" \
	DWM_LOCK_START_DELAY=0 \
	PATH="$work/bin" \
	"$helper"
grep -Fxq started "$work/light-locker"
grep -Fxq -- "--lock" "$work/light-locker-command"

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

printf '%s\n' "dwm-lock fallback behavior: PASS"
