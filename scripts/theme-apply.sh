#!/bin/bash
# theme-apply.sh — Apply the active theme from themes.toml to all apps.
#
# Called automatically by DWM on config reload (SIGUSR1 / file save).
# Can also be run manually: theme-apply.sh
#
# Updates: alacritty · kitty · GTK · Qt

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
XSETTINGS_HELPER=${DWM_APPEARANCE_XSETTINGS_HELPER:-$script_dir/dwm-xsettings}
THEME_DISCOVERY_HOME=${DWM_APPEARANCE_DISCOVERY_HOME:-$HOME}
[[ $THEME_DISCOVERY_HOME == /* ]] || {
	echo "theme-apply: theme discovery home must be an absolute path" >&2
	exit 1
}
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
STAGED_OUTPUT=${DWM_APPEARANCE_STAGED_OUTPUT:-0}
[[ $STAGED_OUTPUT == 0 || $STAGED_OUTPUT == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_STAGED_OUTPUT must be 0 or 1" >&2
	exit 1
}
STRICT_PERSONALIZATION=${DWM_APPEARANCE_STRICT_PERSONALIZATION:-0}
[[ $STRICT_PERSONALIZATION == 0 || $STRICT_PERSONALIZATION == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_STRICT_PERSONALIZATION must be 0 or 1" >&2
	exit 1
}
PRESERVE_DESKTOP_SETTINGS=${DWM_APPEARANCE_PRESERVE_DESKTOP_SETTINGS:-0}
[[ $PRESERVE_DESKTOP_SETTINGS == 0 || $PRESERVE_DESKTOP_SETTINGS == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_PRESERVE_DESKTOP_SETTINGS must be 0 or 1" >&2
	exit 1
}
PERSONALIZATION_CAPABILITY=${DWM_APPEARANCE_PERSONALIZATION_CAPABILITY:-}
case $PERSONALIZATION_CAPABILITY in
'' | font | text-size | cursor | icon | gtk | qt) ;;
*)
	echo 'theme-apply: invalid personalization capability' >&2
	exit 1
	;;
esac
PERSONALIZATION_XFCONF=${DWM_APPEARANCE_PERSONALIZATION_XFCONF:-0}
[[ $PERSONALIZATION_XFCONF == 0 || $PERSONALIZATION_XFCONF == 1 ]] || {
	echo "theme-apply: DWM_APPEARANCE_PERSONALIZATION_XFCONF must be 0 or 1" >&2
	exit 1
}
PERSONALIZATION_BASELINE_PREFIX=${DWM_APPEARANCE_PERSONALIZATION_BASELINE_PREFIX:-}
if [[ -n $PERSONALIZATION_BASELINE_PREFIX && $PERSONALIZATION_BASELINE_PREFIX != /* ]]; then
	echo 'theme-apply: personalization baseline prefix must be absolute' >&2
	exit 1
fi
DESKTOP_FONT_SIZE_OVERRIDE=${DWM_APPEARANCE_DESKTOP_FONT_SIZE:-}
if [[ -n $DESKTOP_FONT_SIZE_OVERRIDE &&
	! $DESKTOP_FONT_SIZE_OVERRIDE =~ ^[1-9][0-9]{0,2}([.][0-9]+)?$ ]]; then
	echo 'theme-apply: invalid desktop font size override' >&2
	exit 1
fi
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
# hash during a short rollback window. The active transaction marker applies to
# both automatic and manual invocations so neither can escape preview rollback.
if [[ $RUNTIME_ONLY_EXPLICIT == false ]]; then
	THEME_STATE_HOME=${XDG_STATE_HOME:-}
	[[ $THEME_STATE_HOME == /* ]] || THEME_STATE_HOME=$HOME/.local/state
	if [[ $AUTOMATIC_APPLY == 1 ]]; then
		THEME_SUPPRESS_FILE=$THEME_STATE_HOME/dwm-titus/appearance/integration-suppress
		if [[ -f $THEME_SUPPRESS_FILE && ! -L $THEME_SUPPRESS_FILE &&
			$(stat -c %u -- "$THEME_SUPPRESS_FILE") == "$UID" ]]; then
			read -r THEME_SUPPRESS_HASH _ <"$THEME_SUPPRESS_FILE" || {
				THEME_SUPPRESS_HASH=
			}
			if [[ $THEME_SUPPRESS_HASH == "$THEME_SOURCE_HASH" ]]; then
				RUNTIME_ONLY=1
			elif [[ ! $THEME_SUPPRESS_HASH =~ ^[0-9a-f]{64}$ ||
				$THEME_SUPPRESS_HASH != "$THEME_SOURCE_HASH" ]]; then
				rm -f -- "$THEME_SUPPRESS_FILE"
			fi
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
			if [[ $THEME_TRANSACTION_STATE == ready ||
				$THEME_TRANSACTION_STATE == pending ]]; then
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

PERSONALIZATION_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/personalization.conf"
personalization_validate() {
	[[ ! -e $PERSONALIZATION_FILE && ! -L $PERSONALIZATION_FILE ]] && return 0
	[[ -f $PERSONALIZATION_FILE && ! -L $PERSONALIZATION_FILE &&
		$(stat -c %u -- "$PERSONALIZATION_FILE") == "$UID" &&
		$(stat -c %h -- "$PERSONALIZATION_FILE") == 1 &&
		$(stat -c %s -- "$PERSONALIZATION_FILE") -le 4096 ]] || return 1
	awk -F '\t' '
		NR == 1 { if ($0 != "personalization-protocol\t1\t0") bad = 1; next }
		NF != 2 || $1 !~ /^(font|text-size|cursor|icon|gtk|qt)$/ || seen[$1]++ { bad = 1 }
		$2 == "" || $2 ~ /[\r\n]/ || length($2) > 255 { bad = 1 }
		END { exit(NR > 0 && !bad ? 0 : 1) }
	' "$PERSONALIZATION_FILE"
}

if ! personalization_validate; then
	if [[ $STRICT_PERSONALIZATION == 1 ]]; then
		echo "theme-apply: personalization configuration is invalid or unsafe: $PERSONALIZATION_FILE" >&2
		exit 1
	fi
	echo "theme-apply: ignoring invalid personalization configuration: $PERSONALIZATION_FILE" >&2
	PERSONALIZATION_FILE=
fi

personalization_get() {
	local key=$1
	[[ -f $PERSONALIZATION_FILE && ! -L $PERSONALIZATION_FILE ]] || return 1
	awk -F '\t' -v key="$key" '
		NR == 1 { next }
		$1 == key { value = $2; found = 1 }
		END { if (found) print value; exit(found ? 0 : 1) }
	' "$PERSONALIZATION_FILE"
}

FONT_CHOICE=$(personalization_get font 2>/dev/null || true)
TEXT_SCALE_CHOICE=$(personalization_get text-size 2>/dev/null || true)
CURSOR_CHOICE=$(personalization_get cursor 2>/dev/null || true)
ICON_CHOICE=$(personalization_get icon 2>/dev/null || true)
GTK_CHOICE=$(personalization_get gtk 2>/dev/null || true)
QT_CHOICE=$(personalization_get qt 2>/dev/null || true)

personalization_name_valid() {
	[[ -n $1 && ${#1} -le 255 && $1 != */* && $1 != *\\* && $1 != *\"* &&
		$1 != *=* && $1 != *'|'* && $1 != *'&'* && $1 != . && $1 != .. ]]
}
personalization_choice_valid() {
	local value=$2 follow_value=$3
	[[ -z $value || $value == "$follow_value" ]] && return 0
	[[ $value != follow-system && $value != follow-theme ]] || return 1
	personalization_name_valid "$value"
}
for PERSONALIZATION_NAME in font cursor icon gtk; do
	case $PERSONALIZATION_NAME in
	font)
		PERSONALIZATION_VALUE=$FONT_CHOICE
		PERSONALIZATION_FOLLOW=follow-system
		;;
	cursor)
		PERSONALIZATION_VALUE=$CURSOR_CHOICE
		PERSONALIZATION_FOLLOW=follow-theme
		;;
	icon)
		PERSONALIZATION_VALUE=$ICON_CHOICE
		PERSONALIZATION_FOLLOW=follow-system
		;;
	gtk)
		PERSONALIZATION_VALUE=$GTK_CHOICE
		PERSONALIZATION_FOLLOW=follow-theme
		;;
	esac
	personalization_choice_valid "$PERSONALIZATION_NAME" "$PERSONALIZATION_VALUE" \
		"$PERSONALIZATION_FOLLOW" && continue
	if [[ $STRICT_PERSONALIZATION == 1 ]]; then
		echo "theme-apply: personalization configuration contains an invalid $PERSONALIZATION_NAME value" >&2
		exit 1
	fi
	echo "theme-apply: ignoring invalid $PERSONALIZATION_NAME personalization value" >&2
	case $PERSONALIZATION_NAME in
	font) FONT_CHOICE= ;;
	cursor) CURSOR_CHOICE= ;;
	icon) ICON_CHOICE= ;;
	gtk) GTK_CHOICE= ;;
	esac
done
case $TEXT_SCALE_CHOICE in
'' | follow-system | 0.75 | 0.875 | 1.0 | 1.125 | 1.25 | 1.5 | 1.75 | 2.0) ;;
*)
	if [[ $STRICT_PERSONALIZATION == 1 ]]; then
		echo 'theme-apply: personalization configuration contains an invalid text scale' >&2
		exit 1
	fi
	echo 'theme-apply: ignoring invalid text-size personalization value' >&2
	TEXT_SCALE_CHOICE=
	;;
esac
case $QT_CHOICE in
'' | follow-theme | gtk3 | qt6ct | qt5ct) ;;
*)
	if [[ $STRICT_PERSONALIZATION == 1 ]]; then
		echo 'theme-apply: personalization configuration contains an invalid Qt backend' >&2
		exit 1
	fi
	echo 'theme-apply: ignoring invalid qt personalization value' >&2
	QT_CHOICE=
	;;
esac

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
if [[ -n $CURSOR_CHOICE && $CURSOR_CHOICE != follow-theme ]]; then
	CURSOR_THEME=$CURSOR_CHOICE
fi

gtk_theme_available() {
	local name="$1"
	local base root
	local -a data_roots=()
	[[ $name == Adwaita || $name == Adwaita-dark ]] && return 0
	for base in \
		"${XDG_DATA_HOME:-$HOME/.local/share}/themes" \
		"$THEME_DISCOVERY_HOME/.themes"; do
		[[ -d "$base/$name" ]] || continue
		[[ -d "$base/$name/gtk-3.0" || -d "$base/$name/gtk-4.0" ]] && return 0
	done
	IFS=: read -r -a data_roots <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	for root in "${data_roots[@]}"; do
		[[ $root == /* ]] || continue
		[[ -d "$root/themes/$name/gtk-3.0" || -d "$root/themes/$name/gtk-4.0" ]] && return 0
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
if [[ $STAGED_OUTPUT == 0 ]] && command -v kitty &>/dev/null; then
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
if [[ -n $GTK_CHOICE && $GTK_CHOICE != follow-theme ]]; then
	GTK_THEME_NAME=$GTK_CHOICE
fi
if ! gtk_theme_available "$GTK_THEME_NAME"; then
	GTK_THEME_FALLBACK="Adwaita"
	[[ "$DARK_MODE" == "true" ]] && GTK_THEME_FALLBACK="Adwaita-dark"
	echo "theme-apply: GTK theme '$GTK_THEME_NAME' not found; falling back to '$GTK_THEME_FALLBACK'" >&2
	GTK_THEME_NAME="$GTK_THEME_FALLBACK"
fi

# Helper: set or add a key in a [Settings] ini file without destroying other settings
gtk_ini_edit_path() {
	local file=$1
	if [[ -L $file ]]; then
		file=$(readlink -f -- "$file") || {
			echo "theme-apply: GTK configuration symlink has no valid target" >&2
			return 1
		}
		[[ -f $file ]] || {
			echo "theme-apply: GTK configuration symlink target is not a regular file" >&2
			return 1
		}
	fi
	printf '%s\n' "$file"
}

gtk_ini_set() {
	local file="$1" key="$2" value="$3" temporary mode=600
	file=$(gtk_ini_edit_path "$file") || return 1
	mkdir -p -- "${file%/*}"
	temporary=$(mktemp "${file%/*}/.settings.ini.XXXXXX")
	if [[ -f $file ]]; then
		mode=$(stat -c %a -- "$file")
		awk -v key="$key" -v assignment="$key=$value" '
			BEGIN { in_settings = 0; saw_settings = 0 }
			/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
				if (in_settings && !written) {
					print assignment
					written = 1
				}
				header = $0
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
				in_settings = (header == "[Settings]")
				if (in_settings) saw_settings = 1
				print
				next
			}
			in_settings {
				equals = index($0, "=")
				name = equals ? substr($0, 1, equals - 1) : ""
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
				if (name == key) {
					if (!written) print assignment
					written = 1
					next
				}
			}
			{ print }
			END {
				if (!written) {
					if (!saw_settings) {
						if (NR) print ""
						print "[Settings]"
					}
					print assignment
				}
			}
		' "$file" >"$temporary"
	else
		printf '[Settings]\n%s=%s\n' "$key" "$value" >"$temporary"
	fi
	chmod "$mode" -- "$temporary"
	mv -f -- "$temporary" "$file"
}

gtk_ini_unset() {
	local file="$1" key="$2" temporary
	file=$(gtk_ini_edit_path "$file") || return 1
	[[ -f $file ]] || return 0
	temporary=$(mktemp "${file%/*}/.settings.ini.XXXXXX")
	awk -v key="$key" '
		BEGIN { in_settings = 0 }
		/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
			header = $0
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
			in_settings = (header == "[Settings]")
			print
			next
		}
		in_settings {
			equals = index($0, "=")
			name = equals ? substr($0, 1, equals - 1) : ""
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			if (name == key) next
		}
		{ print }
	' "$file" >"$temporary"
	chmod --reference="$file" "$temporary"
	mv -f -- "$temporary" "$file"
}

gtk2_edit_path() {
	local file=$1
	if [[ -L $file ]]; then
		file=$(readlink -f -- "$file") || {
			echo "theme-apply: GTK2 configuration symlink has no valid target" >&2
			return 1
		}
		[[ -f $file ]] || {
			echo "theme-apply: GTK2 configuration symlink target is not a regular file" >&2
			return 1
		}
	fi
	printf '%s\n' "$file"
}

gtk2_unset() {
	local file="$1" key="$2" temporary
	file=$(gtk2_edit_path "$file") || return 1
	[[ -f $file ]] || return 0
	temporary=$(mktemp "${file%/*}/.gtkrc-2.0.XXXXXX")
	awk -v key="$key" '
		{
			equals = index($0, "=")
			name = equals ? substr($0, 1, equals - 1) : ""
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			if (name != key) print
		}
	' "$file" >"$temporary"
	chmod --reference="$file" "$temporary"
	mv -f -- "$temporary" "$file"
}

gtk2_write() {
	local file="$1" key="$2" assignment="$3" temporary mode=600
	file=$(gtk2_edit_path "$file") || return 1
	mkdir -p -- "${file%/*}"
	temporary=$(mktemp "${file%/*}/.gtkrc-2.0.XXXXXX")
	if [[ -f $file ]]; then
		mode=$(stat -c %a -- "$file")
		awk -v key="$key" -v assignment="$assignment" '
			{
				equals = index($0, "=")
				name = equals ? substr($0, 1, equals - 1) : ""
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
			}
			name == key {
				if (!written) print assignment
				written = 1
				next
			}
			{ print }
			END { if (!written) print assignment }
		' "$file" >"$temporary"
	else
		printf '%s\n' "$assignment" >"$temporary"
	fi
	chmod "$mode" -- "$temporary"
	mv -f -- "$temporary" "$file"
}

gtk2_set() {
	local file=$1 key=$2 value=$3
	gtk2_write "$file" "$key" "$key=\"$value\""
}

gtk2_set_integer() {
	local file=$1 key=$2 value=$3
	[[ $value =~ ^[0-9]+$ ]] || return 1
	gtk2_write "$file" "$key" "$key=$value"
}

xsettingsd_config_write() {
	local file=$1 key=$2 assignment=${3:-} temporary mode=600
	if [[ -e $file || -L $file ]]; then
		[[ -f $file && ! -L $file && $(stat -c %u -- "$file") == "$UID" &&
		$(stat -c %h -- "$file") == 1 && $(stat -c %s -- "$file") -le 65536 ]] || {
			echo "theme-apply: unsafe generated XSETTINGS configuration: $file" >&2
			return 1
		}
	fi
	mkdir -p -- "${file%/*}"
	temporary=$(mktemp "${file%/*}/.xsettingsd.conf.XXXXXX")
	if [[ -f $file ]]; then
		mode=$(stat -c %a -- "$file")
		awk -v key="$key" -v assignment="$assignment" '
			BEGIN { print "# Auto-generated by theme-apply.sh - do not edit manually." }
			$0 == "# Auto-generated by theme-apply.sh - do not edit manually." { next }
			{
				name = $1
				if (name == key) {
					if (!written && assignment != "") print assignment
					written = 1
					next
				}
				print
			}
			END {
				if (!written && assignment != "") print assignment
			}
		' "$file" >"$temporary"
	else
		printf '# Auto-generated by theme-apply.sh - do not edit manually.\n' >"$temporary"
		[[ -z $assignment ]] || printf '%s\n' "$assignment" >>"$temporary"
	fi
	chmod "$mode" -- "$temporary"
	mv -f -- "$temporary" "$file"
}

xsettingsd_scale_dpi() {
	case $1 in
	0.75) printf '73728\n' ;;
	0.875) printf '86016\n' ;;
	1.0) printf '98304\n' ;;
	1.125) printf '110592\n' ;;
	1.25) printf '122880\n' ;;
	1.5) printf '147456\n' ;;
	1.75) printf '172032\n' ;;
	2.0) printf '196608\n' ;;
	*) return 1 ;;
	esac
}

configured_font_description() {
	local file line
	for file in \
		"${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini"; do
		[[ -f $file && ! -L $file ]] || continue
		line=$(awk -v key=gtk-font-name '
			/^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
				header = $0
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", header)
				in_settings = (header == "[Settings]")
				next
			}
			in_settings {
				equals = index($0, "=")
				name = equals ? substr($0, 1, equals - 1) : ""
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
				if (name == key) {
					value = substr($0, equals + 1)
					gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
					print value
					exit
				}
			}
		' "$file" 2>/dev/null || true)
		line=${line#\"}
		line=${line%\"}
		[[ -z $line ]] || {
			printf '%s' "$line"
			return 0
		}
	done
	file=$HOME/.gtkrc-2.0
	if [[ -f $file && ! -L $file ]]; then
		line=$(awk -v key=gtk-font-name '
			{
				equals = index($0, "=")
				name = equals ? substr($0, 1, equals - 1) : ""
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
				if (name == key) {
					value = substr($0, equals + 1)
					gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
					print value
					exit
				}
			}
		' "$file" 2>/dev/null || true)
		line=${line#\"}
		line=${line%\"}
		[[ -z $line ]] || printf '%s' "$line"
	fi
}

desktop_font_size() {
	local description size
	if [[ -n $DESKTOP_FONT_SIZE_OVERRIDE ]]; then
		printf '%s' "$DESKTOP_FONT_SIZE_OVERRIDE"
		return 0
	fi
	description=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null || true)
	description=${description#\'}
	description=${description%\'}
	description=${description#\"}
	description=${description%\"}
	size=${description##* }
	if [[ ! $size =~ ^[1-9][0-9]{0,2}([.][0-9]+)?$ ]]; then
		description=$(configured_font_description)
		size=${description##* }
	fi
	[[ $size =~ ^[1-9][0-9]{0,2}([.][0-9]+)?$ ]] || size=11
	printf '%s' "$size"
}

shell_assignment_escape() {
	local LC_ALL=C value=$1 result='' character index
	for ((index = 0; index < ${#value}; index++)); do
		character=${value:index:1}
		if [[ $character =~ ^[A-Za-z0-9._+@-]$ ]]; then
			result+=$character
		else
			result+=\\$character
		fi
	done
	printf '%s' "$result"
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

	if [[ -n $FONT_CHOICE && $FONT_CHOICE != follow-system ]]; then
		DESKTOP_FONT_NAME="$FONT_CHOICE $(desktop_font_size)"
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
			"gtk-font-name" "$DESKTOP_FONT_NAME"
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
			"gtk-font-name" "$DESKTOP_FONT_NAME"
	elif [[ $FONT_CHOICE == follow-system && $PERSONALIZATION_CAPABILITY == font ]]; then
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" gtk-font-name
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" gtk-font-name
	fi
	if [[ -n $ICON_CHOICE && $ICON_CHOICE != follow-system ]]; then
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
			"gtk-icon-theme-name" "$ICON_CHOICE"
		gtk_ini_set "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
			"gtk-icon-theme-name" "$ICON_CHOICE"
	elif [[ $ICON_CHOICE == follow-system && $PERSONALIZATION_CAPABILITY == icon ]]; then
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" gtk-icon-theme-name
		gtk_ini_unset "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" gtk-icon-theme-name
	fi

	# GTK2
	gtk2_set "$HOME/.gtkrc-2.0" gtk-theme-name "$GTK_THEME_NAME"
	gtk2_set "$HOME/.gtkrc-2.0" gtk-cursor-theme-name "$CURSOR_THEME"
	gtk2_set_integer "$HOME/.gtkrc-2.0" gtk-cursor-theme-size "$CURSOR_SIZE"
	if [[ -n $FONT_CHOICE && $FONT_CHOICE != follow-system ]]; then
		gtk2_set "$HOME/.gtkrc-2.0" gtk-font-name "$FONT_CHOICE $(desktop_font_size)"
	elif [[ $FONT_CHOICE == follow-system && $PERSONALIZATION_CAPABILITY == font ]]; then
		gtk2_unset "$HOME/.gtkrc-2.0" gtk-font-name
	fi
	if [[ -n $ICON_CHOICE && $ICON_CHOICE != follow-system ]]; then
		gtk2_set "$HOME/.gtkrc-2.0" gtk-icon-theme-name "$ICON_CHOICE"
	elif [[ $ICON_CHOICE == follow-system && $PERSONALIZATION_CAPABILITY == icon ]]; then
		gtk2_unset "$HOME/.gtkrc-2.0" gtk-icon-theme-name
	fi
fi

# Plain DWM Xorg sessions intentionally do not run a desktop settings daemon.
# Publish text scaling to a project-owned xsettingsd configuration so native
# GTK applications consume the same fixed-point DPI as the persisted choice.
XSETTINGSD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/xsettingsd.conf"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	if [[ -z $TEXT_SCALE_CHOICE || $TEXT_SCALE_CHOICE == follow-system ]]; then
		xsettingsd_config_write "$XSETTINGSD_CONFIG" Xft/DPI
	else
		TEXT_SCALE_DPI=$(xsettingsd_scale_dpi "$TEXT_SCALE_CHOICE")
		xsettingsd_config_write "$XSETTINGSD_CONFIG" Xft/DPI \
			"Xft/DPI $TEXT_SCALE_DPI"
	fi
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

personalization_baseline_file_safe() {
	local file=$1
	[[ -f $file && ! -L $file && -r $file &&
		$(stat -c %u -- "$file") == "$UID" &&
		$(stat -c %h -- "$file") == 1 &&
		$(stat -c %s -- "$file") -le 4096 ]]
}

personalization_gsettings_baseline_matches() {
	local capability key dconf_path expected current
	[[ -n $PERSONALIZATION_BASELINE_PREFIX ]] || return 1
	personalization_baseline_file_safe "$PERSONALIZATION_BASELINE_PREFIX.gsettings.capability" ||
		return 1
	personalization_baseline_file_safe "$PERSONALIZATION_BASELINE_PREFIX.gsettings.before" ||
		return 1
	IFS= read -r capability <"$PERSONALIZATION_BASELINE_PREFIX.gsettings.capability"
	[[ $capability == "$PERSONALIZATION_CAPABILITY" ]] || return 1
	case $capability in
	font)
		key=font-name
		dconf_path=/org/gnome/desktop/interface/font-name
		;;
	text-size)
		key=text-scaling-factor
		dconf_path=/org/gnome/desktop/interface/text-scaling-factor
		;;
	cursor)
		key=cursor-theme
		dconf_path=/org/gnome/desktop/interface/cursor-theme
		;;
	icon)
		key=icon-theme
		dconf_path=/org/gnome/desktop/interface/icon-theme
		;;
	gtk)
		key=gtk-theme
		dconf_path=/org/gnome/desktop/interface/gtk-theme
		;;
	*) return 1 ;;
	esac
	[[ $(gsettings writable org.gnome.desktop.interface "$key" 2>/dev/null) == true ]] || return 1
	expected=$(<"$PERSONALIZATION_BASELINE_PREFIX.gsettings.before")
	current=$(dconf read "$dconf_path" 2>/dev/null) || return 1
	[[ $current == "$expected" ]]
}

personalization_xfconf_baseline_matches() {
	local capability property expected expected_existed current current_existed
	[[ -n $PERSONALIZATION_BASELINE_PREFIX ]] || return 1
	personalization_baseline_file_safe "$PERSONALIZATION_BASELINE_PREFIX.xfconf.capability" ||
		return 1
	personalization_baseline_file_safe "$PERSONALIZATION_BASELINE_PREFIX.xfconf.before" ||
		return 1
	personalization_baseline_file_safe "$PERSONALIZATION_BASELINE_PREFIX.xfconf.before-existed" ||
		return 1
	IFS= read -r capability <"$PERSONALIZATION_BASELINE_PREFIX.xfconf.capability"
	[[ $capability == "$PERSONALIZATION_CAPABILITY" ]] || return 1
	case $capability in
	gtk) property=/Net/ThemeName ;;
	cursor) property=/Gtk/CursorThemeName ;;
	*) return 1 ;;
	esac
	IFS= read -r expected_existed <"$PERSONALIZATION_BASELINE_PREFIX.xfconf.before-existed"
	[[ $expected_existed == 0 || $expected_existed == 1 ]] || return 1
	if current=$(xfconf-query -c xsettings -p "$property" 2>/dev/null); then
		current_existed=1
	elif xfconf-query -c xsettings -l >/dev/null 2>&1; then
		current_existed=0
		current=
	else
		return 1
	fi
	expected=$(<"$PERSONALIZATION_BASELINE_PREFIX.xfconf.before")
	[[ $current_existed == "$expected_existed" && $current == "$expected" ]]
}

personalization_live_write_test_wait() {
	[[ -n ${DWM_TEST_BEFORE_PERSONALIZATION_LIVE_WRITE:-} ]] || return 0
	: >"$DWM_TEST_BEFORE_PERSONALIZATION_LIVE_WRITE"
	while [[ ! -e ${DWM_TEST_PERSONALIZATION_LIVE_WRITE_RELEASE:-} ]]; do
		sleep 0.01
	done
}

# Live D-Bus update — affects running GTK4 apps, Flatpaks, and XDG portals
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 &&
	$PRESERVE_DESKTOP_SETTINGS == 0 ]] && command -v gsettings &>/dev/null; then
	if [[ $STRICT_PERSONALIZATION == 1 && $PERSONALIZATION_CAPABILITY != qt ]]; then
		personalization_live_write_test_wait
		personalization_gsettings_baseline_matches || {
			echo 'theme-apply: personalization GSettings changed before the live write' >&2
			exit 1
		}
	fi
	personalization_status=0
	if [[ -z $PERSONALIZATION_CAPABILITY ]]; then
		gsettings set org.gnome.desktop.interface color-scheme "$GTK_COLOR_SCHEME" 2>/dev/null || true
		gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
		gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null || true
		gsettings set org.gnome.desktop.interface cursor-size "$CURSOR_SIZE" 2>/dev/null || true
	elif [[ $PERSONALIZATION_CAPABILITY == gtk ]]; then
		gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null ||
			personalization_status=1
	elif [[ $PERSONALIZATION_CAPABILITY == cursor ]]; then
		gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR_THEME" 2>/dev/null ||
			personalization_status=1
	fi
	if [[ -n $FONT_CHOICE &&
		(-z $PERSONALIZATION_CAPABILITY || $PERSONALIZATION_CAPABILITY == font) ]]; then
		if [[ $FONT_CHOICE == follow-system ]]; then
			if [[ $PERSONALIZATION_CAPABILITY == font ]]; then
				gsettings reset org.gnome.desktop.interface font-name 2>/dev/null ||
					personalization_status=1
			fi
		else
			gsettings set org.gnome.desktop.interface font-name \
				"$FONT_CHOICE $(desktop_font_size)" 2>/dev/null ||
				personalization_status=1
		fi
	fi
	if [[ -n $TEXT_SCALE_CHOICE &&
		(-z $PERSONALIZATION_CAPABILITY || $PERSONALIZATION_CAPABILITY == text-size) ]]; then
		if [[ $TEXT_SCALE_CHOICE == follow-system ]]; then
			if [[ $PERSONALIZATION_CAPABILITY == text-size ]]; then
				gsettings reset org.gnome.desktop.interface text-scaling-factor 2>/dev/null ||
					personalization_status=1
			fi
		else
			gsettings set org.gnome.desktop.interface text-scaling-factor \
				"$TEXT_SCALE_CHOICE" 2>/dev/null ||
				personalization_status=1
		fi
	fi
	if [[ -n $ICON_CHOICE &&
		(-z $PERSONALIZATION_CAPABILITY || $PERSONALIZATION_CAPABILITY == icon) ]]; then
		if [[ $ICON_CHOICE == follow-system ]]; then
			if [[ $PERSONALIZATION_CAPABILITY == icon ]]; then
				gsettings reset org.gnome.desktop.interface icon-theme 2>/dev/null ||
					personalization_status=1
			fi
		else
			gsettings set org.gnome.desktop.interface icon-theme "$ICON_CHOICE" 2>/dev/null ||
				personalization_status=1
		fi
	fi
	if [[ $STRICT_PERSONALIZATION == 1 && $personalization_status != 0 ]]; then
		echo 'theme-apply: personalization GSettings convergence failed' >&2
		exit 1
	fi
elif [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 &&
	$PRESERVE_DESKTOP_SETTINGS == 0 &&
	$STRICT_PERSONALIZATION == 1 && $PERSONALIZATION_CAPABILITY != qt ]]; then
	echo 'theme-apply: personalization GSettings backend became unavailable' >&2
	exit 1
fi
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 &&
	$PRESERVE_DESKTOP_SETTINGS == 0 ]] && command -v xfconf-query &>/dev/null; then
	if [[ $STRICT_PERSONALIZATION == 1 && $PERSONALIZATION_XFCONF == 1 ]]; then
		personalization_xfconf_baseline_matches || {
			echo 'theme-apply: personalization xfconf changed before the live write' >&2
			exit 1
		}
	fi
	xfconf_status=0
	if [[ -z $PERSONALIZATION_CAPABILITY ]]; then
		xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$GTK_THEME_NAME" 2>/dev/null || true
		xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s "$CURSOR_THEME" 2>/dev/null || true
		xfconf-query -c xsettings -p /Gtk/CursorThemeSize -n -t int -s "$CURSOR_SIZE" 2>/dev/null || true
	elif [[ $PERSONALIZATION_XFCONF == 1 && $PERSONALIZATION_CAPABILITY == gtk ]]; then
		xfconf-query -c xsettings -p /Net/ThemeName -n -t string -s "$GTK_THEME_NAME" 2>/dev/null ||
			xfconf_status=1
	elif [[ $PERSONALIZATION_XFCONF == 1 && $PERSONALIZATION_CAPABILITY == cursor ]]; then
		xfconf-query -c xsettings -p /Gtk/CursorThemeName -n -t string -s "$CURSOR_THEME" 2>/dev/null ||
			xfconf_status=1
	fi
	if [[ $STRICT_PERSONALIZATION == 1 && $PERSONALIZATION_XFCONF == 1 &&
		$xfconf_status != 0 ]]; then
		echo 'theme-apply: personalization xfconf convergence failed' >&2
		exit 1
	fi
fi

# Refresh only the project-owned xsettingsd instance after the transaction has
# published its staged configuration. A follow-system reset stops that instance
# and releases the XSETTINGS selection instead of pinning a generated scale.
if [[ $RUNTIME_ONLY == 0 && $TRANSACTIONAL_APPLY == 0 ]]; then
	if [[ -x $XSETTINGS_HELPER ]]; then
		if ! "$XSETTINGS_HELPER" reload >/dev/null; then
			if [[ $STRICT_PERSONALIZATION == 1 &&
				$PERSONALIZATION_CAPABILITY == text-size ]]; then
				echo 'theme-apply: personalization X11 text-scale convergence failed' >&2
				exit 1
			fi
			echo 'theme-apply: managed X11 text scaling is unavailable' >&2
		fi
	elif [[ $STRICT_PERSONALIZATION == 1 &&
		$PERSONALIZATION_CAPABILITY == text-size ]]; then
		echo 'theme-apply: managed X11 text-scale helper is unavailable' >&2
		exit 1
	fi
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
if [[ -n $QT_CHOICE && $QT_CHOICE != follow-theme ]]; then
	QT_PLATFORM_THEME=$QT_CHOICE
fi

# Write persistent env file — sourced by autostart.sh so tray apps inherit it
THEME_ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dwm-titus/theme-env.sh"
if [[ $RUNTIME_ONLY == 0 && $LIVE_ONLY == 0 ]]; then
	cat >"$THEME_ENV_FILE" <<EOF
# Auto-generated by theme-apply.sh — do not edit manually.
export QT_QPA_PLATFORMTHEME=$(shell_assignment_escape "$QT_PLATFORM_THEME")
export XCURSOR_THEME=$(shell_assignment_escape "$CURSOR_THEME")
export XCURSOR_SIZE=$(shell_assignment_escape "$CURSOR_SIZE")
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
	QT_QPA_PLATFORMTHEME=$QT_PLATFORM_THEME \
		XCURSOR_THEME=$CURSOR_THEME XCURSOR_SIZE=$CURSOR_SIZE \
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
