#!/usr/bin/env bash

## Author : Aditya Shakya (adi1090x)
## Github : @adi1090x

# CMDs
uptime="`uptime -p | sed -e 's/up //g'`"

# ── Resolution helpers ───────────────────────────────────
# Returns the pixel height of the currently active mode on the
# primary (or first connected) display.
_screen_height() {
    if command -v xrandr &>/dev/null; then
        xrandr --query | awk '/\*/ { split($1,a,"x"); print a[2]; exit }'
        return
    fi
    echo "1080"
}

# Emits a rofi -theme-str override that scales all sizes proportionally
# to the current screen height. 1080 is the baseline (matches the .rasi defaults).
_scale_theme() {
    local h
    h="$(_screen_height)"
    [ "$h" -eq 1080 ] && return 0   # exact baseline — no override needed

    local ps ms ls ep_v ep_h icon_sz
    ps=$(( 72  * h / 1080 )); [ "$ps"      -lt 32 ] && ps=32
    ms=$(( 100 * h / 1080 )); [ "$ms"      -lt 48 ] && ms=48
    ls=$(( 50  * h / 1080 )); [ "$ls"      -lt 20 ] && ls=20
    ep_v=$(( 35 * h / 1080 )); [ "$ep_v"   -lt 14 ] && ep_v=14
    ep_h=$(( 40 * h / 1080 )); [ "$ep_h"   -lt 16 ] && ep_h=16
    icon_sz=$(( 64 * h / 1080 )); [ "$icon_sz" -lt 28 ] && icon_sz=28

    printf '* { prompt-font: "MesloLGS Nerd Font Bold %d"; element-text-font: "MesloLGS Nerd Font %d"; mainbox-spacing: %dpx; listview-spacing: %dpx; element-padding: %dpx %dpx; }' \
        "$ps" "$icon_sz" "$ms" "$ls" "$ep_v" "$ep_h"
}

# ── Build icon + label entries (pango markup) ──────────────
# Each entry: large icon above a small label. A real newline inside
# each entry renders as two stacked lines; the | separator tells rofi
# to treat | (not newline) as the entry boundary.
_ICON_SZ=56
_LABEL_SZ=13
_h="$(_screen_height)"
if [ "$_h" -lt 1080 ]; then
    _ICON_SZ=$(( 56 * _h / 1080 )); [ "$_ICON_SZ"  -lt 28 ] && _ICON_SZ=28
    _LABEL_SZ=$(( 13 * _h / 1080 )); [ "$_LABEL_SZ" -lt 8  ] && _LABEL_SZ=8
fi
unset _h

_entry() {
    # $1 = icon glyph   $2 = label text
    printf '<span font="MesloLGS Nerd Font %d">%s</span>\n<span font="MesloLGS Nerd Font Bold %d">%s</span>' \
        "$_ICON_SZ" "$1" "$_LABEL_SZ" "$2"
}

# Options
shutdown="$(_entry '󰐥' 'Shutdown')"
reboot="$(_entry '󰜉' 'Reboot')"
lock="$(_entry '' 'Lock')"
suspend="$(_entry '󰤄' 'Suspend')"
logout="$(_entry '󰍃' 'Logout')"
# Rofi CMD
rofi_cmd() {
	local _override
	_override="$(_scale_theme)"
	# -markup-rows renders pango markup  |  -sep '|' lets entries contain newlines
	local _args=(-dmenu -p "" -mesg "Uptime: $uptime" -markup-rows -sep '|'
	             -theme "$HOME/.config/rofi/themes/powermenu.rasi")
	[ -n "$_override" ] && _args+=(-theme-str "$_override")
	rofi "${_args[@]}"
}

# Pass variables to rofi dmenu
run_rofi() {
	printf '%s|%s|%s|%s|%s' "$lock" "$suspend" "$logout" "$reboot" "$shutdown" | rofi_cmd
}

# Execute Command
run_cmd() {
	case $1 in
		--shutdown)
			systemctl poweroff
			;;
		--reboot)
			systemctl reboot
			;;
		--suspend)
			mpc -q pause
			amixer set Master mute
			systemctl suspend
			;;
		--logout)
			case "$DESKTOP_SESSION" in
				openbox)
					openbox --exit
					;;
				bspwm)
					bspc quit
					;;
				dwm)
					pkill dwm
					;;
				i3)
					i3-msg exit
					;;
				plasma)
					qdbus org.kde.ksmserver /KSMServer logout 0 0 0
					;;
			esac
			;;
	esac
}

# Actions
chosen="$(run_rofi)"
case "${chosen}" in
    "${shutdown}")
		run_cmd --shutdown
        ;;
    "${reboot}")
		run_cmd --reboot
        ;;
    "${lock}")
		if [[ -x '/usr/bin/betterlockscreen' ]]; then
			betterlockscreen -l
		elif [[ -x '/usr/bin/i3lock' ]]; then
			i3lock
		fi
        ;;
    "${suspend}")
		run_cmd --suspend
        ;;
    "${logout}")
		run_cmd --logout
        ;;
esac
