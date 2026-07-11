#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
test_uid=$(id -u)

mkdir -p "$work/bin" "$work/config/dwm-titus" "$work/home/Pictures/backgrounds" "$work/data/dwm-titus/config/quickshell" "$work/power-state"
mkdir -p "$work/config/quickshell"
cp "$repo/config/themes.toml" "$work/config/dwm-titus/themes.toml"
cp "$repo/config/hotkeys.toml" "$work/config/dwm-titus/hotkeys.toml"
: >"$work/data/dwm-titus/config/quickshell/shell.qml"
: >"$work/config/quickshell/shell.qml"
: >"$work/home/Pictures/backgrounds/wallpaper.png"

stub_command() {
	name=$1
	cat >"$work/bin/$name" <<'SH'
#!/bin/sh
printf '%s %s\n' "$(basename "$0")" "$*" >>"$DWM_TEST_LOG"
SH
	chmod +x "$work/bin/$name"
}

for name in quickshell xprop dwm-quickshell-launcher dwm-quickshell-controlcenter dex picom feh flameshot notify-send pactl brightnessctl xset gsettings light-locker setsid dwm-terminal dwm-default-apps xdg-open nwg-look pkill pgrep dnf; do
	stub_command "$name"
done

cat >"$work/bin/pkill" <<'SH'
#!/bin/sh
printf 'pkill %s\n' "$*" >>"${DWM_TEST_LOG:?}"
case $* in
*"-x light-locker"*) rm -f "${DWM_TEST_POWER_STATE:?}/light-locker.running" ;;
esac
SH
chmod +x "$work/bin/pkill"

cat >"$work/bin/pgrep" <<'SH'
#!/bin/sh
case "$*" in
"-x picom")
	exit "${DWM_TEST_PICOM_RUNNING:-1}"
	;;
*"-x light-locker"*)
	test -f "${DWM_TEST_POWER_STATE:?}/light-locker.running"
	;;
*)
	exit 1
	;;
esac
SH
chmod +x "$work/bin/pgrep"

cat >"$work/bin/xset" <<'SH'
#!/bin/sh
state=${DWM_TEST_POWER_STATE:?}
log=${DWM_TEST_LOG:?}
mkdir -p "$state"

read_state() {
	name=$1
	default=$2
	if [ -f "$state/$name" ]; then
		cat "$state/$name"
	else
		printf '%s\n' "$default"
	fi
}

case ${1:-} in
q)
	dpms_enabled=$(read_state dpms_enabled 0)
	dpms_timeout=$(read_state dpms_timeout 600)
	saver_timeout=$(read_state saver_timeout 0)
	if [ "$dpms_enabled" = 1 ]; then
		dpms_text=Enabled
	else
		dpms_text=Disabled
	fi
	cat <<EOF
Screen Saver:
  prefer blanking:  no    allow exposures:  yes
  timeout:  $saver_timeout    cycle:  600
DPMS (Display Power Management Signaling):
  Standby: $dpms_timeout    Suspend: $dpms_timeout    Off: $dpms_timeout
  DPMS is $dpms_text
EOF
	;;
+dpms)
	printf '1\n' >"$state/dpms_enabled"
	printf 'xset %s\n' "$*" >>"$log"
	;;
-dpms)
	printf '0\n' >"$state/dpms_enabled"
	printf 'xset %s\n' "$*" >>"$log"
	;;
dpms)
	printf '%s\n' "${4:-600}" >"$state/dpms_timeout"
	printf 'xset %s\n' "$*" >>"$log"
	;;
s)
	case ${2:-} in
	off) printf '0\n' >"$state/saver_timeout" ;;
	noblank) : ;;
	*[!0-9]* | "") : ;;
	*) printf '%s\n' "$2" >"$state/saver_timeout" ;;
	esac
	printf 'xset %s\n' "$*" >>"$log"
	;;
*)
	printf 'xset %s\n' "$*" >>"$log"
	;;
esac
SH
chmod +x "$work/bin/xset"

cat >"$work/bin/gsettings" <<'SH'
#!/bin/sh
state=${DWM_TEST_POWER_STATE:?}
log=${DWM_TEST_LOG:?}
mkdir -p "$state"

case ${1:-} in
get)
	case ${2:-}:${3:-} in
	apps.light-locker:lock-after-screensaver)
		if [ -f "$state/lock_after" ]; then
			printf 'uint32 %s\n' "$(cat "$state/lock_after")"
		else
			printf 'uint32 0\n'
		fi
		;;
	apps.light-locker:lock-on-suspend)
		if [ -f "$state/lock_on_suspend" ]; then
			cat "$state/lock_on_suspend"
		else
			printf 'true\n'
		fi
		;;
	*) exit 1 ;;
	esac
	;;
set)
	printf 'gsettings %s\n' "$*" >>"$log"
	case ${2:-}:${3:-} in
	apps.light-locker:lock-after-screensaver)
		printf '%s\n' "${4:-0}" >"$state/lock_after"
		;;
	apps.light-locker:lock-on-suspend)
		printf '%s\n' "${4:-false}" >"$state/lock_on_suspend"
		;;
	*) exit 1 ;;
	esac
	;;
*)
	printf 'gsettings %s\n' "$*" >>"$log"
	;;
esac
SH
chmod +x "$work/bin/gsettings"

cat >"$work/bin/light-locker" <<'SH'
#!/bin/sh
printf 'light-locker %s\n' "$*" >>"${DWM_TEST_LOG:?}"
: >"${DWM_TEST_POWER_STATE:?}/light-locker.running"
SH
chmod +x "$work/bin/light-locker"

cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
case "$*" in
info)
	printf 'Server Name: PipeWire\n'
	;;
*)
	printf 'pactl %s\n' "$*" >>"$DWM_TEST_LOG"
	;;
esac
SH
chmod +x "$work/bin/pactl"

run_helper() {
	DWM_TEST_LOG="$work/actions.log" \
		DWM_TEST_SYNC=1 \
		HOME="$work/home" \
		XDG_CONFIG_HOME="$work/config" \
		XDG_DATA_HOME="$work/data" \
		DWM_TEST_POWER_STATE="$work/power-state" \
		DWM_HEALTH_COMMAND_TIMEOUT=2 \
		PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/dwm-quickshell-controlcenter" "$@"
}

health=$(run_helper health)
printf '%s\n' "$health" | grep -Fqx 'ok	Quickshell	Available'
printf '%s\n' "$health" | grep -Fqx 'ok	xset	xset is available'
printf '%s\n' "$health" | grep -Fqx 'ok	light-locker	light-locker is available'
printf '%s\n' "$health" | grep -Fqx 'ok	Themes configuration	Readable'
printf '%s\n' "$health" | grep -Fqx 'ok	Quickshell configuration	Readable'

info=$(run_helper info)
printf '%s\n' "$info" | grep -Fqx 'Theme	nord'
printf '%s\n' "$info" | grep -Fqx 'Audio	PipeWire'

themes=$(run_helper themes)
printf '%s\n' "$themes" | grep -Fqx 'active	nord'
printf '%s\n' "$themes" | grep -Fqx 'available	dracula'

run_helper theme-set dracula >"$work/theme-set.out"
grep -Fqx 'theme	dracula' "$work/theme-set.out"
grep -Fq 'theme = "dracula"' "$work/config/dwm-titus/themes.toml"

if run_helper theme-set missing-theme 2>"$work/theme-set.err"; then
	exit 1
fi
grep -Fqx 'unknown theme: missing-theme' "$work/theme-set.err"

keybinds=$(run_helper keybinds)
printf '%s\n' "$keybinds" | grep -Fqx 'Super + r	App launcher'
printf '%s\n' "$keybinds" | grep -Fqx 'Super + F1	Control center'

power=$(run_helper power-status)
printf '%s\n' "$power" | grep -Fqx 'dpms_available	1'
printf '%s\n' "$power" | grep -Fqx 'dpms_enabled	0'
printf '%s\n' "$power" | grep -Fqx 'lock_available	1'
printf '%s\n' "$power" | grep -Fqx 'lock_enabled	0'

: >"$work/actions.log"
run_helper power-dpms-timeout 900 >"$work/power-dpms-timeout.out"
grep -Fqx 'power-dpms-timeout	900' "$work/power-dpms-timeout.out"
grep -Fq 'dpms_enabled=1' "$work/config/dwm-titus/power.conf"
grep -Fq 'dpms_timeout=900' "$work/config/dwm-titus/power.conf"
grep -Fqx 'xset +dpms' "$work/actions.log"
grep -Fqx 'xset dpms 900 900 900' "$work/actions.log"
power=$(run_helper power-status)
printf '%s\n' "$power" | grep -Fqx 'dpms_enabled	1'
printf '%s\n' "$power" | grep -Fqx 'dpms_timeout	900'

: >"$work/actions.log"
run_helper power-lock-timeout 300 >"$work/power-lock-timeout.out"
grep -Fqx 'power-lock-timeout	300' "$work/power-lock-timeout.out"
grep -Fq 'lock_enabled=1' "$work/config/dwm-titus/power.conf"
grep -Fq 'lock_timeout=300' "$work/config/dwm-titus/power.conf"
grep -Fqx 'xset s 300' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-after-screensaver 5' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-on-suspend true' "$work/actions.log"
grep -Fqx 'light-locker ' "$work/actions.log"
power=$(run_helper power-status)
printf '%s\n' "$power" | grep -Fqx 'lock_enabled	1'
printf '%s\n' "$power" | grep -Fqx 'lock_timeout	300'
printf '%s\n' "$power" | grep -Fqx 'lock_running	1'

: >"$work/actions.log"
run_helper power-lock off >"$work/power-lock-off.out"
grep -Fqx 'power-lock	0' "$work/power-lock-off.out"
grep -Fq 'lock_enabled=0' "$work/config/dwm-titus/power.conf"
grep -Fqx 'xset s off' "$work/actions.log"
grep -Fqx 'xset s noblank' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-after-screensaver 0' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-on-suspend false' "$work/actions.log"
grep -Fqx "pkill -u $test_uid -x light-locker" "$work/actions.log"
test ! -e "$work/power-state/light-locker.running"

# Persisted settings remain authoritative when X11 or light-locker state drifts.
printf '0\n' >"$work/power-state/dpms_enabled"
printf '60\n' >"$work/power-state/dpms_timeout"
printf '600\n' >"$work/power-state/saver_timeout"
printf '5\n' >"$work/power-state/lock_after"
printf 'true\n' >"$work/power-state/lock_on_suspend"
: >"$work/power-state/light-locker.running"
: >"$work/actions.log"
run_helper power-apply
grep -Fqx 'xset +dpms' "$work/actions.log"
grep -Fqx 'xset dpms 900 900 900' "$work/actions.log"
grep -Fqx 'xset s off' "$work/actions.log"
grep -Fqx 'xset s noblank' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-after-screensaver 0' "$work/actions.log"
grep -Fqx 'gsettings set apps.light-locker lock-on-suspend false' "$work/actions.log"
grep -Fqx 'false' "$work/power-state/lock_on_suspend"
grep -Fqx "pkill -u $test_uid -x light-locker" "$work/actions.log"
test ! -e "$work/power-state/light-locker.running"

: >"$work/actions.log"
run_helper action restart-quickshell >"$work/quickshell.out"
grep -Fqx 'action	restart-quickshell' "$work/quickshell.out"
grep -Fq 'pkill -x quickshell' "$work/actions.log"
grep -Fq 'quickshell --no-duplicate' "$work/actions.log"

: >"$work/actions.log"
run_helper action restart-picom >"$work/picom.out"
grep -Fqx 'action	restart-picom' "$work/picom.out"
grep -Fq 'pkill -x picom' "$work/actions.log"
grep -Fqx 'picom ' "$work/actions.log"

: >"$work/actions.log"
run_helper action open-wallpapers >"$work/wallpapers.out"
grep -Fqx 'action	open-wallpapers' "$work/wallpapers.out"
grep -Fq "xdg-open $work/home/Pictures/backgrounds" "$work/actions.log"

: >"$work/actions.log"
run_helper action reload-wallpaper >"$work/reload-wallpaper.out"
grep -Fqx 'action	reload-wallpaper' "$work/reload-wallpaper.out"
grep -Fq "feh --randomize --bg-fill $work/home/Pictures/backgrounds/wallpaper.png" "$work/actions.log"

rm -f "$work/home/Pictures/backgrounds/wallpaper.png"
if run_helper action reload-wallpaper 2>"$work/reload-wallpaper.err"; then
	exit 1
fi
grep -Fqx "no loadable wallpaper images found in $work/home/Pictures/backgrounds" "$work/reload-wallpaper.err"

if run_helper action not-real 2>"$work/action.err"; then
	exit 1
fi
grep -Fqx 'unknown action: not-real' "$work/action.err"

printf 'Quickshell control center helper: PASS\n'
