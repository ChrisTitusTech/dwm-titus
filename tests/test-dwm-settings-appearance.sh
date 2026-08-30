#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo/scripts/dwm-settings-appearance
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM

config_home=$work/config
data_root=$work/data
bin_dir=$work/bin
mkdir -p "$config_home/dwm-titus" "$config_home/alacritty" "$config_home/kitty" \
	"$config_home/gtk-3.0" "$config_home/gtk-4.0" \
	"$data_root/themes/Nordic/gtk-3.0" "$data_root/themes/Nordic/gtk-4.0" \
	"$data_root/icons/Capitaine-Cursors-White/cursors" "$bin_dir"
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"
declare -A fixture_color=()
while read -r key _ color; do
	fixture_color[$key]=${color//\"/}
done < <(awk '
	/^\[theme\.nord\]$/ { capture = 1; next }
	/^\[theme\./ && capture { exit }
	capture && /^[[:space:]]*term_/ { print }
' "$repo/config/themes.toml")
cat >"$config_home/alacritty/active-theme.toml" <<EOF
[colors.primary]
background = '${fixture_color[term_bg]}'
foreground = '${fixture_color[term_fg]}'
[colors.cursor]
text = '${fixture_color[term_bg]}'
cursor = '${fixture_color[term_cursor]}'
[colors.normal]
black = '${fixture_color[term_color0]}'
red = '${fixture_color[term_color1]}'
green = '${fixture_color[term_color2]}'
yellow = '${fixture_color[term_color3]}'
blue = '${fixture_color[term_color4]}'
magenta = '${fixture_color[term_color5]}'
cyan = '${fixture_color[term_color6]}'
white = '${fixture_color[term_color7]}'
[colors.bright]
black = '${fixture_color[term_color8]}'
red = '${fixture_color[term_color9]}'
green = '${fixture_color[term_color10]}'
yellow = '${fixture_color[term_color11]}'
blue = '${fixture_color[term_color12]}'
magenta = '${fixture_color[term_color13]}'
cyan = '${fixture_color[term_color14]}'
white = '${fixture_color[term_color15]}'
EOF
cat >"$config_home/kitty/active-theme.conf" <<EOF
background ${fixture_color[term_bg]}
foreground ${fixture_color[term_fg]}
cursor ${fixture_color[term_cursor]}
color0 ${fixture_color[term_color0]}
color1 ${fixture_color[term_color1]}
color2 ${fixture_color[term_color2]}
color3 ${fixture_color[term_color3]}
color4 ${fixture_color[term_color4]}
color5 ${fixture_color[term_color5]}
color6 ${fixture_color[term_color6]}
color7 ${fixture_color[term_color7]}
color8 ${fixture_color[term_color8]}
color9 ${fixture_color[term_color9]}
color10 ${fixture_color[term_color10]}
color11 ${fixture_color[term_color11]}
color12 ${fixture_color[term_color12]}
color13 ${fixture_color[term_color13]}
color14 ${fixture_color[term_color14]}
color15 ${fixture_color[term_color15]}
EOF
cp "$config_home/alacritty/active-theme.toml" "$work/alacritty-valid.toml"
cp "$config_home/kitty/active-theme.conf" "$work/kitty-valid.conf"
printf 'import = ["%s"]\n' "$config_home/alacritty/active-theme.toml" \
	>"$config_home/alacritty/alacritty.toml"

printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors-White\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
printf 'Xcursor.theme: Capitaine-Cursors-White\n' \
	>"$config_home/dwm-titus/cursor.Xresources"
printf '  [Settings]  \ngtk-theme-name=Nordic\ngtk-cursor-theme-name=Capitaine-Cursors-White\n' \
	>"$config_home/gtk-3.0/settings.ini"
printf '[Settings]\ngtk-theme-name=Nordic\ngtk-cursor-theme-name=Capitaine-Cursors-White\n' \
	>"$config_home/gtk-4.0/settings.ini"
printf 'include active-theme.conf\n' >"$config_home/kitty/kitty.conf"

for command_name in awk bash dirname grep stat tr; do
	ln -s "$(command -v "$command_name")" "$bin_dir/$command_name"
done
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/qt6ct"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/picom"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/alacritty"
printf '#!/bin/sh\nexit 0\n' >"$bin_dir/kitty"
chmod +x "$bin_dir/qt6ct" "$bin_dir/picom" "$bin_dir/alacritty" "$bin_dir/kitty"

hash_config_home=$work/config#hash
cp -a "$config_home" "$hash_config_home"
printf 'import = ["%s"] # active palette\n' \
	"$hash_config_home/alacritty/active-theme.toml" \
	>"$hash_config_home/alacritty/alacritty.toml"
hash_path=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$hash_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$hash_path"

escaped_config_home=$work/config\\escaped
cp -a "$config_home" "$escaped_config_home"
escaped_active_path=$escaped_config_home/alacritty/active-theme.toml
encoded_active_path=${escaped_active_path//\\/\\\\}
printf 'import = ["%s"]\n' "$encoded_active_path" \
	>"$escaped_config_home/alacritty/alacritty.toml"
escaped_path=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$escaped_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$escaped_path"

fresh_home=$work/fresh-home
fresh_config_home=$fresh_home/.config
mkdir -p "$fresh_home"
cp -a "$config_home" "$fresh_config_home"
cp "$repo/config/alacritty/alacritty.toml" "$fresh_config_home/alacritty/alacritty.toml"
fresh_install=$(HOME=$fresh_home PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$fresh_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$fresh_install"

spaced_config_home=$work/config-spaced
cp -a "$config_home" "$spaced_config_home"
printf '[ general ]\nimport = ["%s"]\n' "$spaced_config_home/alacritty/active-theme.toml" \
	>"$spaced_config_home/alacritty/alacritty.toml"
spaced_header=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$spaced_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$spaced_header"

double_quoted_config_home=$work/config-double-quoted
cp -a "$config_home" "$double_quoted_config_home"
printf '["general"]\nimport = ["%s"]\n' \
	"$double_quoted_config_home/alacritty/active-theme.toml" \
	>"$double_quoted_config_home/alacritty/alacritty.toml"
double_quoted_header=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$double_quoted_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$double_quoted_header"

single_quoted_config_home=$work/config-single-quoted
cp -a "$config_home" "$single_quoted_config_home"
printf "['general']\nimport = [\"%s\"]\n" \
	"$single_quoted_config_home/alacritty/active-theme.toml" \
	>"$single_quoted_config_home/alacritty/alacritty.toml"
single_quoted_header=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$single_quoted_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$single_quoted_header"

quoted_import_config_home=$work/config-quoted-import
cp -a "$config_home" "$quoted_import_config_home"
printf '[general]\n"import" = ["%s"]\n' \
	"$quoted_import_config_home/alacritty/active-theme.toml" \
	>"$quoted_import_config_home/alacritty/alacritty.toml"
quoted_import=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$quoted_import_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$quoted_import"

quoted_dotted_config_home=$work/config-quoted-dotted
cp -a "$config_home" "$quoted_dotted_config_home"
printf "'general' . 'import' = [\"%s\"]\n" \
	"$quoted_dotted_config_home/alacritty/active-theme.toml" \
	>"$quoted_dotted_config_home/alacritty/alacritty.toml"
quoted_dotted=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$quoted_dotted_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$quoted_dotted"

dotted_config_home=$work/config-dotted
cp -a "$config_home" "$dotted_config_home"
printf 'general . import = ["%s"]\n' "$dotted_config_home/alacritty/active-theme.toml" \
	>"$dotted_config_home/alacritty/alacritty.toml"
dotted_key=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$dotted_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$dotted_key"

snapshot() {
	PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
		DWM_APPEARANCE_DATA_DIRS=$data_root \
		"$helper" snapshot
}

before_hash=$(sha256sum "$config_home/dwm-titus/themes.toml")
before_mode=$(stat -c %a "$config_home/dwm-titus/themes.toml")
output=$(snapshot)
after_hash=$(sha256sum "$config_home/dwm-titus/themes.toml")
after_mode=$(stat -c %a "$config_home/dwm-titus/themes.toml")
[[ $before_hash == "$after_hash" && $before_mode == "$after_mode" ]]

grep -Fqx $'appearance-protocol\t1\t0' <<<"$output"
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' <<<"$output"
grep -Fqx $'source\tuser\t'"$config_home/dwm-titus/themes.toml" <<<"$output"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$output"
grep -Fqx $'theme\tnord\tselected\tvalid\ttrue\tNordic\tTheme record is complete' <<<"$output"
[[ $(grep -c $'^theme\t' <<<"$output") -eq 15 ]]
grep -Fqx $'color\tbackground\t#2E3440\tterm_bg' <<<"$output"
grep -Fqx $'color\taccent\t#81A1C1\tselbordercolor' <<<"$output"
grep -Fqx $'color\tdanger\t#BF616A\tterm_color1' <<<"$output"
grep -Fqx $'integration\tgtk\tavailable\tNordic\tRequested GTK theme is installed and applied' <<<"$output"
grep -Fqx $'integration\tqt\tavailable\tqt6ct\tQt applications use the supported theme backend' <<<"$output"
grep -Fqx $'integration\tcursor\tavailable\tCapitaine-Cursors-White\tManaged cursor theme is installed and applied' <<<"$output"
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' <<<"$output"
grep -Fqx $'integration\tkitty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' <<<"$output"
grep -Fqx $'integration\tcompositor\tpartial\tpicom\tPicom is available but has no shared theme mutation contract' <<<"$output"
grep -Fqx $'error\tcompositor\tunsupported\tPicom theme mutation is not implemented' <<<"$output"

no_picom_bin=$work/no-picom-bin
cp -a "$bin_dir" "$no_picom_bin"
rm -f "$no_picom_bin/picom"
missing_picom=$(PATH=$no_picom_bin GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$missing_picom"
grep -Fqx $'integration\tgtk\tavailable\tNordic\tRequested GTK theme is installed and applied' \
	<<<"$missing_picom"
grep -Fqx $'integration\tqt\tavailable\tqt6ct\tQt applications use the supported theme backend' \
	<<<"$missing_picom"
grep -Fqx $'integration\tcursor\tavailable\tCapitaine-Cursors-White\tManaged cursor theme is installed and applied' \
	<<<"$missing_picom"
grep -Fqx $'integration\talacritty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$missing_picom"
grep -Fqx $'integration\tkitty\tavailable\tactive-theme\tGenerated terminal theme matches the resolved palette' \
	<<<"$missing_picom"
grep -Fqx $'integration\tcompositor\tunavailable\tmissing\tPicom is optional and not installed' \
	<<<"$missing_picom"

printf '[window]\nimport = ["%s"]\n' "$config_home/alacritty/active-theme.toml" \
	>"$config_home/alacritty/alacritty.toml"
table_import_alacritty=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$table_import_alacritty"

nested_dotted_config_home=$work/config-nested-dotted
cp -a "$config_home" "$nested_dotted_config_home"
printf '[general]\ngeneral.import = ["%s"]\n' \
	"$nested_dotted_config_home/alacritty/active-theme.toml" \
	>"$nested_dotted_config_home/alacritty/alacritty.toml"
nested_dotted_import=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$nested_dotted_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$nested_dotted_import"

legacy_precedence_config_home=$work/config-legacy-precedence
cp -a "$config_home" "$legacy_precedence_config_home"
printf 'import = ["%s"]\n[general]\nimport = ["%s"]\n' \
	"$legacy_precedence_config_home/alacritty/legacy-theme.toml" \
	"$legacy_precedence_config_home/alacritty/active-theme.toml" \
	>"$legacy_precedence_config_home/alacritty/alacritty.toml"
legacy_precedence=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$legacy_precedence_config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot)
grep -Fqx $'integration\talacritty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$legacy_precedence"

printf 'import = "%s"\n' "$config_home/alacritty/active-theme.toml" \
	>"$config_home/alacritty/alacritty.toml"
scalar_import_alacritty=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$scalar_import_alacritty"
printf 'import = ["%s"]\n' "$config_home/alacritty/active-theme.toml" \
	>"$config_home/alacritty/alacritty.toml"

no_kitty_bin=$work/no-kitty-bin
cp -a "$bin_dir" "$no_kitty_bin"
rm -f "$no_kitty_bin/kitty"
no_kitty=$(PATH=$no_kitty_bin GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root "$helper" snapshot)
grep -Fqx $'integration\tkitty\tunavailable\tmissing-application\tTerminal application is not installed' \
	<<<"$no_kitty"
grep -Fqx $'error\tkitty\tmissing-application\tTerminal application is not installed' \
	<<<"$no_kitty"

cp "$config_home/dwm-titus/themes.toml" "$work/replacement-themes.toml"
sed -i '0,/theme = "nord"/s//theme = "dracula"/' "$work/replacement-themes.toml"
real_awk=$(command -v awk)
real_mv=$(command -v mv)
rm -f "$bin_dir/awk"
cat >"$bin_dir/awk" <<'EOF'
#!/bin/sh
if [ ! -e "$DWM_TEST_REPLACED_MARKER" ]; then
	"$DWM_TEST_REAL_MV" "$DWM_TEST_REPLACEMENT" "$DWM_TEST_REPLACEMENT_TARGET"
	: >"$DWM_TEST_REPLACED_MARKER"
fi
exec "$DWM_TEST_REAL_AWK" "$@"
EOF
chmod +x "$bin_dir/awk"
immutable_snapshot=$(PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root DWM_TEST_REAL_AWK="$real_awk" \
	DWM_TEST_REAL_MV="$real_mv" \
	DWM_TEST_REPLACEMENT="$work/replacement-themes.toml" \
	DWM_TEST_REPLACEMENT_TARGET="$config_home/dwm-titus/themes.toml" \
	DWM_TEST_REPLACED_MARKER="$work/replaced.marker" "$helper" snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$immutable_snapshot"
grep -Fq 'theme = "dracula"' "$config_home/dwm-titus/themes.toml"
rm -f "$bin_dir/awk"
ln -s "$real_awk" "$bin_dir/awk"
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"

no_qt_bin=$work/no-qt-bin
cp -a "$bin_dir" "$no_qt_bin"
rm -f "$no_qt_bin/qt6ct"
mv "$config_home/dwm-titus/theme-env.sh" "$work/theme-env.sh"
no_qt=$(PATH=$no_qt_bin QT_QPA_PLATFORMTHEME='' XDG_CONFIG_HOME=$config_home \
	XDG_DATA_HOME=$data_root DWM_APPEARANCE_DATA_DIRS=$data_root \
	"$helper" snapshot)
grep -Fqx $'integration\tqt\tunavailable\tnone\tNo supported Qt theme backend is active' <<<"$no_qt"
grep -Fqx $'error\tqt\tmissing-backend\tNo applied Qt theme backend is recorded' \
	<<<"$no_qt"
mv "$work/theme-env.sh" "$config_home/dwm-titus/theme-env.sh"

mv "$config_home/dwm-titus/theme-env.sh" "$work/theme-env-regular.sh"
mkfifo "$config_home/dwm-titus/theme-env.sh"
timeout 3 env PATH="$bin_dir" GTK_THEME='' \
	QT_QPA_PLATFORMTHEME=qt6ct XCURSOR_THEME=Capitaine-Cursors-White \
	XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot \
	>"$work/special-theme-env.out"
grep -Fqx $'integration\tqt\tavailable\tqt6ct\tQt applications use the supported theme backend' \
	"$work/special-theme-env.out"
rm "$config_home/dwm-titus/theme-env.sh"
mv "$work/theme-env-regular.sh" "$config_home/dwm-titus/theme-env.sh"

gtk3_qt=$(QT_QPA_PLATFORMTHEME=gtk3 snapshot)
grep -Fqx $'integration\tqt\tavailable\tqt6ct\tQt applications use the supported theme backend' \
	<<<"$gtk3_qt"

for malformed_environment in unknown duplicate missing-size; do
	case $malformed_environment in
	unknown)
		printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors-White\nexport XCURSOR_SIZE=32\nexport CUSTOM_VALUE=yes\n' \
			>"$config_home/dwm-titus/theme-env.sh"
		;;
	duplicate)
		printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport QT_QPA_PLATFORMTHEME=gtk3\nexport XCURSOR_THEME=Capitaine-Cursors-White\nexport XCURSOR_SIZE=32\n' \
			>"$config_home/dwm-titus/theme-env.sh"
		;;
	missing-size)
		printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors-White\n' \
			>"$config_home/dwm-titus/theme-env.sh"
		;;
	esac
	malformed_snapshot=$(QT_QPA_PLATFORMTHEME=gtk3 \
		XCURSOR_THEME=Capitaine-Cursors-White snapshot)
	grep -Fqx $'integration\tqt\tavailable\tgtk3\tQt applications use the supported theme backend' \
		<<<"$malformed_snapshot"
done
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors-White\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"

printf 'personalization-protocol\t1\t0\ngtk\tfollow-system\n' \
	>"$config_home/dwm-titus/personalization.conf"
invalid_gtk_override=$(snapshot)
grep -Fqx $'integration\tgtk\tavailable\tNordic\tRequested GTK theme is installed and applied' \
	<<<"$invalid_gtk_override"
if grep -F $'integration\tgtk\tpartial\tfollow-system\t' <<<"$invalid_gtk_override"; then
	printf 'semantically invalid GTK personalization was reported as active\n' >&2
	exit 1
fi
rm -f "$config_home/dwm-titus/personalization.conf"

home_cursor_root=$work/home-cursor
mkdir -p "$home_cursor_root/.icons/Cursor One/cursors"
printf 'personalization-protocol\t1\t0\ncursor\tCursor One\n' \
	>"$config_home/dwm-titus/personalization.conf"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Cursor\\ One\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
printf 'Xcursor.theme: Cursor One\n' >"$config_home/dwm-titus/cursor.Xresources"
sed -i 's/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Cursor One/' \
	"$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"
spaced_cursor=$(HOME=$home_cursor_root snapshot)
grep -Fqx $'integration\tcursor\tavailable\tCursor One\tManaged cursor theme is installed and applied' \
	<<<"$spaced_cursor"
stale_environment_cursor=$(HOME=$home_cursor_root PATH=$bin_dir GTK_THEME='' XCURSOR_THEME='Old Cursor' \
	XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root "$helper" snapshot)
grep -Fqx $'integration\tcursor\tavailable\tCursor One\tManaged cursor theme is installed and applied' \
	<<<"$stale_environment_cursor"
mkdir -p "$data_root/icons/IconOnly"
printf 'personalization-protocol\t1\t0\ncursor\tIconOnly\n' \
	>"$config_home/dwm-titus/personalization.conf"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=IconOnly\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
printf 'Xcursor.theme: IconOnly\n' >"$config_home/dwm-titus/cursor.Xresources"
sed -i 's/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=IconOnly/' \
	"$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"
icon_only_cursor=$(HOME=$home_cursor_root snapshot)
grep -Fqx $'integration\tcursor\tunavailable\tIconOnly\tManaged cursor theme is missing' \
	<<<"$icon_only_cursor"
grep -Fqx $'error\tcursor\tmissing-theme\tCursor theme '\''IconOnly'\'' is not installed' \
	<<<"$icon_only_cursor"
rm -f "$config_home/dwm-titus/personalization.conf"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Capitaine-Cursors-White\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
printf 'Xcursor.theme: Capitaine-Cursors-White\n' \
	>"$config_home/dwm-titus/cursor.Xresources"
sed -i 's/gtk-cursor-theme-name=.*/gtk-cursor-theme-name=Capitaine-Cursors-White/' \
	"$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"

sed -i 's/XCURSOR_THEME=Capitaine-Cursors-White/XCURSOR_THEME=Capitaine-Cursors/' \
	"$config_home/dwm-titus/theme-env.sh"
stale_cursor=$(snapshot)
grep -Fqx $'integration\tcursor\tpartial\tCapitaine-Cursors-White\tManaged cursor theme is installed but not applied' \
	<<<"$stale_cursor"
grep -Fqx $'error\tcursor\tstale-theme\tApplied cursor settings do not match '\''Capitaine-Cursors-White'\''' \
	<<<"$stale_cursor"
sed -i 's/XCURSOR_THEME=Capitaine-Cursors/XCURSOR_THEME=Capitaine-Cursors-White/' \
	"$config_home/dwm-titus/theme-env.sh"

printf 'import = ["/wrong/active-theme.toml"]\n' >"$config_home/alacritty/alacritty.toml"
unimported_alacritty=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$unimported_alacritty"
grep -Fqx $'error\talacritty\tnot-imported\tTerminal configuration does not import the generated active theme' \
	<<<"$unimported_alacritty"
printf 'import = ["%s"]\n' "$config_home/alacritty/active-theme.toml" \
	>"$config_home/alacritty/alacritty.toml"

printf '# include active-theme.conf\n' >"$config_home/kitty/kitty.conf"
unimported_kitty=$(snapshot)
grep -Fqx $'integration\tkitty\tpartial\tconfiguration\tGenerated theme is not imported by the terminal configuration' \
	<<<"$unimported_kitty"
grep -Fqx $'error\tkitty\tnot-imported\tTerminal configuration does not import the generated active theme' \
	<<<"$unimported_kitty"
printf 'include active-theme.conf\n' >"$config_home/kitty/kitty.conf"

sed -i '/^text =/d' "$config_home/alacritty/active-theme.toml"
missing_cursor_text=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tactive-theme\tGenerated terminal theme is empty or stale' \
	<<<"$missing_cursor_text"
cp "$work/alacritty-valid.toml" "$config_home/alacritty/active-theme.toml"

sed -i "s|${fixture_color[term_bg]}|__DWM_COLOR_SWAP__|; \
	s|${fixture_color[term_fg]}|${fixture_color[term_bg]}|; \
	s|__DWM_COLOR_SWAP__|${fixture_color[term_fg]}|" \
	"$config_home/alacritty/active-theme.toml"
swapped_terminal=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tactive-theme\tGenerated terminal theme is empty or stale' \
	<<<"$swapped_terminal"
cp "$work/alacritty-valid.toml" "$config_home/alacritty/active-theme.toml"

: >"$config_home/alacritty/active-theme.toml"
stale_terminal=$(snapshot)
grep -Fqx $'integration\talacritty\tpartial\tactive-theme\tGenerated terminal theme is empty or stale' \
	<<<"$stale_terminal"
grep -Fqx $'error\talacritty\tstale-theme\tGenerated active theme does not match the resolved palette' \
	<<<"$stale_terminal"
cp "$work/alacritty-valid.toml" "$config_home/alacritty/active-theme.toml"

sed -i 's/^\[active\]$/[active] # selected theme/' "$config_home/dwm-titus/themes.toml"
sed -i 's/^\[theme\.nord\]$/[theme.nord] # default theme/' "$config_home/dwm-titus/themes.toml"
commented_headers=$(snapshot)
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$commented_headers"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$commented_headers"
grep -Fqx $'theme\tnord\tselected\tvalid\ttrue\tNordic\tTheme record is complete' \
	<<<"$commented_headers"
if grep -Fq $'error\tparser\tmalformed-section\t' <<<"$commented_headers"; then
	printf 'Valid commented section header was rejected\n' >&2
	exit 1
fi
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"

sed -i 's/^\[theme\.dracula\]$/[theme.dracula] trailing/' "$config_home/dwm-titus/themes.toml"
malformed_header=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$malformed_header"
grep -Fq $'error\tparser\tmalformed-section\tMalformed theme section header at line ' \
	<<<"$malformed_header"
if grep -Fq $'theme\tdracula\t' <<<"$malformed_header"; then
	printf 'Malformed theme section was inventoried\n' >&2
	exit 1
fi

cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i 's/^\[active\]$/[active/' "$config_home/dwm-titus/themes.toml"
truncated_header=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$truncated_header"
grep -Fqx $'active\tnone\tnord\trecovery' <<<"$truncated_header"
grep -Fq $'error\tparser\tmalformed-section\tMalformed theme section header at line ' \
	<<<"$truncated_header"
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"

{
	printf '%s\n' '[ignored]' 'extra = [{x="a=b"}, {x='"'"'c=d'"'"'}] # ignored = comment'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
inline_table=$(snapshot)
inline_table_status=$?
set -e
[[ $inline_table_status -eq 0 ]]
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$inline_table"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$inline_table"

{
	printf '[ignored]\nextra = {x=1}\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
direct_inline_table=$(snapshot)
direct_inline_table_status=$?
set -e
[[ $direct_inline_table_status -eq 0 ]]
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$direct_inline_table"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$direct_inline_table"

{
	printf '[ignored]\nextra = ["one", "two"]\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
scalar_array=$(snapshot)
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$scalar_array"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$scalar_array"

{
	printf '[ignored]\nextra = [\n  {x=1},\n  {x=2}\n]\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
multiline_array=$(snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$multiline_array"

{
	printf '[ignored]\nextra = [\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
unterminated_array=$(snapshot)
unterminated_array_status=$?
set -e
[[ $unterminated_array_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$unterminated_array"
grep -Fqx $'error\tparser\tunterminated-complex-value\tAn unrelated multi-line array was not terminated before the end of the theme configuration' \
	<<<"$unterminated_array"

{
	printf '[ignored]\nextra = [\n  {x=1}, {x=2}]\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
runtime_stuck_array=$(snapshot)
runtime_stuck_array_status=$?
set -e
[[ $runtime_stuck_array_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$runtime_stuck_array"
grep -Fqx $'error\tparser\tunterminated-complex-value\tAn unrelated multi-line array was not terminated before the end of the theme configuration' \
	<<<"$runtime_stuck_array"
if grep -Fq $'theme\tnord\t' <<<"$runtime_stuck_array"; then
	printf 'Provider parsed a theme section hidden by the runtime multi-line array state\n' >&2
	exit 1
fi
for runtime_array_snapshot in "$inline_table" "$direct_inline_table" "$scalar_array" \
	"$multiline_array" "$unterminated_array" "$runtime_stuck_array"; do
	if grep -Fq $'error\tparser\tunsupported-complex-value\t' <<<"$runtime_array_snapshot"; then
		printf 'Runtime-compatible unrelated array retained a superseded parser diagnostic\n' >&2
		exit 1
	fi
done

{
	printf '[ignored]\nextra = [\n'
	for ((nested_index = 0; nested_index < 257; nested_index++)); do
		printf '  {outer={inner="x"}},\n'
	done
	printf ']\n'
	cat "$repo/config/themes.toml"
} >"$config_home/dwm-titus/themes.toml"
nested_inline_tables=$(snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$nested_inline_tables"
grep -Fqx $'error\tparser\tentry-limit\tTheme configuration exceeds the runtime parser limit of 512 entries' \
	<<<"$nested_inline_tables"
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"

printf '\n[theme.@unsafe]\nterm_bg = "#000000"\n' >>"$config_home/dwm-titus/themes.toml"
unsafe_name=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$unsafe_name"
grep -Fq $'error\tparser\tinvalid-theme-name\tTheme name is not a supported bare identifier at line ' \
	<<<"$unsafe_name"
if grep -Fq $'theme\t@unsafe\t' <<<"$unsafe_name"; then
	printf 'Unsafe theme identifier was inventoried\n' >&2
	exit 1
fi
cp "$repo/config/themes.toml" "$config_home/dwm-titus/themes.toml"

rmdir "$data_root/themes/Nordic/gtk-4.0"
partial_gtk_assets=$(snapshot)
grep -Fqx $'integration\tgtk\tpartial\tNordic\tRequested GTK theme is missing GTK 3 or GTK 4 assets' \
	<<<"$partial_gtk_assets"
grep -Fqx $'error\tgtk\tmissing-version\tGTK theme '\''Nordic'\'' does not support both GTK 3 and GTK 4' \
	<<<"$partial_gtk_assets"
rmdir "$data_root/themes/Nordic/gtk-3.0"
missing_gtk=$(snapshot)
grep -Fqx $'integration\tgtk\tpartial\tNordic\tRequested GTK theme is missing; apply falls back to Adwaita-dark' <<<"$missing_gtk"
grep -Fqx $'error\tgtk\tmissing-theme\tGTK theme '\''Nordic'\'' is not installed' <<<"$missing_gtk"
mkdir -p "$data_root/themes/Nordic/gtk-3.0" "$data_root/themes/Nordic/gtk-4.0"

sed -i 's/gtk-theme-name=Nordic/gtk-theme-name=Adwaita/' \
	"$config_home/gtk-4.0/settings.ini"
stale_gtk_application=$(snapshot)
grep -Fqx $'integration\tgtk\tpartial\tNordic\tRequested GTK theme is installed but not applied' \
	<<<"$stale_gtk_application"
grep -Fqx $'error\tgtk\tstale-theme\tApplied GTK settings do not match '\''Nordic'\''' \
	<<<"$stale_gtk_application"
sed -i 's/gtk-theme-name=Adwaita/gtk-theme-name=Nordic/' \
	"$config_home/gtk-4.0/settings.ini"

mv "$config_home/dwm-titus/themes.toml" "$work/managed-themes.toml"
managed=$(PATH=$bin_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_MANAGED_THEMES_FILE="$work/managed-themes.toml" \
	"$helper" snapshot)
grep -Fqx $'source\tmanaged\t'"$work/managed-themes.toml" <<<"$managed"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$managed"

mkdir -p "$data_root/dwm-titus/config"
cp "$work/managed-themes.toml" "$data_root/dwm-titus/config/themes.toml"
installed_managed=$(PATH=$bin_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root "$helper" snapshot)
grep -Fqx $'source\tmanaged\t'"$data_root/dwm-titus/config/themes.toml" <<<"$installed_managed"

mkdir "$config_home/dwm-titus/themes.toml"
set +e
blocked_user=$(snapshot)
blocked_user_status=$?
set -e
[[ $blocked_user_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$blocked_user"
grep -Fqx $'source\tuser\t'"$config_home/dwm-titus/themes.toml" <<<"$blocked_user"
grep -Fqx $'active\tnone\tnone\tunresolved' <<<"$blocked_user"
grep -Fq $'error\tsource\tunreadable\tUser theme file is not a readable regular file: ' \
	<<<"$blocked_user"
rmdir "$config_home/dwm-titus/themes.toml"

ln -s "$work/missing-user-theme.toml" "$config_home/dwm-titus/themes.toml"
dangling_user=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$dangling_user"
grep -Fqx $'source\tmanaged\t'"$data_root/dwm-titus/config/themes.toml" <<<"$dangling_user"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$dangling_user"
grep -Fq $'error\tsource\tdangling-user\tIgnoring dangling user theme symlink and trying the managed source: ' \
	<<<"$dangling_user"
rm -f "$config_home/dwm-titus/themes.toml"

custom_theme=-custom_theme_with_a_name_that_is_longer_than_sixty_four_characters_1234567890
cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i "0,/theme = \"nord\"/s//theme = \"$custom_theme\"/" "$config_home/dwm-titus/themes.toml"
sed -i "0,/^\[theme\.nord\]$/s//[theme.$custom_theme]/" "$config_home/dwm-titus/themes.toml"
custom=$(snapshot)
grep -Fqx $'active\t'"$custom_theme"$'\t'"$custom_theme"$'\tselected' <<<"$custom"
grep -Fq $'theme\t'"$custom_theme"$'\tselected\tvalid\ttrue\tNordic' <<<"$custom"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/theme = "nord"/s//theme = "no\\rd"/' \
	"$config_home/dwm-titus/themes.toml"
escaped_active=$(snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$escaped_active"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
em_space=$'\u2003'
sed -i "0,/^\[active\]$/s//${em_space}[active]/; 0,/^theme =/s//${em_space}theme =/" \
	"$config_home/dwm-titus/themes.toml"
unicode_space=$(snapshot)
grep -Fqx $'active\tnone\tnord\trecovery' <<<"$unicode_space"
grep -Fqx $'error\tactive\tmissing\tThe active theme name is missing' <<<"$unicode_space"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/theme = "nord"/s//theme = 123/' "$config_home/dwm-titus/themes.toml"
numeric_active=$(snapshot)
grep -Fqx $'active\tnone\tnord\trecovery' <<<"$numeric_active"
grep -Fq $'error\tactive\tinvalid-type\tActive theme must resolve to a TOML string at line ' \
	<<<"$numeric_active"

sed -i '0,/theme = 123/s//theme = 123\n theme = "nord"/' \
	"$config_home/dwm-titus/themes.toml"
duplicate_after_numeric=$(snapshot)
grep -Fqx $'active\tnone\tnord\trecovery' <<<"$duplicate_after_numeric"
grep -Fq $'error\tactive:__active\tduplicate-key\tDuplicate key '\''theme'\'' at line ' \
	<<<"$duplicate_after_numeric"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '/^gtk_theme[[:space:]]*=/a author-name = "demo"' \
	"$config_home/dwm-titus/themes.toml"
metadata_key=$(snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$metadata_key"
if grep -Fq $'error\ttheme:nord\tinvalid-record\t' <<<"$metadata_key"; then
	printf 'Runtime-valid metadata invalidated the active theme\n' >&2
	exit 1
fi

printf -v overlong_theme '%*s' 506 ''
overlong_theme=${overlong_theme// /a}
cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i "0,/theme = \"nord\"/s//theme = \"$overlong_theme\"/" "$config_home/dwm-titus/themes.toml"
sed -i "0,/^\[theme\.nord\]$/s//[theme.$overlong_theme]/" "$config_home/dwm-titus/themes.toml"
overlong=$(snapshot)
grep -Fqx $'active\t'"$overlong_theme"$'\tdracula\trecovery' <<<"$overlong"
grep -Fq $'error\tparser\tinvalid-theme-name\tTheme name is not a supported bare identifier at line ' \
	<<<"$overlong"

cat >"$config_home/dwm-titus/themes.toml" <<EOF
[active]
theme = "$overlong_theme"
[colors]
normfgcolor = "#D8DEE9"
normbgcolor = "#2E3440"
normbordercolor = "#4C566A"
selfgcolor = "#ECEFF4"
selbgcolor = "#5E81AC"
selbordercolor = "#81A1C1"
EOF
overlong_legacy=$(snapshot)
grep -Fqx $'active\t'"$overlong_theme"$'\t@legacy-colors\trecovery' <<<"$overlong_legacy"
grep -Fqx $'error\tactive\tname-too-long\tActive theme name exceeds the runtime section limit; using the legacy [colors] palette' \
	<<<"$overlong_legacy"

{
	printf '[ignored]\nmetadata = "'
	printf '%4095s' '' | tr ' ' x
	printf '"\n'
	cat "$work/managed-themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
long_line=$(snapshot)
long_line_status=$?
set -e
[[ $long_line_status -eq 3 ]]
grep -Fqx $'error\tparser\tline-too-long\tTheme configuration contains a physical line that exceeds the runtime reader limit' \
	<<<"$long_line"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/theme = "nord"/s//theme = "dracula"/' "$config_home/dwm-titus/themes.toml"
sed -i 's/gtk-theme-name=Nordic/gtk-theme-name=Adwaita-dark/' \
	"$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"
adwaita=$(snapshot)
grep -Fqx $'integration\tgtk\tavailable\tAdwaita-dark\tRequested GTK theme is installed and applied' <<<"$adwaita"
if grep -Fq $'error\tgtk\tmissing-theme' <<<"$adwaita"; then
	printf 'Built-in Adwaita fallback was reported missing\n' >&2
	exit 1
fi
sed -i 's/gtk-theme-name=Adwaita-dark/gtk-theme-name=Nordic/' \
	"$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/theme = "nord"/s//theme = "missing"/' "$config_home/dwm-titus/themes.toml"
unknown=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' <<<"$unknown"
grep -Fqx $'active\tmissing\tnord\trecovery' <<<"$unknown"
grep -Fqx $'error\tactive\tunknown\tActive theme '\''missing'\'' is not defined' <<<"$unknown"
grep -Fqx $'color\tbackground\t#434C5E\tterm_bg' <<<"$unknown"
grep -Fqx $'color\tbar-background\t#434C5E\tnormbgcolor' <<<"$unknown"
grep -Fqx $'color\taccent\t#81A1C1\tselbordercolor' <<<"$unknown"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
printf '\n[theme.nord]\nterm_bg = "#000000"\n' >>"$config_home/dwm-titus/themes.toml"
duplicate=$(snapshot)
grep -Fqx $'active\tnord\tnord\trecovery' <<<"$duplicate"
grep -Fq $'error\ttheme:nord\tduplicate\tDuplicate theme section at line ' <<<"$duplicate"
grep -Fqx $'theme\tnord\tselected\tinvalid\ttrue\tNordic\tTheme record is duplicate, malformed, or incomplete' <<<"$duplicate"
grep -Fqx $'color\tbackground\t#2E3440\tterm_bg' <<<"$duplicate"

cat >"$config_home/dwm-titus/themes.toml" <<'EOF'
[active]
theme = "nord"

[theme.nord]
normfgcolor = "#D8DEE9"
normbgcolor = "#434C5E"
normbordercolor = "#3B4252"

[theme.nord]
selfgcolor = "#ECEFF4"
selbgcolor = "#434C5E"
selbordercolor = "#81A1C1"
normbgcolor = "#FFFFFF"
EOF
split_duplicate=$(snapshot)
grep -Fqx $'active\tnord\tnord\trecovery' <<<"$split_duplicate"
grep -Fqx $'color\tbar-background\t#434C5E\tnormbgcolor' <<<"$split_duplicate"
grep -Fqx $'color\tplaceholder\t#D8DEE9\tterm_color8' <<<"$split_duplicate"
grep -Fqx $'color\tsuccess\t#81A1C1\tterm_color2' <<<"$split_duplicate"
[[ $(grep -Ec $'^color\t[^\t]+\t#[0-9A-Fa-f]{6}\t' <<<"$split_duplicate") -eq 18 ]]

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/theme = "nord"/s//theme = "broken"/' "$config_home/dwm-titus/themes.toml"
printf '\n[theme.broken]\ndark_mode = true\n' >>"$config_home/dwm-titus/themes.toml"
incomplete=$(snapshot)
grep -Fqx $'active\tbroken\tnord\trecovery' <<<"$incomplete"
grep -Fqx $'color\tbackground\t#434C5E\tterm_bg' <<<"$incomplete"
grep -Fqx $'error\ttheme:broken\tmissing-key\tTheme is missing 25 required keys; first missing key is '\''normfgcolor'\''' <<<"$incomplete"
grep -Fqx $'error\tactive\tinvalid\tActive theme '\''broken'\'' is invalid or incomplete' <<<"$incomplete"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i '0,/normfgcolor     = "#D8DEE9"/s//normfgcolor     = "not-a-color"/' \
	"$config_home/dwm-titus/themes.toml"
invalid_color=$(snapshot)
grep -Fqx $'active\tnord\tdracula\trecovery' <<<"$invalid_color"
grep -Fqx $'color\tbackground\t#2E3440\tterm_bg' <<<"$invalid_color"
grep -Fqx $'error\ttheme:nord\tinvalid-color\tTheme key '\''normfgcolor'\'' is not a #RRGGBB color' <<<"$invalid_color"

cp "$work/managed-themes.toml" "$config_home/dwm-titus/themes.toml"
sed -i $'0,/dark_mode       = true/s//dark_mode       = "bogus\tvalue"/' \
	"$config_home/dwm-titus/themes.toml"
invalid_dark=$(snapshot)
grep -Fqx $'theme\tnord\tselected\tinvalid\tbogus value\tNordic\tTheme record is duplicate, malformed, or incomplete' \
	<<<"$invalid_dark"
grep -Fqx $'error\ttheme:nord\tinvalid-dark-mode\tTheme dark_mode must be true or false' \
	<<<"$invalid_dark"

{
	printf '[ignored]\n'
	for ((entry_index = 0; entry_index < 512; entry_index++)); do
		printf 'extra-%s = 1\n' "$entry_index"
	done
	cat "$work/managed-themes.toml"
} >"$config_home/dwm-titus/themes.toml"
set +e
alternate_key_limit=$(snapshot)
alternate_key_status=$?
set -e
[[ $alternate_key_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$alternate_key_limit"
grep -Fqx $'error\tparser\tentry-limit\tTheme configuration exceeds the runtime parser limit of 512 entries' \
	<<<"$alternate_key_limit"

printf -v multibyte_key 'é%.0s' {1..300}
{
	printf '[ignored]\n'
	for ((entry_index = 0; entry_index < 512; entry_index++)); do
		printf '%s-%s = 1\n' "$multibyte_key" "$entry_index"
	done
	cat "$work/managed-themes.toml"
} >"$config_home/dwm-titus/themes.toml"
multibyte_keys=$(snapshot)
grep -Fqx $'provider\tappearance\tavailable\tread-only\tShared theme inventory and integration state' \
	<<<"$multibyte_keys"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$multibyte_keys"

nord_block=$(awk '
	/^\[theme\.nord\]$/ { capture = 1; next }
	/^\[theme\.dracula\]$/ { exit }
	capture && /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ { print }
' "$repo/config/themes.toml")
{
	printf '[active]\ntheme = "legacy"\n[theme.legacy]\n%s\n' "$nord_block"
	printf '%s\n' '[colors]' \
		'normfgcolor = "#D8DEE9"' \
		'normbgcolor = "#2E3440"' \
		'normbordercolor = "#4C566A"' \
		'selfgcolor = "#ECEFF4"' \
		'selbgcolor = "#5E81AC"' \
		'selbordercolor = "#81A1C1"'
} >"$config_home/dwm-titus/themes.toml"
legacy_collision=$(snapshot)
grep -Fqx $'active\tlegacy\tlegacy\tselected' <<<"$legacy_collision"
grep -Fqx $'theme\tlegacy\tselected\tvalid\ttrue\tNordic\tTheme record is complete' \
	<<<"$legacy_collision"
grep -Fqx $'theme\t@legacy-colors\tavailable\tvalid\ttrue\tautomatic\tTheme record is complete' \
	<<<"$legacy_collision"

{
	printf '[active]\ntheme = "missing"\n'
	for ((theme_index = 0; theme_index < 128; theme_index++)); do
		printf '[theme.sparse%s]\n' "$theme_index"
	done
	printf '[theme.nord]\n%s\n' "$nord_block"
} >"$config_home/dwm-titus/themes.toml"
nord_after_cap=$(snapshot)
grep -Fqx $'active\tmissing\tnord\trecovery' <<<"$nord_after_cap"
grep -Fqx $'theme\tnord\trecovery\tvalid\ttrue\tNordic\tTheme record is complete' \
	<<<"$nord_after_cap"

{
	printf '[active]\ntheme = "chosen"\n'
	for ((theme_index = 0; theme_index < 128; theme_index++)); do
		printf '[theme.sparse%s]\n' "$theme_index"
	done
	printf '[theme.chosen]\n%s\n' "$nord_block"
} >"$config_home/dwm-titus/themes.toml"
selected_after_cap=$(snapshot)
grep -Fqx $'active\tchosen\tchosen\tselected' <<<"$selected_after_cap"
grep -Fqx $'theme\tchosen\tselected\tvalid\ttrue\tNordic\tTheme record is complete' \
	<<<"$selected_after_cap"
sed -i '0,/theme = "chosen"/s//theme = chosen/' "$config_home/dwm-titus/themes.toml"
bare_selected_after_cap=$(snapshot)
grep -Fqx $'active\tchosen\tchosen\tselected' <<<"$bare_selected_after_cap"
grep -Fqx $'theme\tchosen\tselected\tvalid\ttrue\tNordic\tTheme record is complete' \
	<<<"$bare_selected_after_cap"

{
	printf '[active]\ntheme = "t19"\n'
	for ((theme_index = 0; theme_index < 20; theme_index++)); do
		printf '[theme.t%s]\n%s\n' "$theme_index" "$nord_block"
	done
} >"$config_home/dwm-titus/themes.toml"
entry_limited=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$entry_limited"
grep -Fqx $'active\tt19\tt0\trecovery' <<<"$entry_limited"
grep -Fqx $'error\tparser\tentry-limit\tTheme configuration exceeds the runtime parser limit of 512 entries' \
	<<<"$entry_limited"
if grep -Fq $'theme\tt19\t' <<<"$entry_limited"; then
	printf 'Theme defined after the runtime entry limit was inventoried\n' >&2
	exit 1
fi

{
	printf '[active]\ntheme = "t0"\n'
	for ((theme_index = 0; theme_index < 100; theme_index++)); do
		printf '[theme.t%s]\ndark_mode = true\n' "$theme_index"
	done
} >"$config_home/dwm-titus/themes.toml"
set +e
timeout 5 env PATH="$bin_dir" XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot >"$work/many-incomplete.out"
many_status=$?
set -e
[[ $many_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' \
	"$work/many-incomplete.out"
[[ $(grep -c $'^error\ttheme:' "$work/many-incomplete.out") -eq 100 ]]

{
	for ((comment_index = 0; comment_index < 30000; comment_index++)); do
		printf '# comment\n'
	done
	cat "$work/managed-themes.toml"
} >"$config_home/dwm-titus/themes.toml"
timeout 5 env PATH="$bin_dir" GTK_THEME='' XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_root" DWM_APPEARANCE_DATA_DIRS="$data_root" \
	"$helper" snapshot >"$work/comment-heavy.out"
grep -Fqx $'active\tnord\tnord\tselected' "$work/comment-heavy.out"

{
	cat "$work/managed-themes.toml"
	for ((scalar_index = 0; scalar_index < 68000; scalar_index++)); do
		printf 'extra%s = 1\n' "$scalar_index"
	done
} >"$config_home/dwm-titus/themes.toml"
timeout 5 env PATH="$bin_dir" GTK_THEME='' XCURSOR_THEME='' \
	XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_root" \
	DWM_APPEARANCE_DATA_DIRS="$data_root" "$helper" snapshot \
	>"$work/scalar-heavy.out"
grep -Fqx $'active\tnord\tnord\tselected' "$work/scalar-heavy.out"
grep -Fqx $'error\tparser\tentry-limit\tTheme configuration exceeds the runtime parser limit of 512 entries' \
	"$work/scalar-heavy.out"

{
	cat "$work/managed-themes.toml"
	for ((post_budget_index = 0; post_budget_index < 512; post_budget_index++)); do
		printf 'post-budget%s = 1\n' "$post_budget_index"
	done
	printf 'ignored-complex = [{x=1}]\n'
} >"$config_home/dwm-titus/themes.toml"
post_budget_complex=$(snapshot)
grep -Fqx $'active\tnord\tnord\tselected' <<<"$post_budget_complex"
if grep -Fq $'error\tparser\tunsupported-complex-value\t' <<<"$post_budget_complex"; then
	printf 'Post-budget complex value invalidated the runtime snapshot\n' >&2
	exit 1
fi

cat >"$config_home/dwm-titus/themes.toml" <<'EOF'
[colors]
normfgcolor = "#D8DEE9"
normbgcolor = "#2E3440"
normbordercolor = "#4C566A"
selfgcolor = "#ECEFF4"
selbgcolor = "#5E81AC"
selbordercolor = "#81A1C1"
EOF
legacy=$(snapshot)
grep -Fqx $'provider\tappearance\tpartial\tread-only\tShared theme inventory and integration state' \
	<<<"$legacy"
grep -Fqx $'active\t@legacy-colors\t@legacy-colors\tselected' <<<"$legacy"
grep -Fqx $'theme\t@legacy-colors\tselected\tvalid\ttrue\tautomatic\tTheme record is complete' \
	<<<"$legacy"
grep -Fqx $'color\tbackground\t#2E3440\tterm_bg' <<<"$legacy"
if awk -F '\t' '$1 == "color" && $3 !~ /^#[0-9A-Fa-f]{6}$/ { exit 1 }' <<<"$legacy"; then
	:
else
	printf 'Legacy palette emitted an empty or invalid semantic color\n' >&2
	exit 1
fi
grep -Fqx $'error\tparser\tlegacy-format\tLegacy [colors] palette is active; named themes are recommended' \
	<<<"$legacy"

cat >"$config_home/dwm-titus/themes.toml" <<'EOF'
[active]
theme = "missing"
[colors]
normbgcolor = "#2E3440"
EOF
set +e
legacy_not_recovery=$(snapshot)
legacy_not_recovery_status=$?
set -e
[[ $legacy_not_recovery_status -eq 3 ]]
grep -Fqx $'active\tmissing\tnone\tunresolved' <<<"$legacy_not_recovery"
grep -Fqx $'error\tactive\tno-valid-theme\tNo complete theme is available for recovery' \
	<<<"$legacy_not_recovery"

mkdir -p "$work/fallback-home/.config/dwm-titus"
cp "$work/managed-themes.toml" "$work/fallback-home/.config/dwm-titus/themes.toml"
relative_xdg=$(HOME="$work/fallback-home" XDG_CONFIG_HOME=relative-config \
	XDG_DATA_HOME=relative-data DWM_APPEARANCE_DATA_DIRS=$data_root \
	"$helper" snapshot)
grep -Fqx $'source\tuser\t'"$work/fallback-home/.config/dwm-titus/themes.toml" \
	<<<"$relative_xdg"
grep -Fqx $'active\tnord\tnord\tselected' <<<"$relative_xdg"

rm -f "$config_home/dwm-titus/themes.toml" "$work/missing-managed.toml"
set +e
missing=$(PATH=$bin_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_root \
	DWM_APPEARANCE_DATA_DIRS=$data_root \
	DWM_APPEARANCE_MANAGED_THEMES_FILE="$work/missing-managed.toml" \
	"$helper" snapshot)
missing_status=$?
set -e
[[ $missing_status -eq 3 ]]
grep -Fqx $'provider\tappearance\tunavailable\tread-only\tShared theme inventory and integration state' <<<"$missing"
grep -Fqx $'source\tnone\tunavailable' <<<"$missing"
grep -Fqx $'active\tnone\tnone\tunresolved' <<<"$missing"
grep -Fqx $'error\tsource\tmissing\tNo readable user or managed themes.toml file is available' <<<"$missing"

if "$helper" invalid 2>"$work/usage.err"; then
	printf 'Unknown appearance action unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'usage:' "$work/usage.err"

printf 'Appearance provider contract: PASS\n'
