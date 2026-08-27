#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
helper=$repo/scripts/dwm-settings-personalization
work=$(mktemp -d "${TMPDIR:-/tmp}/dwm-personalization-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

home=$work/home
config_home=$home/.config
data_home=$home/.local/share
bin_dir=$work/bin
settings_state=$work/gsettings
mkdir -p "$config_home/dwm-titus" "$config_home/gtk-3.0" "$config_home/gtk-4.0" \
	"$data_home/icons/Cursor One/cursors" "$data_home/icons/Bob's Icons" \
	"$data_home/themes/Theme One/gtk-3.0" "$bin_dir" "$settings_state"
printf '[Icon Theme]\nName=Bob\nDirectories=16x16/apps\n' \
	>"$data_home/icons/Bob's Icons/index.theme"

printf "'Old Font 10'\n" >"$settings_state/font-name"
printf '1.0\n' >"$settings_state/text-scaling-factor"
printf "'Old Cursor'\n" >"$settings_state/cursor-theme"
printf '32\n' >"$settings_state/cursor-size"
printf '"Old Icons"\n' >"$settings_state/icon-theme"
printf "'Old GTK'\n" >"$settings_state/gtk-theme"
cp -a "$settings_state" "$work/gsettings-defaults"

cat >"$bin_dir/gsettings" <<'SH'
#!/bin/sh
set -eu
state=${DWM_TEST_GSETTINGS_STATE:?}
defaults=${DWM_TEST_GSETTINGS_DEFAULTS:?}
command=${1:-}
schema=${2:-}
key=${3:-}
[ "$schema" = org.gnome.desktop.interface ] || exit 1
case $command in
writable)
	[ "${DWM_TEST_GSETTINGS_READONLY:-}" != "$key" ]
	printf 'true\n'
	;;
get)
	cat "$state/$key"
	;;
set)
	[ "${DWM_TEST_GSETTINGS_FAIL_SET:-}" != "$key" ]
	printf '%s\n' "${4:?}" >"$state/$key"
	;;
reset)
	cp "$defaults/$key" "$state/$key"
	;;
*) exit 1 ;;
esac
SH

cat >"$bin_dir/dconf" <<'SH'
#!/bin/sh
exit 0
SH

cat >"$bin_dir/fc-match" <<'SH'
#!/bin/sh
set -eu
for value do last=$value; done
printf '%s' "${DWM_TEST_FC_MATCH_RESULT:-$last}"
SH
cat >"$bin_dir/fc-list" <<'SH'
#!/bin/sh
set -eu
if [ "${DWM_TEST_FC_LIST_RESULT+x}" = x ]; then
	printf '%s' "$DWM_TEST_FC_LIST_RESULT"
	case $DWM_TEST_FC_LIST_RESULT in '') ;; *) printf '\n' ;; esac
else
	printf '%s\n' "${DWM_TEST_FC_MATCH_RESULT:-New Font}" \
		'MesloLGS Nerd Font' 'MesloLGS Nerd Font Mono' 'MesloLGS NF'
fi
SH

cat >"$bin_dir/systemctl" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$bin_dir/dbus-update-activation-environment" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$bin_dir/xrdb" <<'SH'
#!/bin/sh
cat >"${DWM_TEST_XRDB_MARKER:?}"
SH
cat >"$bin_dir/xsettingsd" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$bin_dir/dump_xsettings" <<'SH'
#!/bin/sh
printf 'Xft/DPI 122880\n'
SH
cat >"$bin_dir/dwm-xsettings" <<'SH'
#!/bin/sh
set -eu
[ "${1:-}" = status ] || exit 2
printf 'xsettings-protocol\t1\t0\n'
if [ "${DWM_TEST_XSETTINGS_STATE:-active}" = system-follow ]; then
	printf 'state\tsystem-follow\n'
else
	printf 'state\t%s\t%s\n' \
		"${DWM_TEST_XSETTINGS_STATE:-active}" "${DWM_TEST_XSETTINGS_DPI:-122880}"
fi
SH
cat >"$bin_dir/dwm-settings-theme" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"${DWM_TEST_THEME_CALLS:?}"
case ${1:-} in
mutation-ready) exit 0 ;;
personalization-ready) [ "${DWM_TEST_PERSONALIZATION_READY:-1}" = 1 ] ;;
personalize)
	printf 'personalization-action-protocol\t1\t0\n'
	printf 'result\tapply\t%s\t%s\n' "${2:?}" "${3:?}"
	;;
personalize-reset)
	case ${2:?} in
	cursor | gtk | qt) value=follow-theme ;;
	*) value=follow-system ;;
	esac
	printf 'personalization-action-protocol\t1\t0\n'
	printf 'result\treset\t%s\t%s\n' "$2" "$value"
	;;
*) exit 2 ;;
esac
SH
cat >"$bin_dir/qt6ct" <<'SH'
#!/bin/sh
printf 'qt6ct\n' >>"${DWM_TEST_DELEGATE_MARKER:?}"
printf '%s\t%s\t%s\n' "${QT_QPA_PLATFORMTHEME:-}" "${XCURSOR_THEME:-}" \
	"${XCURSOR_SIZE:-}" >"${DWM_TEST_DELEGATE_ENV_MARKER:?}"
SH
cat >"$bin_dir/nwg-look" <<'SH'
#!/bin/sh
printf 'nwg-look\n' >>"${DWM_TEST_DELEGATE_MARKER:?}"
SH
chmod +x "$bin_dir"/*

printf '[Settings]\nunchanged=yes\ngtk-theme-name=Old GTK\n\n[Other]\nvalue=keep\n' \
	>"$config_home/gtk-3.0/settings.ini"
printf '[Other]\nvalue=keep\n' >"$config_home/gtk-4.0/settings.ini"
printf 'gtk-key-theme-name="Keep"\ngtk-theme-name="Old GTK"\n' >"$home/.gtkrc-2.0"
printf 'Xcursor.theme: Old Cursor\nXcursor.size: 32\nCustom.value: keep\n' \
	>"$config_home/dwm-titus/cursor.Xresources"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Old\\ Cursor\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"

run_helper() {
	PATH=${DWM_TEST_HELPER_PATH:-$bin_dir:/usr/bin:/bin} \
		HOME=$home XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home XDG_DATA_DIRS=$work/empty-share \
		XDG_RUNTIME_DIR=$work/runtime \
		DWM_TEST_GSETTINGS_STATE=$settings_state \
		DWM_TEST_GSETTINGS_DEFAULTS=$work/gsettings-defaults \
		DWM_TEST_XRDB_MARKER=$work/xrdb.marker \
		DWM_TEST_DELEGATE_MARKER=$work/delegate.marker \
		DWM_TEST_DELEGATE_ENV_MARKER=$work/delegate-env.marker \
		DWM_TEST_THEME_CALLS=$work/theme.calls \
		DWM_SETTINGS_THEME_HELPER=$bin_dir/dwm-settings-theme \
		DWM_SETTINGS_XSETTINGS_HELPER=$bin_dir/dwm-xsettings \
		DISPLAY=:199 "$helper" "$@"
}

status=$(DWM_TEST_XSETTINGS_STATE=system-follow run_helper status)
printf '%s\n' "$status" | grep -Fqx 'personalization-protocol	1	0'
printf '%s\n' "$status" | grep -Fqx \
	'provider	personalization	available	user-session	Bounded personalization changes are available'
printf '%s\n' "$status" | grep -Fqx \
	'mutation	available	Transactional personalization changes are available'
printf '%s\n' "$status" | grep -Fqx \
	'selection	font	available	Old Font 10	follow-system	Persistent user-session setting'
printf '%s\n' "$status" | grep -Fqx \
	'delegate	qt	available	qt6ct	Open the Qt 6 configuration tool for advanced settings'
printf '%s\n' "$status" | grep -Fqx \
	'delegate	gtk	available	nwg-look	Open nwg-look for advanced GTK settings'
printf "personalization-protocol\t1\t0\nfont\tfollow-system\ntext-size\t1.25\ncursor\tCursor One\nicon\tBob's Icons\nqt\tfollow-theme\n" \
	>"$config_home/dwm-titus/personalization.conf"
persisted_status=$(run_helper status)
expected=$(printf 'selection\ttext-size\tavailable\t1.0\t1.25\tPersistent desktop text scale')
printf '%s\n' "$persisted_status" | grep -Fqx "$expected"
inactive_status=$(DWM_TEST_XSETTINGS_STATE=inactive run_helper status)
expected=$(printf 'selection\ttext-size\tpartial\t1.0\t1.25\tManaged X11 text scale is not active; apply or reset remains available')
printf '%s\n' "$inactive_status" | grep -Fqx "$expected"
expected=$(printf 'selection\tcursor\tavailable\tOld Cursor\tCursor One\tPersistent user-session setting')
printf '%s\n' "$persisted_status" | grep -Fqx "$expected"
expected=$(printf "selection\ticon\tavailable\tOld Icons\tBob's Icons\tPersistent user-session setting")
printf '%s\n' "$persisted_status" | grep -Fqx "$expected"
expected=$(printf 'selection\tqt\tavailable\tqt6ct\tfollow-theme\tPersistent environment for newly launched Qt applications')
printf '%s\n' "$persisted_status" | grep -Fqx "$expected"
printf 'invalid\n' >"$config_home/dwm-titus/personalization.conf"
malformed_status=$(run_helper status)
expected=$(printf 'provider\tpersonalization\tpartial\tuser-session\tPersisted personalization choices are unavailable or malformed')
printf '%s\n' "$malformed_status" | grep -Fqx "$expected"
rm -f "$config_home/dwm-titus/personalization.conf"
stale_status=$(DWM_TEST_XSETTINGS_STATE=stale run_helper status)
expected=$(printf 'selection\ttext-size\tpartial\t1.0\tfollow-system\tManaged X11 text scale is still active; reset remains available')
printf '%s\n' "$stale_status" | grep -Fqx "$expected"
head -c 4097 /dev/zero | tr '\0' x >"$config_home/dwm-titus/theme-env.sh"
oversized_status=$(run_helper status)
printf '%s\n' "$oversized_status" | grep -Fqx \
	'selection	qt	partial		follow-theme	No supported persistent Qt backend is configured'
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Old\\ Cursor\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\n' >"$config_home/dwm-titus/theme-env.sh"
incomplete_theme_status=$(run_helper status)
expected=$(printf 'selection\tqt\tpartial\t\tfollow-theme\tNo supported persistent Qt backend is configured')
printf '%s\n' "$incomplete_theme_status" | grep -Fqx "$expected"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport QT_QPA_PLATFORMTHEME=qt5ct\nexport XCURSOR_THEME=Old\\ Cursor\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
duplicate_theme_status=$(run_helper status)
printf '%s\n' "$duplicate_theme_status" | grep -Fqx "$expected"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Old\\ Cursor\nexport XCURSOR_SIZE=32\nexport CUSTOM_VALUE=yes\n' \
	>"$config_home/dwm-titus/theme-env.sh"
unknown_theme_status=$(run_helper status)
printf '%s\n' "$unknown_theme_status" | grep -Fqx "$expected"
printf 'export QT_QPA_PLATFORMTHEME=qt6ct\nexport XCURSOR_THEME=Old\\ Cursor\nexport XCURSOR_SIZE=32\n' \
	>"$config_home/dwm-titus/theme-env.sh"
restricted_status=$(DWM_TEST_PERSONALIZATION_READY=0 run_helper status)
no_dconf_bin=$work/no-dconf-bin
mkdir -p "$no_dconf_bin"
cp -a "$bin_dir/." "$no_dconf_bin/"
rm -f "$no_dconf_bin/dconf"
for command_name in awk bash cat dirname grep stat timeout; do
	ln -s "$(command -v "$command_name")" "$no_dconf_bin/$command_name"
done
no_dconf_status=$(DWM_TEST_HELPER_PATH=$no_dconf_bin run_helper status)
printf '%s\n' "$no_dconf_status" | grep -Fqx \
	'provider	personalization	partial	user-session	GSettings-backed changes lack required dconf rollback support; supported Qt changes remain available'
for capability in font text-size cursor icon gtk; do
	printf '%s\n' "$no_dconf_status" | grep -Fq \
		"selection	$capability	restricted	"
	detail=$(printf '%s\n' "$no_dconf_status" | awk -F '\t' -v capability="$capability" \
		'$1 == "selection" && $2 == capability { print $6 }')
	[ "$detail" = 'Required dconf rollback backend is unavailable' ]
done
if DWM_TEST_HELPER_PATH=$no_dconf_bin run_helper apply font 'New Font' \
	>"$work/no-dconf.out" 2>"$work/no-dconf.err"; then
	printf 'Font mutation was accepted without dconf rollback support\n' >&2
	exit 1
fi
grep -Fqx \
	'dwm-settings-personalization: dconf rollback backend is unavailable for desktop interface setting: font-name' \
	"$work/no-dconf.err"
DWM_TEST_HELPER_PATH=$no_dconf_bin run_helper apply qt gtk3 | grep -Fqx \
	'result	apply	qt	gtk3'
printf '%s\n' "$restricted_status" | grep -Fqx \
	'mutation	restricted	The shared theme transaction is unavailable or unsafe'

readonly_status=$(DWM_TEST_GSETTINGS_READONLY=font-name run_helper status)
printf '%s\n' "$readonly_status" | grep -Fqx \
	'selection	font	restricted	Old Font 10	follow-system	Setting is readable but not writable in this session'
printf '%s\n' "$readonly_status" | grep -Fqx \
	'selection	icon	available	Old Icons	follow-system	Persistent user-session setting'
if (DWM_TEST_GSETTINGS_READONLY=font-name run_helper apply font 'New Font' \
	>"$work/readonly.out" 2>"$work/readonly.err"); then
	printf 'Read-only font setting was accepted\n' >&2
	exit 1
fi
grep -Fqx \
	'dwm-settings-personalization: desktop interface setting is unavailable or read-only: font-name' \
	"$work/readonly.err"
(DWM_TEST_GSETTINGS_READONLY=font-name run_helper apply icon "Bob's Icons" >/dev/null)
grep -Fqx "personalize icon Bob's Icons" "$work/theme.calls"

run_helper apply font 'New Font' | grep -Fqx \
	'result	apply	font	New Font'
grep -Fqx 'personalize font New Font' "$work/theme.calls"
DWM_TEST_FC_MATCH_RESULT='MesloLGS NF' run_helper apply font \
	'MesloLGS Nerd Font Mono' | grep -Fqx \
	'result	apply	font	MesloLGS Nerd Font Mono'
grep -Fqx 'personalize font MesloLGS Nerd Font Mono' "$work/theme.calls"
if DWM_TEST_FC_LIST_RESULT='' run_helper apply font 'Symbol Font' \
	>"$work/symbol-font.out" 2>"$work/symbol-font.err"; then
	printf 'Font without printable glyph coverage was accepted\n' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-personalization: font family is not installed: Symbol Font' \
	"$work/symbol-font.err"

run_helper apply text-size 1.25 | grep -Fqx \
	'result	apply	text-size	1.25'
grep -Fqx 'personalize text-size 1.25' "$work/theme.calls"
if run_helper apply text-size 3.0 >"$work/invalid.out" 2>"$work/invalid.err"; then
	printf 'Unsupported text scale was accepted\n' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-personalization: text size must be one of the supported scale steps' \
	"$work/invalid.err"

run_helper apply cursor 'Cursor One' | grep -Fqx \
	'result	apply	cursor	Cursor One'
grep -Fqx 'personalize cursor Cursor One' "$work/theme.calls"

run_helper apply icon "Bob's Icons" | grep -Fqx \
	"result	apply	icon	Bob's Icons"
grep -Fqx "personalize icon Bob's Icons" "$work/theme.calls"

run_helper apply gtk 'Theme One' | grep -Fqx \
	'result	apply	gtk	Theme One'
grep -Fqx 'personalize gtk Theme One' "$work/theme.calls"

run_helper apply qt gtk3 | grep -Fqx 'result	apply	qt	gtk3'
grep -Fqx 'personalize qt gtk3' "$work/theme.calls"
if run_helper apply qt unsupported >"$work/invalid-qt.out" 2>"$work/invalid-qt.err"; then
	printf 'Unsupported Qt backend was accepted\n' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-personalization: Qt platform theme backend is unavailable: unsupported' \
	"$work/invalid-qt.err"

if (DWM_TEST_GSETTINGS_READONLY=gtk-theme run_helper apply gtk Adwaita \
	>"$work/fail.out" 2>"$work/fail.err"); then
	printf 'Read-only GTK setting was accepted\n' >&2
	exit 1
fi
grep -Fqx \
	'dwm-settings-personalization: desktop interface setting is unavailable or read-only: gtk-theme' \
	"$work/fail.err"

run_helper reset font | grep -Fqx 'result	reset	font	follow-system'
grep -Fqx 'personalize-reset font' "$work/theme.calls"
no_xsettingsd_bin=$work/no-xsettingsd-bin
mkdir -p "$no_xsettingsd_bin"
cp -a "$bin_dir/." "$no_xsettingsd_bin/"
rm -f "$no_xsettingsd_bin/xsettingsd"
for required_command in awk bash cat dirname grep stat; do
	ln -s "$(command -v "$required_command")" "$no_xsettingsd_bin/$required_command"
done
no_xsettingsd_status=$(DWM_TEST_HELPER_PATH=$no_xsettingsd_bin run_helper status)
expected=$(printf 'selection\ttext-size\tpartial\t1.0\tfollow-system\tXSETTINGS verification tools are unavailable; reset to system follow remains available')
printf '%s\n' "$no_xsettingsd_status" | grep -Fqx "$expected"
DWM_TEST_HELPER_PATH=$no_xsettingsd_bin run_helper reset text-size | grep -Fqx \
	'result	reset	text-size	follow-system'
if DWM_TEST_HELPER_PATH=$no_xsettingsd_bin run_helper apply text-size 1.25 \
	>"$work/no-xsettingsd.out" 2>"$work/no-xsettingsd.err"; then
	printf 'Text scale apply was accepted without xsettingsd\n' >&2
	exit 1
fi
grep -Fqx \
	'dwm-settings-personalization: managed X11 text scaling requires xsettingsd, dump_xsettings, and dwm-xsettings' \
	"$work/no-xsettingsd.err"
run_helper reset qt | grep -Fqx 'result	reset	qt	follow-theme'
grep -Fqx 'personalize-reset qt' "$work/theme.calls"

printf '%s\n' 'export QT_QPA_PLATFORMTHEME=qt6ct' \
	'export XCURSOR_THEME=Cursor-One' 'export XCURSOR_SIZE=32' \
	>"$config_home/dwm-titus/theme-env.sh"
QT_QPA_PLATFORMTHEME=gtk3 XCURSOR_THEME=Old-Cursor XCURSOR_SIZE=24 \
	run_helper delegate qt
i=0
while [ "$i" -lt 50 ] && [ ! -s "$work/delegate.marker" ]; do
	i=$((i + 1))
	sleep 0.02
done
grep -Fqx qt6ct "$work/delegate.marker"
grep -Fqx "$(printf 'qt6ct\tCursor-One\t32')" "$work/delegate-env.marker"
: >"$work/delegate.marker"
run_helper delegate gtk
i=0
while [ "$i" -lt 50 ] && [ ! -s "$work/delegate.marker" ]; do
	i=$((i + 1))
	sleep 0.02
done
grep -Fqx nwg-look "$work/delegate.marker"

printf 'dwm-settings-personalization tests: PASS\n'
