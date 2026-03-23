#!/usr/bin/env bash

uptime_info="$(uptime -p | sed 's/up //')"

# ── Theme integration (reads colors from themes.toml) ────
_themes_file() {
    local f="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/themes.toml"
    [[ -f "$f" ]] && echo "$f"
}

_toml_get() {
    local section="$1" key="$2" file="$3"
    awk -v sec="[$section]" -v key="$key" '
        /^\[/ { in_sec = ($0 == sec) }
        in_sec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/"/, "")
            gsub(/[[:space:]]+#.*$/, "")
            sub(/[[:space:]]+$/, "")
            print; exit
        }
    ' "$file"
}

_theme_colors() {
    local tf; tf="$(_themes_file)"
    [[ -z "$tf" ]] && return 0

    local name; name="$(_toml_get "active" "theme" "$tf")"
    [[ -z "$name" ]] && return 0

    local sec="theme.$name"
    local bg;     bg="$(_toml_get "$sec" "normbgcolor"     "$tf")"
    local bg_alt; bg_alt="$(_toml_get "$sec" "selbgcolor"  "$tf")"
    local fg;     fg="$(_toml_get "$sec" "normfgcolor"     "$tf")"
    local accent; accent="$(_toml_get "$sec" "selbordercolor" "$tf")"
    local border; border="$(_toml_get "$sec" "normbordercolor" "$tf")"

    [[ -z "$bg" ]] && return 0

    printf '* { background: %s; background-alt: %s; foreground: %s; accent: %s; border-col: %s; background-color: %s; text-color: %s; }' \
        "$bg" "$bg_alt" "$fg" "$accent" "$border" "$bg" "$fg"
}

# ── Resolution scaling ───────────────────────────────────
_screen_height() {
    if command -v xrandr &>/dev/null; then
        xrandr --query | awk '/\*/ { split($1,a,"x"); print a[2]; exit }'
        return
    fi
    echo "1080"
}

_scale_theme() {
    local h
    h="$(_screen_height)"
    [ "$h" -eq 1080 ] && return 0

    local icon win_w win_h pad_v pad_h
    icon=$(( 30  * h / 1080 )); [ "$icon"  -lt 14 ] && icon=14
    win_w=$(( 500 * h / 1080 )); [ "$win_w" -lt 240 ] && win_w=240
    win_h=$(( 130 * h / 1080 )); [ "$win_h" -lt 60  ] && win_h=60
    pad_v=$(( 20  * h / 1080 )); [ "$pad_v" -lt 8   ] && pad_v=8
    pad_h=$(( 30  * h / 1080 )); [ "$pad_h" -lt 12  ] && pad_h=12

    printf '* { element-text-font: "MesloLGS Nerd Font %d"; } window { width: %dpx; height: %dpx; } mainbox { padding: %dpx %dpx; }' \
        "$icon" "$win_w" "$win_h" "$pad_v" "$pad_h"
}

# Icons
lock=''
logout='󰍃'
sleep='󰤄'
reboot='󰜉'
shutdown='󰐥'

rofi_cmd() {
    local _colors; _colors="$(_theme_colors)"
    local _scale;  _scale="$(_scale_theme)"
    local _args=(-dmenu -i -p "  $uptime_info"
                 -theme "$HOME/.config/rofi/themes/powermenu.rasi")
    [ -n "$_colors" ] && _args+=(-theme-str "$_colors")
    [ -n "$_scale"  ] && _args+=(-theme-str "$_scale")
    rofi "${_args[@]}"
}

selected=$(printf '%s\n%s\n%s\n%s\n%s' \
    "$lock" "$logout" "$sleep" "$reboot" "$shutdown" | rofi_cmd)

case "$selected" in
    "$lock")
        if command -v betterlockscreen &>/dev/null; then
            betterlockscreen -l
        elif command -v i3lock &>/dev/null; then
            i3lock
        fi
        ;;
    "$logout")
        case "$DESKTOP_SESSION" in
            dwm)     pkill dwm ;;
            openbox) openbox --exit ;;
            bspwm)   bspc quit ;;
            i3)      i3-msg exit ;;
            plasma)  qdbus org.kde.ksmserver /KSMServer logout 0 0 0 ;;
        esac
        ;;
    "$sleep")
        amixer set Master mute 2>/dev/null
        systemctl suspend
        ;;
    "$reboot")
        systemctl reboot
        ;;
    "$shutdown")
        systemctl poweroff
        ;;
esac
