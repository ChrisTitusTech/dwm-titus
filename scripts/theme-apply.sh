#!/bin/bash
# theme-apply.sh — Apply the active theme from themes.toml to all apps.
#
# Called automatically by DWM on config reload (SIGUSR1 / file save).
# Can also be run manually: theme-apply.sh
#
# Updates: alacritty · kitty · GTK · Qt

set -euo pipefail

RUNTIME_ONLY_EXPLICIT=false
[[ -z ${DWM_APPEARANCE_RUNTIME_ONLY+x} ]] || RUNTIME_ONLY_EXPLICIT=true
RUNTIME_ONLY=${DWM_APPEARANCE_RUNTIME_ONLY:-0}
[[ $RUNTIME_ONLY == 0 || $RUNTIME_ONLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_RUNTIME_ONLY must be 0 or 1" >&2
	exit 1
}
AUTOMATIC_APPLY=${DWM_THEME_APPLY_AUTOMATIC:-}
if [[ -z $AUTOMATIC_APPLY ]]; then
	AUTOMATIC_APPLY=0
	if [[ -r /proc/$PPID/comm ]]; then
		IFS= read -r AUTOMATIC_PARENT </proc/"$PPID"/comm || AUTOMATIC_PARENT=
		[[ $AUTOMATIC_PARENT != dwm ]] || AUTOMATIC_APPLY=1
	fi
fi
[[ $AUTOMATIC_APPLY == 0 || $AUTOMATIC_APPLY == 1 ]] || {
	echo "theme-apply: DWM_THEME_APPLY_AUTOMATIC must be 0 or 1" >&2
	exit 1
}
TRANSACTIONAL_APPLY=${DWM_APPEARANCE_TRANSACTIONAL:-0}
[[ $TRANSACTIONAL_APPLY == 0 || $TRANSACTIONAL_APPLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_TRANSACTIONAL must be 0 or 1" >&2
	exit 1
}
LIVE_ONLY=${DWM_APPEARANCE_LIVE_ONLY:-0}
[[ $LIVE_ONLY == 0 || $LIVE_ONLY == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_LIVE_ONLY must be 0 or 1" >&2
	exit 1
}
[[ ! ($RUNTIME_ONLY == 1 && $LIVE_ONLY == 1) ]] || {
	echo "theme-apply: runtime-only and live-only modes are mutually exclusive" >&2
	exit 1
}

# Serialize integration writes. A themes.toml update can trigger this script
# through dwm inotify while the Settings transaction also invokes it directly.
THEME_RUNTIME_BASE="${XDG_RUNTIME_DIR:-}"
if [[ -z "$THEME_RUNTIME_BASE" ]]; then
	THEME_RUNTIME_BASE=/tmp/dwm-titus-$UID
elif [[ "$THEME_RUNTIME_BASE" != /* ]]; then
	echo "theme-apply: XDG_RUNTIME_DIR must be an absolute path" >&2
	exit 1
fi
if [[ ! -e "$THEME_RUNTIME_BASE" ]]; then
	(umask 077 && mkdir -p -- "$THEME_RUNTIME_BASE")
fi
if [[ ! -d "$THEME_RUNTIME_BASE" || -L "$THEME_RUNTIME_BASE" ||
	$(stat -c %u -- "$THEME_RUNTIME_BASE") != "$UID" ]]; then
	echo "theme-apply: unsafe runtime directory: $THEME_RUNTIME_BASE" >&2
	exit 1
fi
chmod 700 -- "$THEME_RUNTIME_BASE"
THEME_APPLY_LOCK="$THEME_RUNTIME_BASE/dwm-theme-apply.lock"
if [[ -e "$THEME_APPLY_LOCK" &&
	(! -f "$THEME_APPLY_LOCK" || -L "$THEME_APPLY_LOCK" ||
	$(stat -c %u -- "$THEME_APPLY_LOCK") != "$UID") ]]; then
	echo "theme-apply: unsafe integration lock: $THEME_APPLY_LOCK" >&2
	exit 1
fi
command -v flock >/dev/null 2>&1 || {
	echo "theme-apply: flock is unavailable" >&2
	exit 1
}
if [[ ${DWM_APPEARANCE_INTEGRATION_LOCK_HELD:-0} == 1 && -e /proc/$$/fd/8 &&
	$(readlink -f -- /proc/$$/fd/8) == "$(readlink -f -- "$THEME_APPLY_LOCK")" ]]; then
	flock 8
elif [[ ${DWM_APPEARANCE_INTEGRATION_LOCK_HELD:-0} == 1 ]]; then
	echo "theme-apply: caller-reported integration lock does not match descriptor 8" >&2
	exit 1
else
	: >>"$THEME_APPLY_LOCK"
	chmod 600 -- "$THEME_APPLY_LOCK"
	exec 8>"$THEME_APPLY_LOCK"
	flock 8
fi

# ── Locate themes.toml ────────────────────────────────────────────────────────
THEMES_FILE="${DWM_APPEARANCE_THEMES_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/themes.toml}"
MANAGED_THEMES_FILE="${DWM_APPEARANCE_MANAGED_THEMES_FILE:-${XDG_DATA_HOME:-$HOME/.local/share}/dwm-titus/config/themes.toml}"
if [[ -e "$THEMES_FILE" || -L "$THEMES_FILE" ]]; then
	if [[ ! -f "$THEMES_FILE" || ! -r "$THEMES_FILE" ]]; then
		echo "theme-apply: user theme source is not a regular file: $THEMES_FILE" >&2
		exit 1
	fi
else
	THEMES_FILE=$MANAGED_THEMES_FILE
	if [[ ! -f "$THEMES_FILE" || -L "$THEMES_FILE" || ! -r "$THEMES_FILE" ]]; then
		echo "theme-apply: no user or managed themes.toml file is available" >&2
		exit 1
	fi
fi
THEME_SOURCE_HASH=$(sha256sum -- "$THEMES_FILE" | awk '{print $1}')

# A transactional rollback restores integration files byte-for-byte. DWM can
# still have a queued asynchronous theme-apply invocation for the same source
# change, so suppress file writes for automatic applies with that exact source
# hash during a short rollback window. Manual and explicit transaction calls
# bypass it.
if [[ $RUNTIME_ONLY_EXPLICIT == false && $AUTOMATIC_APPLY == 1 ]]; then
	THEME_STATE_HOME=${XDG_STATE_HOME:-}
	[[ $THEME_STATE_HOME == /* ]] || THEME_STATE_HOME=$HOME/.local/state
	THEME_SUPPRESS_FILE=$THEME_STATE_HOME/dwm-titus/appearance/integration-suppress
	if [[ -f $THEME_SUPPRESS_FILE && ! -L $THEME_SUPPRESS_FILE &&
		$(stat -c %u -- "$THEME_SUPPRESS_FILE") == "$UID" ]]; then
		read -r THEME_SUPPRESS_HASH THEME_SUPPRESS_DEADLINE <"$THEME_SUPPRESS_FILE" || {
			THEME_SUPPRESS_HASH=
			THEME_SUPPRESS_DEADLINE=
		}
		THEME_SUPPRESS_NOW=$(date +%s)
		if [[ $THEME_SUPPRESS_HASH == "$THEME_SOURCE_HASH" &&
			$THEME_SUPPRESS_DEADLINE =~ ^[0-9]+$ &&
			$THEME_SUPPRESS_DEADLINE -ge $THEME_SUPPRESS_NOW ]]; then
			RUNTIME_ONLY=1
		elif [[ ! $THEME_SUPPRESS_HASH =~ ^[0-9a-f]{64}$ ||
			! $THEME_SUPPRESS_DEADLINE =~ ^[0-9]+$ ||
			$THEME_SUPPRESS_DEADLINE -lt $THEME_SUPPRESS_NOW ||
			$THEME_SUPPRESS_HASH != "$THEME_SOURCE_HASH" ]]; then
			rm -f -- "$THEME_SUPPRESS_FILE"
		fi
	fi
	THEME_TRANSACTION_FILE=$THEME_STATE_HOME/dwm-titus/appearance/integration-transaction
	if [[ -f $THEME_TRANSACTION_FILE && ! -L $THEME_TRANSACTION_FILE &&
		$(stat -c %u -- "$THEME_TRANSACTION_FILE") == "$UID" ]]; then
		read -r THEME_TRANSACTION_HASH THEME_TRANSACTION_STATE <"$THEME_TRANSACTION_FILE" || {
			THEME_TRANSACTION_HASH=
			THEME_TRANSACTION_STATE=
		}
		if [[ $THEME_TRANSACTION_HASH == "$THEME_SOURCE_HASH" ]]; then
			if [[ $THEME_TRANSACTION_STATE == ready ]]; then
				TRANSACTIONAL_APPLY=1
			elif [[ $THEME_TRANSACTION_STATE == pending ]]; then
				RUNTIME_ONLY=1
			fi
		fi
	fi
fi

# ── Minimal TOML section reader ───────────────────────────────────────────────
# toml_get SECTION KEY FILE — prints the value or empty string
toml_get() {
	local section="$1" key="$2" file="$3"
	awk -v sec="[$section]" -v key="$key" '
	        /^[[:space:]]*\[/ {
	            header = $0
	            sub(/^[[:space:]]*/, "", header)
	            sub(/[[:space:]]*#.*/, "", header)
	            sub(/[[:space:]]+$/, "", header)
	            in_sec = (header == sec)
	        }
        in_sec && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/"/, "")
            gsub(/[[:space:]]+#.*$/, "")  # strip inline comments (not # in hex colors)
            sub(/[[:space:]]+$/, "")
            print; exit
        }
    ' "$file"
}

# ── Read active theme name ────────────────────────────────────────────────────
THEME_NAME="$(toml_get "active" "theme" "$THEMES_FILE")"
if [[ -z "$THEME_NAME" ]]; then
	echo "theme-apply: no [active] theme set in $THEMES_FILE" >&2
	exit 1
fi

SECTION="theme.$THEME_NAME"

# ── Helper: read a value from the active theme section ───────────────────────
theme_get() {
	toml_get "$SECTION" "$1" "$THEMES_FILE"
}

# ── Read all theme values ─────────────────────────────────────────────────────
TERM_BG="$(theme_get term_bg)"
TERM_FG="$(theme_get term_fg)"
TERM_CURSOR="$(theme_get term_cursor)"
TERM_C0="$(theme_get term_color0)"
TERM_C1="$(theme_get term_color1)"
TERM_C2="$(theme_get term_color2)"
TERM_C3="$(theme_get term_color3)"
TERM_C4="$(theme_get term_color4)"
TERM_C5="$(theme_get term_color5)"
TERM_C6="$(theme_get term_color6)"
TERM_C7="$(theme_get term_color7)"
TERM_C8="$(theme_get term_color8)"
TERM_C9="$(theme_get term_color9)"
TERM_C10="$(theme_get term_color10)"
TERM_C11="$(theme_get term_color11)"
TERM_C12="$(theme_get term_color12)"
TERM_C13="$(theme_get term_color13)"
TERM_C14="$(theme_get term_color14)"
TERM_C15="$(theme_get term_color15)"

DARK_MODE="$(theme_get dark_mode)"
[[ "$DARK_MODE" != "false" ]] && DARK_MODE="true" # default to dark if unset
CURSOR_SIZE=32
if [[ "$DARK_MODE" == "true" ]]; then
	CURSOR_THEME="Capitaine-Cursors-White"
else
	CURSOR_THEME="Capitaine-Cursors"
fi

gtk_theme_available() {
	local name="$1"
	local base
	for base in \
		"${XDG_DATA_HOME:-$HOME/.local/share}/themes" \
		"$HOME/.themes" \
		/usr/local/share/themes \
		/usr/share/themes; do
		[[ -d "$base/$name" ]] || continue
		[[ -d "$base/$name/gtk-3.0" || -d "$base/$name/gtk-4.0" ]] && return 0
	done
	return 1
}

default_gtk_theme() {
	if [[ "$DARK_MODE" == "true" ]]; then
		case "$THEME_NAME" in
		nord) printf '%s\n' "Nordic" ;;
		*) printf '%s\n' "Adwaita-dark" ;;
		esac
	else
		printf '%s\n' "Adwaita"
	fi
}

# ══════════════════════════════════════════════════════════════════════════════
# ALACRITTY — write ~/.config/alacritty/active-theme.toml
# ══════════════════════════════════════════════════════════════════════════════
ALACRITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/alacritty"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 && -d "$ALACRITTY_DIR" ]]; then
	cat >"$ALACRITTY_DIR/active-theme.toml" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
# Change the theme in ~/.config/dwm-titus/themes.toml instead.

[colors.primary]
background = '$TERM_BG'
foreground = '$TERM_FG'

[colors.cursor]
text   = '$TERM_BG'
cursor = '$TERM_CURSOR'

[colors.normal]
black   = '$TERM_C0'
red     = '$TERM_C1'
green   = '$TERM_C2'
yellow  = '$TERM_C3'
blue    = '$TERM_C4'
magenta = '$TERM_C5'
cyan    = '$TERM_C6'
white   = '$TERM_C7'

[colors.bright]
black   = '$TERM_C8'
red     = '$TERM_C9'
green   = '$TERM_C10'
yellow  = '$TERM_C11'
blue    = '$TERM_C12'
magenta = '$TERM_C13'
cyan    = '$TERM_C14'
white   = '$TERM_C15'
EOF

	# Ensure alacritty.toml imports active-theme.toml (add if missing)
	if [[ -f "$ALACRITTY_DIR/alacritty.toml" ]]; then
		if ! grep -q "active-theme.toml" "$ALACRITTY_DIR/alacritty.toml"; then
			# Insert active-theme.toml as first import entry
			sed -i 's|^\(import = \[\s*\)|\1\n  "~/.config/alacritty/active-theme.toml",|' \
				"$ALACRITTY_DIR/alacritty.toml"
		fi
		# Replace any existing theme import line to point to active-theme.toml
		# (removes old theme-specific imports, keeps keybinds import)
		sed -i 's|"~/.config/alacritty/[^k][^"]*\.toml"|"~/.config/alacritty/active-theme.toml"|g' \
			"$ALACRITTY_DIR/alacritty.toml"
	fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# KITTY — write ~/.config/kitty/active-theme.conf
# ══════════════════════════════════════════════════════════════════════════════
KITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 && -d "$KITTY_DIR" ]]; then
	cat >"$KITTY_DIR/active-theme.conf" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
# Change the theme in ~/.config/dwm-titus/themes.toml instead.

background  $TERM_BG
foreground  $TERM_FG
cursor      $TERM_CURSOR

color0  $TERM_C0
color1  $TERM_C1
color2  $TERM_C2
color3  $TERM_C3
color4  $TERM_C4
color5  $TERM_C5
color6  $TERM_C6
color7  $TERM_C7
color8  $TERM_C8
color9  $TERM_C9
color10 $TERM_C10
color11 $TERM_C11
color12 $TERM_C12
color13 $TERM_C13
color14 $TERM_C14
color15 $TERM_C15
EOF

	# Ensure kitty.conf has 'include active-theme.conf' at the top
	if [[ -f "$KITTY_DIR/kitty.conf" ]]; then
		if ! grep -q "include active-theme.conf" "$KITTY_DIR/kitty.conf"; then
			sed -i '1s|^|include active-theme.conf\n|' "$KITTY_DIR/kitty.conf"
		fi
	fi

fi
# Signal kitty after normal writes or after a transaction restored the exact
# pre-preview files. No restart is needed.
if command -v kitty &>/dev/null; then
	while IFS= read -r kitty_pid; do
		[[ $kitty_pid =~ ^[1-9][0-9]*$ ]] || continue
		kill -SIGUSR1 "$kitty_pid" 2>/dev/null || true
	done < <(pgrep -x kitty 2>/dev/null || true)
fi

# ══════════════════════════════════════════════════════════════════════════════
# GTK DARK / LIGHT MODE
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$DARK_MODE" == "true" ]]; then
	GTK_COLOR_SCHEME="prefer-dark"
	GTK_DARK_PREF=1
else
	GTK_COLOR_SCHEME="default"
	GTK_DARK_PREF=0
fi
GTK_THEME_NAME="$(theme_get gtk_theme)"
[[ -n "$GTK_THEME_NAME" ]] || GTK_THEME_NAME="$(default_gtk_theme)"
if ! gtk_theme_available "$GTK_THEME_NAME"; then
	GTK_THEME_FALLBACK="Adwaita"
	[[ "$DARK_MODE" == "true" ]] && GTK_THEME_FALLBACK="Adwaita-dark"
	echo "theme-apply: GTK theme '$GTK_THEME_NAME' not found; falling back to '$GTK_THEME_FALLBACK'" >&2
	GTK_THEME_NAME="$GTK_THEME_FALLBACK"
fi

# Helper: set or add a key in a [Settings] ini file without destroying other settings
gtk_ini_set() {
	local file="$1" key="$2" value="$3"
	mkdir -p "$(dirname "$file")"
	if [[ ! -f "$file" ]]; then
		printf '[Settings]\n%s=%s\n' "$key" "$value" >"$file"
		return
	fi
	if grep -q "^${key}" "$file"; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$file"
	elif grep -q '^\[Settings\]' "$file"; then
		sed -i "/^\[Settings\]/a ${key}=${value}" "$file"
	else
		printf '\n[Settings]\n%s=%s\n' "$key" "$value" >>"$file"
	fi
}

if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	# GTK3
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-application-prefer-dark-theme" "$GTK_DARK_PREF"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-theme-name" "$GTK_THEME_NAME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-cursor-theme-name" "$CURSOR_THEME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"gtk-cursor-theme-size" "$CURSOR_SIZE"

	# GTK4
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-application-prefer-dark-theme" "$GTK_DARK_PREF"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-theme-name" "$GTK_THEME_NAME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-cursor-theme-name" "$CURSOR_THEME"
	gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
		"gtk-cursor-theme-size" "$CURSOR_SIZE"

	# GTK2
	printf 'gtk-theme-name="%s"\ngtk-cursor-theme-name="%s"\ngtk-cursor-theme-size=%s\n' \
		"$GTK_THEME_NAME" "$CURSOR_THEME" "$CURSOR_SIZE" >"$HOME/.gtkrc-2.0"
fi

# Xcursor settings for Xlib applications and programs launched after reload.
CURSOR_XRESOURCES="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/cursor.Xresources"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	mkdir -p "${CURSOR_XRESOURCES%/*}"
	printf 'Xcursor.theme: %s\nXcursor.size: %s\n' \
		"$CURSOR_THEME" "$CURSOR_SIZE" >"$CURSOR_XRESOURCES"
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] &&
	command -v xrdb &>/dev/null && [[ -n "${DISPLAY:-}" ]]; then
	printf 'Xcursor.theme: %s\nXcursor.size: %s\n' "$CURSOR_THEME" "$CURSOR_SIZE" |
		xrdb -merge
fi

# Live D-Bus update — affects running GTK4 apps, Flatpaks, and XDG portals
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v gsettings &>/dev/null; then
	gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
	gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v xfconf-query &>/dev/null; then
	xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$GTK_THEME_NAME" 2>/dev/null || true
	xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s "$CURSOR_THEME" 2>/dev/null || true
	xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s "$CURSOR_SIZE" 2>/dev/null || true
fi

# ══════════════════════════════════════════════════════════════════════════════
# QT DARK / LIGHT MODE
# ══════════════════════════════════════════════════════════════════════════════
# Prefer qt6ct > qt5ct; fall back to gtk3 (inherits GTK theme set above)
if command -v qt6ct &>/dev/null; then
	QT_PLATFORM_THEME="qt6ct"
elif command -v qt5ct &>/dev/null; then
	QT_PLATFORM_THEME="qt5ct"
else
	QT_PLATFORM_THEME="gtk3"
fi

# Write persistent env file — sourced by autostart.sh so tray apps inherit it
THEME_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/theme-env.sh"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	cat >"$THEME_ENV_FILE" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
export QT_QPA_PLATFORMTHEME=$QT_PLATFORM_THEME
export XCURSOR_THEME=$CURSOR_THEME
export XCURSOR_SIZE=$CURSOR_SIZE
EOF

fi

# Update qt5ct / qt6ct color scheme config if that tool is the active theme
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 &&
	("$QT_PLATFORM_THEME" == "qt5ct" || "$QT_PLATFORM_THEME" == "qt6ct") ]]; then
	QT_CT_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/${QT_PLATFORM_THEME}/${QT_PLATFORM_THEME}.conf"
	if [[ -f "$QT_CT_CONF" ]]; then
		if [[ "$DARK_MODE" == "true" ]]; then
			QT_CT_SCHEME="/usr/share/${QT_PLATFORM_THEME}/colors/darker.conf"
		else
			QT_CT_SCHEME=""
		fi
		if grep -q '^color_scheme_path' "$QT_CT_CONF"; then
			sed -i "s|^color_scheme_path=.*|color_scheme_path=$QT_CT_SCHEME|" "$QT_CT_CONF"
		else
			sed -i "/^\[Appearance\]/a color_scheme_path=${QT_CT_SCHEME}" "$QT_CT_CONF"
		fi
	fi
fi

# Propagate to user services and D-Bus-activated services in this session
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] && command -v systemctl &>/dev/null; then
	systemctl --user import-environment \
		QT_QPA_PLATFORMTHEME \
		XCURSOR_THEME \
		XCURSOR_SIZE 2>/dev/null || true
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]] &&
	command -v dbus-update-activation-environment &>/dev/null; then
	dbus-update-activation-environment --systemd \
		QT_QPA_PLATFORMTHEME="$QT_PLATFORM_THEME" \
		XCURSOR_THEME="$CURSOR_THEME" \
		XCURSOR_SIZE="$CURSOR_SIZE" 2>/dev/null || true
fi

echo "theme-apply: applied theme '$THEME_NAME'"
