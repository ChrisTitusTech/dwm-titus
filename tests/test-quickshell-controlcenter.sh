#!/bin/sh
set -eu

repo=$(
	unset CDPATH
	cd -- "$(dirname -- "$0")/.." && pwd
)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin" "$work/config/dwm-titus" "$work/home/Pictures/backgrounds" "$work/data/dwm-titus/config/quickshell"
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

for name in quickshell xprop dwm-quickshell-launcher dwm-quickshell-controlcenter dex picom feh flameshot notify-send pactl brightnessctl setsid dwm-terminal dwm-default-apps xdg-open nwg-look pkill pgrep; do
	stub_command "$name"
done

cat >"$work/bin/pgrep" <<'SH'
#!/bin/sh
case "$*" in
"-x picom")
	exit "${DWM_TEST_PICOM_RUNNING:-1}"
	;;
*)
	exit 1
	;;
esac
SH
chmod +x "$work/bin/pgrep"

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
		PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/dwm-quickshell-controlcenter" "$@"
}

health=$(run_helper health)
printf '%s\n' "$health" | grep -Fqx 'ok	Quickshell	quickshell found'
printf '%s\n' "$health" | grep -Fqx 'ok	Control helper	dwm-quickshell-controlcenter found'
printf '%s\n' "$health" | grep -Fqx "ok	Themes config	$work/config/dwm-titus/themes.toml"

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

if run_helper action not-real 2>"$work/action.err"; then
	exit 1
fi
grep -Fqx 'unknown action: not-real' "$work/action.err"

printf 'Quickshell control center helper: PASS\n'
