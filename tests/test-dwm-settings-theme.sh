#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo/scripts/dwm-settings-theme
work=$(mktemp -d)
cleanup() {
	rm -rf "$work"
}
signal_exit() {
	local signal=$1
	trap - EXIT "$signal"
	cleanup
	kill -s "$signal" "$$"
}
trap cleanup EXIT
trap 'signal_exit HUP' HUP
trap 'signal_exit INT' INT
trap 'signal_exit TERM' TERM

config_home=$work/config
data_home=$work/data
state_home=$work/state
runtime_dir=$work/runtime
home_dir=$work/home
themes_file=$config_home/dwm-titus/themes.toml
managed_file=$data_home/dwm-titus/config/themes.toml
apply_stub=$work/apply-theme
reload_stub=$work/reload-theme
xsettings_stub=$work/reload-xsettings

mkdir -p "$config_home/dwm-titus" "$data_home/dwm-titus/config" "$state_home" \
	"$runtime_dir" "$home_dir"
cp "$repo/config/themes.toml" "$managed_file"

cat >"$apply_stub" <<'SH'
#!/bin/sh
set -eu
wait_for_release() {
	path=$1
	attempt=0
	while [ ! -e "$path" ]; do
		attempt=$((attempt + 1))
		if [ "$attempt" -ge 400 ]; then
			printf 'fixture timed out waiting for %s\n' "$path" >&2
			exit 1
		fi
		sleep 0.05
	done
}
themes=${DWM_APPEARANCE_THEMES_FILE:?}
managed=${DWM_APPEARANCE_MANAGED_THEMES_FILE:?}
if [ "${DWM_APPEARANCE_STAGED_OUTPUT:-0}" != 1 ]; then
	[ -z "${DWM_TEST_EXPECT_CONFIG_HOME:-}" ] || [ "$XDG_CONFIG_HOME" = "$DWM_TEST_EXPECT_CONFIG_HOME" ]
	[ -z "${DWM_TEST_EXPECT_DATA_HOME:-}" ] || [ "$XDG_DATA_HOME" = "$DWM_TEST_EXPECT_DATA_HOME" ]
fi
[ -f "$themes" ] || themes=$managed
active=$(awk '
	/^[[:space:]]*\[active\][[:space:]]*(#.*)?$/ { in_active = 1; next }
	/^\[/ { in_active = 0 }
	in_active && $1 == "theme" {
		value = $0
		sub(/^[^=]*=[[:space:]]*/, "", value)
		sub(/[[:space:]]*#.*/, "", value)
		gsub(/^"|"$/, "", value)
		print value
		exit
	}
' "$themes")
if [ "${DWM_APPEARANCE_LIVE_ONLY:-0}" = 1 ]; then
	if [ -n "${DWM_TEST_LIVE_ONLY_LOG:-}" ]; then
		printf '%s\n' "$active" >>"$DWM_TEST_LIVE_ONLY_LOG"
	fi
	if [ -n "${DWM_TEST_LIVE_ONLY_READY:-}" ]; then
		: >"$DWM_TEST_LIVE_ONLY_READY"
	fi
	if [ -n "${DWM_TEST_LIVE_ONLY_RELEASE:-}" ]; then
		wait_for_release "$DWM_TEST_LIVE_ONLY_RELEASE"
	fi
	if [ "${DWM_TEST_LIVE_ONLY_FAIL:-0}" = 1 ]; then
		printf 'fixture live-only failure\n' >&2
		exit 1
	fi
	if [ "${DWM_TEST_APPLY_FAIL:-0}" = 1 ]; then
		printf 'fixture apply failure\n' >&2
		exit 1
	fi
	if [ -n "${DWM_TEST_LIVE_ONLY_FAIL_THEME:-}" ] &&
		[ "$active" = "$DWM_TEST_LIVE_ONLY_FAIL_THEME" ]; then
		printf 'fixture live-only target failure\n' >&2
		exit 1
	fi
	if [ -n "${DWM_TEST_APPLY_FAIL_THEME:-}" ] && [ "$active" = "$DWM_TEST_APPLY_FAIL_THEME" ]; then
		printf 'fixture target apply failure\n' >&2
		exit 1
	fi
	exit 0
fi
printf '%s\n' "$active" >>"${DWM_TEST_APPLY_LOG:?}"
if [ -n "${DWM_TEST_APPLY_READY:-}" ]; then
	: >"$DWM_TEST_APPLY_READY"
fi
if [ -n "${DWM_TEST_APPLY_PID:-}" ]; then
	printf '%s\n' "$$" >"$DWM_TEST_APPLY_PID"
fi
if [ -n "${DWM_TEST_APPLY_WAIT:-}" ]; then
	wait_for_release "$DWM_TEST_APPLY_WAIT"
fi
if [ "${DWM_TEST_APPLY_FAIL:-0}" = 1 ]; then
	printf 'fixture apply failure\n' >&2
	exit 1
fi
if [ -n "${DWM_TEST_APPLY_FAIL_THEME:-}" ] && [ "$active" = "$DWM_TEST_APPLY_FAIL_THEME" ]; then
	printf 'fixture target apply failure\n' >&2
	exit 1
fi
if [ -n "${DWM_TEST_APPLY_DELAY:-}" ]; then
	sleep "$DWM_TEST_APPLY_DELAY"
fi
SH
chmod +x "$apply_stub"

cat >"$reload_stub" <<'SH'
#!/bin/sh
set -eu
printf 'reload\n' >>"${DWM_TEST_RELOAD_LOG:?}"
SH
chmod +x "$reload_stub"

cat >"$xsettings_stub" <<'SH'
#!/bin/sh
set -eu
printf '%s\n' "${1:?}" >>"${DWM_TEST_XSETTINGS_LOG:?}"
SH
chmod +x "$xsettings_stub"
export DWM_APPEARANCE_XSETTINGS_HELPER=$xsettings_stub
export DWM_TEST_XSETTINGS_LOG=$work/xsettings.log

run_theme() {
	HOME=$home_dir \
		XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home \
		XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime_dir \
		DWM_APPEARANCE_APPLY_HELPER=$apply_stub \
		DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
		DWM_TEST_APPLY_LOG=$work/apply.log \
		DWM_TEST_LIVE_ONLY_LOG=$work/live-only.log \
		DWM_TEST_RELOAD_LOG=$work/reload.log \
		"$helper" "$@"
}

run_theme_real_apply() {
	HOME=$home_dir \
		XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home \
		XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime_dir \
		DWM_APPEARANCE_APPLY_HELPER=$repo/scripts/theme-apply.sh \
		DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
		DWM_TEST_RELOAD_LOG=$work/reload.log \
		DWM_TEST_KITTY_RELOAD_MARKER=$work/kitty-reload.marker \
		DWM_TEST_LIVE_LOG=$work/live.log \
		DWM_TEST_DCONF_DIR=$work/dconf \
		DWM_TEST_LIVE_CONFIG_HOME=$config_home \
		DWM_TEST_XFCONF_DIR=$work/xfconf \
		PATH=$work/integration-bin:$PATH \
		"$helper" "$@"
}

run_theme_apply_direct() {
	HOME=$home_dir \
		XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home \
		XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime_dir \
		DWM_APPEARANCE_THEMES_FILE=$themes_file \
		DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
		DWM_TEST_LIVE_LOG=$work/live.log \
		DWM_TEST_DCONF_DIR=$work/dconf \
		DWM_TEST_XFCONF_DIR=$work/xfconf \
		DWM_APPEARANCE_PERSONALIZATION_CAPABILITY=${DWM_APPEARANCE_PERSONALIZATION_CAPABILITY:-} \
		PATH=$work/integration-bin:$PATH \
		"$repo/scripts/theme-apply.sh"
}

integration_snapshot() {
	local path
	for path in \
		"$config_home/dwm-titus/personalization.conf" \
		"$config_home/alacritty/active-theme.toml" \
		"$config_home/alacritty/alacritty.toml" \
		"$config_home/kitty/active-theme.conf" \
		"$config_home/kitty/kitty.conf" \
		"$config_home/gtk-3.0/settings.ini" \
		"$config_home/gtk-4.0/settings.ini" \
		"$home_dir/.gtkrc-2.0" \
		"$config_home/dwm-titus/cursor.Xresources" \
		"$config_home/dwm-titus/theme-env.sh" \
		"$config_home/dwm-titus/xsettingsd.conf" \
		"$config_home/qt5ct/qt5ct.conf" \
		"$config_home/qt6ct/qt6ct.conf"; do
		if [[ -f $path ]]; then
			printf 'file\t%s\t%s\t%s\n' "$path" "$(stat -c %a -- "$path")" "$(sha256sum -- "$path")"
		else
			printf 'absent\t%s\n' "$path"
		fi
	done
}

mkdir -p "$work/integration-bin"
for side_effect_command in dbus-update-activation-environment dconf gsettings kitty pgrep qt6ct systemctl xfconf-query xrdb; do
	printf '#!/bin/sh\nexit 0\n' >"$work/integration-bin/$side_effect_command"
	chmod +x "$work/integration-bin/$side_effect_command"
done
for live_command in dbus-update-activation-environment gsettings systemctl xfconf-query xrdb; do
	cat >"$work/integration-bin/$live_command" <<'SH'
#!/bin/sh
printf '%s\n' "${0##*/}" >>"${DWM_TEST_LIVE_LOG:?}"
exit 0
SH
	chmod +x "$work/integration-bin/$live_command"
done
cat >"$work/integration-bin/gsettings" <<'SH'
#!/bin/sh
command=${1:-}
key=${3:-}
state=${DWM_TEST_DCONF_DIR:?}/${key}
case $command in
writable)
	printf 'true\n'
	exit 0
	;;
get)
	[ "${DWM_TEST_GSETTINGS_FAIL_ALL:-0}" != 1 ] || exit 1
	if [ "${DWM_TEST_GSETTINGS_STAGE_DEFAULT:-0}" = 1 ] &&
		[ "${XDG_CONFIG_HOME:-}" != "${DWM_TEST_LIVE_CONFIG_HOME:?}" ]; then
		if [ "$key" = font-name ]; then
			printf "'Cantarell 11'\n"
		else
			printf '1.0\n'
		fi
		exit 0
	fi
	if [ -f "$state" ]; then
		cat "$state"
	elif [ "$key" = font-name ]; then
		printf "'Cantarell 11'\n"
	else
		printf '1.0\n'
	fi
	exit 0
	;;
set | reset)
	printf 'gsettings\n' >>"${DWM_TEST_LIVE_LOG:?}"
	[ "${DWM_TEST_GSETTINGS_FAIL_ALL:-0}" != 1 ] || exit 1
	[ -z "${DWM_TEST_GSETTINGS_FAIL_KEY:-}" ] ||
		[ "$key" != "$DWM_TEST_GSETTINGS_FAIL_KEY" ] || exit 1
	if [ -n "${DWM_TEST_GSETTINGS_CALLS:-}" ]; then
		printf '%s\t%s\n' "$command" "$key" >>"$DWM_TEST_GSETTINGS_CALLS"
	fi
	mkdir -p -- "${state%/*}"
	if [ "$command" = set ]; then
		if [ "${DWM_TEST_GSETTINGS_MISMATCH_KEY:-}" = "$key" ]; then
			printf "'Unexpected external value'\n" >"$state"
		elif [ "$key" = text-scaling-factor ]; then
			printf '%s\n' "${4:?}" >"$state"
		else
			value=${4:?}
			case $value in
			*"'"*)
				value=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
				printf '"%s"\n' "$value" >"$state"
				;;
			*)
				value=$(printf '%s' "$value" | sed 's/\\/\\\\/g')
				printf "'%s'\n" "$value" >"$state"
				;;
			esac
		fi
	else
		rm -f -- "$state"
	fi
	exit 0
	;;
*) exit 0 ;;
esac
SH
chmod +x "$work/integration-bin/gsettings"
cat >"$work/integration-bin/dconf" <<'SH'
#!/bin/sh
set -eu
command=${1:?}
path=${2:?}
key=${path##*/}
state=${DWM_TEST_DCONF_DIR:?}/${key}
case $command in
read)
	[ ! -f "$state" ] || cat "$state"
	;;
write)
	mkdir -p -- "${state%/*}"
	printf '%s\n' "${3:?}" >"$state"
	;;
reset)
	rm -f -- "$state"
	;;
*) exit 1 ;;
esac
SH
chmod +x "$work/integration-bin/dconf"
cat >"$work/integration-bin/xfconf-query" <<'SH'
#!/bin/sh
set -eu
printf 'xfconf-query\n' >>"${DWM_TEST_LIVE_LOG:?}"
[ "${DWM_TEST_XFCONF_FAIL:-0}" != 1 ] || exit 1
property=
list=false
reset=false
set_value=false
value=
while [ "$#" -gt 0 ]; do
	case $1 in
	-c | -t)
		shift 2
		;;
	-p)
		property=${2:?}
		shift 2
		;;
	-l)
		list=true
		shift
		;;
	-n)
		shift
		;;
	-r)
		reset=true
		shift
		;;
	-s)
		value=${2-}
		set_value=true
		shift 2
		;;
	*) exit 2 ;;
	esac
done
$list && exit 0
case $property in
/Net/ThemeName) state=${DWM_TEST_XFCONF_DIR:?}/theme-name ;;
/Gtk/CursorThemeName) state=${DWM_TEST_XFCONF_DIR:?}/cursor-theme ;;
/Gtk/CursorThemeSize) state=${DWM_TEST_XFCONF_DIR:?}/cursor-size ;;
*) exit 1 ;;
esac
if $reset; then
	rm -f -- "$state"
elif $set_value; then
	mkdir -p -- "${state%/*}"
	printf '%s\n' "$value" >"$state"
elif [ -f "$state" ]; then
	cat "$state"
else
	exit 1
fi
SH
chmod +x "$work/integration-bin/xfconf-query"

if (cd "$work" && HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=relative-runtime \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/apply.log \
	"$helper" preview-status >"$work/relative-runtime.out" 2>"$work/relative-runtime.err"); then
	echo 'relative XDG_RUNTIME_DIR unexpectedly succeeded' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-theme: XDG_RUNTIME_DIR must be an absolute path' \
	"$work/relative-runtime.err"
[[ ! -e $work/relative-runtime ]]

reset_fixture() {
	rm -rf "$config_home" "$state_home" "$runtime_dir" "$work/dconf" "$work/xfconf"
	mkdir -p "$config_home/dwm-titus" "$state_home" "$runtime_dir" "$work/dconf" "$work/xfconf"
	cp "$repo/config/themes.toml" "$themes_file"
	chmod 640 "$themes_file"
	: >"$work/apply.log"
	: >"$work/live-only.log"
	: >"$work/reload.log"
	rm -f "$work/kitty-reload.marker"
}

active_theme() {
	awk '
		/^[[:space:]]*\[active\][[:space:]]*(#.*)?$/ { in_active = 1; next }
		/^\[/ { in_active = 0 }
		in_active && $1 == "theme" {
			value = $0
			sub(/^[^=]*=[[:space:]]*/, "", value)
			sub(/[[:space:]]*#.*/, "", value)
			gsub(/^"|"$/, "", value)
			print value
			exit
		}
	' "$themes_file"
}

wait_for_theme() {
	local expected=$1 attempt
	for ((attempt = 0; attempt < 100; attempt++)); do
		if [[ $(active_theme 2>/dev/null || true) == "$expected" ]]; then
			return 0
		fi
		sleep 0.05
	done
	printf 'theme did not converge to %s\n' "$expected" >&2
	return 1
}

process_is_running() {
	local pid=$1 state
	state=$(awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			print fields[1]
		}
	' "/proc/$pid/stat" 2>/dev/null || true)
	[[ -n $state && $state != Z ]]
}

reset_fixture
before_custom=$(grep -F '[theme.dracula]' "$themes_file")
apply_output=$(run_theme apply dracula 2>"$work/apply.err")
grep -Fqx $'appearance-action-protocol\t1\t0' <<<"$apply_output"
grep -Fqx $'result\tapply\tdracula\tnord' <<<"$apply_output"
[[ $(active_theme) == dracula ]]
[[ $(stat -c %a "$themes_file") == 640 ]]
grep -Fqx 'theme = "dracula"   # ← change only this line to switch themes' "$themes_file"
grep -Fqx "$before_custom" "$themes_file"
grep -Fqx dracula "$work/apply.log"

relative_home=$work/relative-home
relative_runtime=$work/relative-xdg-runtime
mkdir -p "$relative_home/.config/dwm-titus" \
	"$relative_home/.local/share/dwm-titus/config" "$relative_runtime"
cp "$repo/config/themes.toml" "$relative_home/.config/dwm-titus/themes.toml"
cp "$repo/config/themes.toml" "$relative_home/.local/share/dwm-titus/config/themes.toml"
(
	cd "$work"
	HOME=$relative_home XDG_CONFIG_HOME=relative-config XDG_DATA_HOME=relative-data \
		XDG_STATE_HOME=relative-state XDG_RUNTIME_DIR=$relative_runtime \
		DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/relative-apply.log \
		DWM_TEST_EXPECT_CONFIG_HOME=$relative_home/.config \
		DWM_TEST_EXPECT_DATA_HOME=$relative_home/.local/share \
		"$helper" apply dracula >"$work/relative-apply.out" 2>"$work/relative-apply.err"
)
grep -Fq 'theme = "dracula"' "$relative_home/.config/dwm-titus/themes.toml"
[[ ! -e $work/relative-config && ! -e $work/relative-data && ! -e $work/relative-state ]]

before_hash=$(sha256sum "$themes_file")
if run_theme apply missing-theme 2>"$work/missing.err"; then
	printf 'unknown theme was accepted\n' >&2
	exit 1
fi
grep -Fq 'theme is unavailable, invalid, or the source is unsafe to mutate: missing-theme' \
	"$work/missing.err"
[[ $(sha256sum "$themes_file") == "$before_hash" ]]

reset_fixture
race_bin=$work/race-bin
race_ready=$work/race.ready
race_release=$work/race.release
real_mv=$(command -v mv)
mkdir -p "$race_bin"
cat >"$race_bin/mv" <<SH
#!/bin/sh
set -eu
last=
for argument do last=\$argument; done
if [ "\$last" = "\${DWM_TEST_RACE_THEMES:?}" ] && [ ! -e "\${DWM_TEST_RACE_READY:?}" ]; then
	: >"\$DWM_TEST_RACE_READY"
	while [ ! -e "\${DWM_TEST_RACE_RELEASE:?}" ]; do sleep 0.01; done
fi
exec "$real_mv" "\$@"
SH
chmod +x "$race_bin/mv"
PATH=$race_bin:$PATH HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/apply.log \
	DWM_TEST_RACE_THEMES=$themes_file DWM_TEST_RACE_READY=$race_ready \
	DWM_TEST_RACE_RELEASE=$race_release \
	"$helper" apply dracula >"$work/race.out" 2>"$work/race.err" &
race_pid=$!
for attempt in {1..100}; do
	[[ -e $race_ready ]] && break
	sleep 0.05
done
[[ -e $race_ready ]]
printf '\n# late external edit\n' >>"$themes_file"
: >"$race_release"
set +e
wait "$race_pid"
race_status=$?
set -e
[[ $race_status -eq 1 ]]
grep -Fq 'changed while preparing the transaction' "$work/race.err"
grep -Fqx '# late external edit' "$themes_file"
[[ $(active_theme) == nord ]]
[[ ! -e $state_home/dwm-titus/appearance/transaction.meta ]]

reset_fixture
rm -f "$race_ready" "$race_release"
PATH=$race_bin:$PATH HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/apply.log \
	DWM_TEST_RACE_THEMES=$themes_file DWM_TEST_RACE_READY=$race_ready \
	DWM_TEST_RACE_RELEASE=$race_release \
	"$helper" apply dracula >"$work/mode-race.out" 2>"$work/mode-race.err" &
mode_race_pid=$!
for attempt in {1..100}; do
	[[ -e $race_ready ]] && break
	sleep 0.05
done
[[ -e $race_ready ]]
chmod 600 "$themes_file"
: >"$race_release"
set +e
wait "$mode_race_pid"
mode_race_status=$?
set -e
[[ $mode_race_status -eq 1 ]]
grep -Fq 'changed while preparing the transaction' "$work/mode-race.err"
[[ $(stat -c %a -- "$themes_file") == 600 ]]
[[ $(active_theme) == nord ]]

reset_fixture
same_source_exchange_ready=$work/same-source-exchange.ready
same_source_exchange_release=$work/same-source-exchange.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
	DWM_TEST_APPLY_LOG=$work/apply.log DWM_TEST_RELOAD_LOG=$work/reload.log \
	DWM_TEST_SOURCE_EXCHANGE_READY=$same_source_exchange_ready \
	DWM_TEST_SOURCE_EXCHANGE_RELEASE=$same_source_exchange_release \
	"$helper" apply nord >"$work/same-source-exchange.out" \
	2>"$work/same-source-exchange.err" &
same_source_exchange_pid=$!
for attempt in {1..100}; do
	[[ -e $same_source_exchange_ready ]] && break
	sleep 0.05
done
[[ -e $same_source_exchange_ready ]]
same_exchange_name=$(awk -F= '$1 == "exchange_file" { print $2; exit }' \
	"$state_home/dwm-titus/appearance/transaction.meta")
[[ $same_exchange_name =~ ^\.themes\.toml\.[A-Za-z0-9]+$ ]]
same_exchange_path=${themes_file%/*}/$same_exchange_name
[[ -f $same_exchange_path ]]
same_source_hash=$(sha256sum "$themes_file" | awk '{print $1}')
kill -KILL "$same_source_exchange_pid"
wait "$same_source_exchange_pid" 2>/dev/null || true
run_theme recover >"$work/same-source-exchange-recover.out" \
	2>"$work/same-source-exchange-recover.err"
grep -Fqx $'result\trecovered' "$work/same-source-exchange-recover.out"
[[ ! -e $same_exchange_path ]]
grep -Fqx "$same_source_hash" \
	"$state_home/dwm-titus/appearance/integration-suppress"
[[ $(active_theme) == nord ]]

reset_fixture
source_exchange_ready=$work/source-exchange.ready
source_exchange_release=$work/source-exchange.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
	DWM_TEST_APPLY_LOG=$work/apply.log DWM_TEST_RELOAD_LOG=$work/reload.log \
	DWM_TEST_SOURCE_EXCHANGE_READY=$source_exchange_ready \
	DWM_TEST_SOURCE_EXCHANGE_RELEASE=$source_exchange_release \
	"$helper" apply dracula >"$work/source-exchange.out" 2>"$work/source-exchange.err" &
source_exchange_pid=$!
for attempt in {1..100}; do
	[[ -e $source_exchange_ready ]] && break
	sleep 0.05
done
[[ -e $source_exchange_ready ]]
exchange_name=$(awk -F= '$1 == "exchange_file" { print $2; exit }' \
	"$state_home/dwm-titus/appearance/transaction.meta")
[[ $exchange_name =~ ^\.themes\.toml\.[A-Za-z0-9]+$ ]]
exchange_path=${themes_file%/*}/$exchange_name
printf '\n# retained external source edit\n' >>"$exchange_path"
kill -KILL "$source_exchange_pid"
wait "$source_exchange_pid" 2>/dev/null || true
if run_theme recover >"$work/source-exchange-recover.out" \
	2>"$work/source-exchange-recover.err"; then
	printf 'recovery discarded a journaled external source edit\n' >&2
	exit 1
fi
grep -Fq "external theme edit retained at $exchange_path" "$work/source-exchange-recover.err"
grep -Fqx '# retained external source edit' "$exchange_path"

reset_fixture
integration_lock_ready=$work/integration-lock.ready
integration_lock_release=$work/integration-lock.release
(
	exec 7>"$runtime_dir/dwm-theme-apply.lock"
	flock 7
	: >"$integration_lock_ready"
	while [[ ! -e $integration_lock_release ]]; do sleep 0.01; done
) &
integration_lock_pid=$!
for attempt in {1..100}; do
	[[ -e $integration_lock_ready ]] && break
	sleep 0.05
done
[[ -e $integration_lock_ready ]]
run_theme preview serialized-baseline 10 dracula >"$work/serialized-baseline.out" \
	2>"$work/serialized-baseline.err" &
serialized_preview_pid=$!
sleep 0.1
kill -0 "$serialized_preview_pid"
[[ $(active_theme) == nord ]]
: >"$integration_lock_release"
wait "$integration_lock_pid"
wait "$serialized_preview_pid"
[[ $(active_theme) == dracula ]]
run_theme revert serialized-baseline >/dev/null

reset_fixture
sed -i 's/^\[active\]$/  [active] # retained header comment/' "$themes_file"
sed -i 's/^\[theme.dracula\]$/  [theme.dracula] # retained theme comment/' "$themes_file"
run_theme apply dracula >/dev/null 2>"$work/commented-header.err"
grep -Fqx '  [active] # retained header comment' "$themes_file"
[[ $(grep -Fxc '  [active] # retained header comment' "$themes_file") == 1 ]]
grep -Fqx '  [theme.dracula] # retained theme comment' "$themes_file"
[[ $(active_theme) == dracula ]]

reset_fixture
printf '\n[colors]\n' >>"$themes_file"
awk '
	$0 == "[theme.nord]" { copy = 1; next }
	copy && /^\[theme\./ { exit }
	copy { print }
' "$managed_file" >>"$themes_file"
run_theme apply dracula >/dev/null 2>"$work/legacy-alongside.err"
[[ $(active_theme) == dracula ]]

reset_fixture
sed -i 's/theme = "nord"/theme = "missing theme"/' "$themes_file"
invalid_baseline=$(sha256sum "$themes_file")
invalid_preview=$(run_theme preview invalid-current 10 dracula 2>"$work/invalid-current.err")
grep -Fqx $'preview\tinvalid-current\t10\tdracula\tmissing theme' <<<"$invalid_preview"
[[ $(active_theme) == dracula ]]
run_theme revert invalid-current >/dev/null
[[ $(sha256sum "$themes_file") == "$invalid_baseline" ]]

reset_fixture
run_theme apply dracula >/dev/null 2>"$work/preview-baseline.err"

preview_output=$(run_theme preview preview-keep 10 nord 2>"$work/preview-keep.err")
grep -Fqx $'preview\tpreview-keep\t10\tnord\tdracula' <<<"$preview_output"
[[ $(active_theme) == nord ]]
status_output=$(run_theme preview-status preview-keep)
grep -Fqx $'preview-active\tpreview-keep\tnord' <<<"$status_output"
grep -Eq $'^preview-remaining\t([1-9]|10)$' <<<"$status_output"
keep_output=$(run_theme keep preview-keep)
grep -Fqx $'result\tkeep\tpreview-keep\tnord' <<<"$keep_output"
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme preview keep-live-race 10 dracula >/dev/null 2>"$work/keep-live-race-preview.err"
keep_live_ready=$work/keep-live-race.ready
keep_live_release=$work/keep-live-race.release
DWM_TEST_LIVE_ONLY_READY=$keep_live_ready DWM_TEST_LIVE_ONLY_RELEASE=$keep_live_release \
	run_theme keep keep-live-race >"$work/keep-live-race.out" 2>"$work/keep-live-race.err" &
keep_live_pid=$!
for attempt in {1..100}; do
	[[ -e $keep_live_ready ]] && break
	sleep 0.05
done
[[ -e $keep_live_ready ]]
sed -i '0,/theme = "dracula"/s//theme = "nord"/' "$themes_file"
: >"$keep_live_release"
set +e
wait "$keep_live_pid"
keep_live_status=$?
set -e
[[ $keep_live_status -ne 0 ]]
grep -Fq 'changed during preview confirmation' "$work/keep-live-race.err"
[[ ! -s $work/keep-live-race.out ]]
[[ $(active_theme) == nord ]]
grep -Fqx $'preview-active\tkeep-live-race\tdracula' < <(run_theme preview-status keep-live-race)
run_theme revert keep-live-race >/dev/null
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
slow_started=$(date +%s)
DWM_TEST_APPLY_DELAY=2 run_theme preview slow-preview 1 dracula >/dev/null \
	2>"$work/slow-preview.err"
slow_prefix=$state_home/dwm-titus/appearance/slow-preview.preview
slow_deadline=$(awk -F= '$1 == "deadline" { print $2 }' "$slow_prefix.meta")
((slow_deadline >= slow_started + 3 && slow_deadline <= slow_started + 5))
wait_for_theme nord
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme preview cancelled-watchdog 99 dracula >/dev/null 2>"$work/cancelled-watchdog.err"
cancel_prefix=$state_home/dwm-titus/appearance/cancelled-watchdog.preview
cancel_pid=$(awk -F= '$1 == "watchdog_pid" { print $2 }' "$cancel_prefix.meta")
process_is_running "$cancel_pid"
run_theme keep cancelled-watchdog >/dev/null
for attempt in {1..20}; do
	if ! process_is_running "$cancel_pid"; then
		break
	fi
	sleep 0.05
done
if process_is_running "$cancel_pid"; then
	printf 'confirmed preview left its watchdog running\n' >&2
	exit 1
fi

reset_fixture
run_theme preview orphaned-claim 1 dracula >/dev/null 2>"$work/orphaned-claim.err"
mkdir -p "$state_home/dwm-titus/appearance/orphaned-claim.preview.claim"
wait_for_theme nord
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme preview preview-revert 10 dracula >/dev/null 2>"$work/preview-revert.err"
[[ $(active_theme) == dracula ]]
run_theme revert preview-revert >"$work/revert.out"
grep -Fqx $'result\trevert\tpreview-revert\tdracula' "$work/revert.out"
[[ $(active_theme) == nord ]]

reset_fixture
mkdir -p "$config_home/alacritty" "$config_home/kitty" "$config_home/gtk-3.0" \
	"$config_home/qt6ct"
printf '%s\n' 'import = [' '  "~/.config/alacritty/custom-theme.toml",' ']' \
	>"$config_home/alacritty/alacritty.toml"
printf '# custom kitty configuration\n' >"$config_home/kitty/kitty.conf"
printf '[Settings]\ngtk-theme-name=Custom\n' >"$config_home/gtk-3.0/settings.ini"
printf 'gtk-theme-name="Custom"\n' >"$home_dir/.gtkrc-2.0"
printf 'Xcursor.theme: Custom\n' >"$config_home/dwm-titus/cursor.Xresources"
printf 'export QT_QPA_PLATFORMTHEME=custom\n' >"$config_home/dwm-titus/theme-env.sh"
printf '[Appearance]\ncolor_scheme_path=/custom\n' >"$config_home/qt6ct/qt6ct.conf"
chmod 640 "$config_home/alacritty/alacritty.toml" "$config_home/kitty/kitty.conf" \
	"$config_home/gtk-3.0/settings.ini" "$home_dir/.gtkrc-2.0" \
	"$config_home/dwm-titus/cursor.Xresources" "$config_home/dwm-titus/theme-env.sh" \
	"$config_home/qt6ct/qt6ct.conf"
integration_before=$(integration_snapshot)
: >"$work/live.log"
run_theme_real_apply preview integration-files 10 dracula >/dev/null 2>"$work/integration-preview.err"
[[ -f $work/kitty-reload.marker ]]
[[ -f $config_home/alacritty/active-theme.toml ]]
[[ -f $config_home/kitty/active-theme.conf ]]
[[ -f $config_home/gtk-4.0/settings.ini ]]
integration_transaction=$state_home/dwm-titus/appearance/integration-transaction
integration_preview=$(integration_snapshot)
printf '%s pending\n' "$(sha256sum "$themes_file" | awk '{print $1}')" >"$integration_transaction"
chmod 600 "$integration_transaction"
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_THEME_APPLY_AUTOMATIC=1 DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-pending-automatic.out" 2>"$work/integration-pending-automatic.err"
[[ $(integration_snapshot) == "$integration_preview" ]]
[[ ! -s $work/live.log ]]
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_TEST_LIVE_LOG=$work/live.log PATH=$work/integration-bin:$PATH \
	"$repo/scripts/theme-apply.sh" >"$work/integration-pending-manual.out" \
	2>"$work/integration-pending-manual.err"
[[ $(integration_snapshot) == "$integration_preview" ]]
[[ ! -s $work/live.log ]]
printf '%s ready\n' "$(sha256sum "$themes_file" | awk '{print $1}')" >"$integration_transaction"
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_THEME_APPLY_AUTOMATIC=1 DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-preview-automatic.out" 2>"$work/integration-preview-automatic.err"
[[ ! -s $work/live.log ]]
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_TEST_LIVE_LOG=$work/live.log PATH=$work/integration-bin:$PATH \
	"$repo/scripts/theme-apply.sh" >"$work/integration-preview-manual.out" \
	2>"$work/integration-preview-manual.err"
[[ $(integration_snapshot) == "$integration_preview" ]]
[[ ! -s $work/live.log ]]
run_theme_real_apply revert integration-files >/dev/null 2>"$work/integration-revert.err"
[[ $(integration_snapshot) == "$integration_before" ]]
suppression_file=$state_home/dwm-titus/appearance/integration-suppress
suppression_hash=$(sha256sum "$themes_file" | awk '{print $1}')
cmp -s <(printf '%s\n' "$suppression_hash") "$suppression_file"
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_THEME_APPLY_AUTOMATIC=1 DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-late-apply.out" 2>"$work/integration-late-apply.err"
[[ $(integration_snapshot) == "$integration_before" ]]
[[ -f $suppression_file ]]
printf '%s 0\n' "$(sha256sum "$themes_file" | awk '{print $1}')" >"$suppression_file"
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_THEME_APPLY_AUTOMATIC=1 DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-expired-suppress.out" 2>"$work/integration-expired-suppress.err"
[[ $(integration_snapshot) == "$integration_before" ]]
grep -Fqx "theme-apply: applied theme 'nord'" "$work/integration-expired-suppress.out"
other_themes=$work/other-themes.toml
cp "$themes_file" "$other_themes"
sed -i '0,/theme = "nord"/s//theme = "dracula"/' "$other_themes"
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$other_themes DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_THEME_APPLY_AUTOMATIC=1 DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-other-apply.out" 2>"$work/integration-other-apply.err"
[[ ! -f $suppression_file ]]
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_TEST_LIVE_LOG=$work/live.log \
	PATH=$work/integration-bin:$PATH "$repo/scripts/theme-apply.sh" \
	>"$work/integration-manual-apply.out" 2>"$work/integration-manual-apply.err"
[[ $(integration_snapshot) != "$integration_before" ]]
grep -Fqx gsettings "$work/live.log"
grep -Fqx xfconf-query "$work/live.log"

reset_fixture
mkdir -p "$config_home/alacritty"
printf '# integration baseline\n' >"$config_home/alacritty/active-theme.toml"
capture_ready=$work/integration-capture.ready
capture_release=$work/integration-capture.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
	DWM_TEST_APPLY_LOG=$work/apply.log DWM_TEST_RELOAD_LOG=$work/reload.log \
	DWM_TEST_INTEGRATION_CAPTURE_READY=$capture_ready \
	DWM_TEST_INTEGRATION_CAPTURE_RELEASE=$capture_release \
	"$helper" preview integration-capture 10 dracula \
	>"$work/integration-capture.out" 2>"$work/integration-capture.err" &
capture_pid=$!
for attempt in {1..100}; do
	[[ -e $capture_ready ]] && break
	sleep 0.05
done
[[ -e $capture_ready ]]
printf '# changed during capture\n' >>"$config_home/alacritty/active-theme.toml"
: >"$capture_release"
set +e
wait "$capture_pid"
capture_status=$?
set -e
[[ $capture_status -ne 0 ]]
grep -Fq 'theme integration changed during baseline capture' "$work/integration-capture.err"

reset_fixture
mkdir -p "$config_home/alacritty"
printf '%s\n' 'import = [' '  "~/.config/alacritty/custom-theme.toml",' ']' \
	>"$config_home/alacritty/alacritty.toml"
run_theme_real_apply preview integration-external 10 dracula >/dev/null 2>"$work/integration-external-preview.err"
printf '# external integration edit\n' >>"$config_home/alacritty/alacritty.toml"
integration_external_before=$(integration_snapshot)
if run_theme_real_apply keep integration-external >"$work/integration-external-keep.out" \
	2>"$work/integration-external-keep.err"; then
	printf 'preview with an external integration edit was confirmed\n' >&2
	exit 1
fi
grep -Fq 'theme integration changed outside the preview' "$work/integration-external-keep.err"
if run_theme_real_apply revert integration-external >"$work/integration-external-revert.out" \
	2>"$work/integration-external-revert.err"; then
	printf 'external integration edit was overwritten by preview rollback\n' >&2
	exit 1
fi
grep -Fq 'refusing to overwrite it' "$work/integration-external-revert.err"
grep -Fqx '# external integration edit' "$config_home/alacritty/alacritty.toml"
[[ $(integration_snapshot) == "$integration_external_before" ]]
[[ $(active_theme) == dracula ]]
run_theme_real_apply abandon integration-external >/dev/null

reset_fixture
mkdir -p "$config_home/alacritty"
printf '%s\n' 'import = [' '  "~/.config/alacritty/custom-theme.toml",' ']' \
	>"$config_home/alacritty/alacritty.toml"
publish_ready=$work/integration-publish.ready
publish_release=$work/integration-publish.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$repo/scripts/theme-apply.sh \
	DWM_APPEARANCE_RELOAD_HELPER=$reload_stub DWM_TEST_RELOAD_LOG=$work/reload.log \
	DWM_TEST_LIVE_LOG=$work/live.log PATH=$work/integration-bin:$PATH \
	DWM_TEST_BEFORE_INTEGRATION_PUBLISH=$publish_ready \
	DWM_TEST_INTEGRATION_PUBLISH_RELEASE=$publish_release \
	"$helper" preview integration-publish-race 10 dracula \
	>"$work/integration-publish-race.out" 2>"$work/integration-publish-race.err" &
publish_race_pid=$!
for attempt in {1..100}; do
	[[ -e $publish_ready ]] && break
	sleep 0.05
done
[[ -e $publish_ready ]]
printf '# external integration edit before publish\n' >>"$config_home/alacritty/alacritty.toml"
: >"$publish_release"
set +e
wait "$publish_race_pid"
publish_race_status=$?
set -e
[[ $publish_race_status -eq 1 ]]
grep -Fq 'changed while publishing the transaction' "$work/integration-publish-race.err"
grep -Fqx '# external integration edit before publish' \
	"$config_home/alacritty/alacritty.toml"
[[ -f $state_home/dwm-titus/appearance/integration-publish-race.preview.meta ]]

reset_fixture
mkdir -p "$config_home/alacritty"
printf 'baseline integration content\n' >"$config_home/alacritty/alacritty.toml"
integration_race_ready=$work/integration-race.ready
integration_race_release=$work/integration-race.release
DWM_TEST_BEFORE_INTEGRATION_READY=$integration_race_ready \
	DWM_TEST_BEFORE_INTEGRATION_RELEASE=$integration_race_release \
	run_theme preview integration-race 10 dracula >"$work/integration-race.out" \
	2>"$work/integration-race.err" &
integration_race_pid=$!
for attempt in {1..100}; do
	[[ -e $integration_race_ready ]] && break
	sleep 0.05
done
[[ -e $integration_race_ready ]]
printf 'external integration content\n' >"$config_home/alacritty/alacritty.toml"
: >"$integration_race_release"
set +e
wait "$integration_race_pid"
integration_race_status=$?
set -e
[[ $integration_race_status -ne 0 ]]
grep -Fq 'refusing to overwrite it' "$work/integration-race.err"
grep -Fqx 'external integration content' "$config_home/alacritty/alacritty.toml"
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

run_theme preview preview-expire 3 dracula >/dev/null 2>"$work/preview-expire.err"
[[ $(active_theme) == dracula ]]
wait_for_theme nord
for attempt in {1..100}; do
	[[ $(run_theme preview-status preview-expire | tail -n 1) == $'result\texpired\tpreview-expire' ]] && break
	sleep 0.05
done
[[ $(run_theme preview-status preview-expire | tail -n 1) == $'result\texpired\tpreview-expire' ]]

run_theme preview preview-stale 10 dracula >/dev/null 2>"$work/preview-stale.err"
printf '\n# external change\n' >>"$themes_file"
if run_theme revert preview-stale 2>"$work/stale.err"; then
	printf 'stale preview rollback overwrote an external change\n' >&2
	exit 1
fi
grep -Fq 'refusing to overwrite it' "$work/stale.err"
grep -Fqx '# external change' "$themes_file"
grep -Fqx $'preview-failed\tpreview-stale\tExternal changes prevented automatic rollback; recovery state was retained.' \
	< <(run_theme preview-status preview-stale)
abandon_output=$(run_theme abandon preview-stale)
grep -Fqx $'result\tabandon\tpreview-stale\tdracula' <<<"$abandon_output"
grep -Fqx '# external change' "$themes_file"
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme apply dracula >/dev/null 2>"$work/apply-dracula.err"
reset_output=$(run_theme reset 2>"$work/reset.err")
grep -Fqx $'result\treset\tnord\tdracula' <<<"$reset_output"
[[ $(active_theme) == nord ]]

reset_fixture
{
	printf '%s\n' '[active]' 'theme = "dracula"' '' '[appearance]' 'borderpx = 2' ''
	awk '
		$0 == "[theme.dracula]" { in_theme = 1 }
		in_theme && /^\[theme\./ && $0 != "[theme.dracula]" { exit }
		in_theme { print }
	' "$managed_file"
} >"$themes_file"
chmod 640 "$themes_file"
reset_output=$(run_theme reset 2>"$work/reset-custom.err")
grep -Fqx $'result\treset\tnord\tdracula' <<<"$reset_output"
[[ $(active_theme) == nord ]]
[[ $(stat -c %a "$themes_file") == 640 ]]
grep -Fqx '[theme.dracula]' "$themes_file"
grep -Fqx '[theme.nord]' "$themes_file"
grep -Fqx 'borderpx = 2' "$themes_file"

reset_fixture
if DWM_TEST_APPLY_FAIL_THEME=dracula run_theme preview preview-failed 10 dracula \
	>"$work/preview-failed.out" 2>"$work/preview-failed.err"; then
	printf 'failed preview was reported as successful\n' >&2
	exit 1
fi
grep -Fq 'did not converge; restoring the previous theme' "$work/preview-failed.err"
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)
run_theme apply dracula >/dev/null 2>"$work/apply-after-failed-preview.err"
[[ $(active_theme) == dracula ]]

reset_fixture
run_theme preview failed-rollback-keep 10 dracula >/dev/null 2>"$work/failed-rollback-preview.err"
if DWM_TEST_APPLY_FAIL_THEME=nord run_theme revert failed-rollback-keep \
	>"$work/failed-rollback-revert.out" 2>"$work/failed-rollback-revert.err"; then
	printf 'failed integration rollback was reported as successful\n' >&2
	exit 1
fi
grep -Fq 'theme rollback failed; recovery state was retained' "$work/failed-rollback-revert.err"
if run_theme keep failed-rollback-keep >"$work/failed-rollback-keep.out" \
	2>"$work/failed-rollback-keep.err"; then
	printf 'failed preview rollback was incorrectly confirmable\n' >&2
	exit 1
fi
grep -Fq 'rollback failed; refusing to confirm stale state' "$work/failed-rollback-keep.err"
run_theme revert failed-rollback-keep >/dev/null 2>"$work/failed-rollback-retry.err"
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme preview reused-token 5 dracula >/dev/null 2>"$work/reused-first.err"
run_theme keep reused-token >/dev/null
run_theme preview reused-token 10 nord >/dev/null 2>"$work/reused-second.err"
sleep 6
[[ $(active_theme) == nord ]]
grep -Fqx $'preview-active\treused-token\tnord' < <(run_theme preview-status reused-token)
run_theme revert reused-token >/dev/null
[[ $(active_theme) == dracula ]]

reset_fixture
run_theme preview durable-preview 10 dracula >/dev/null 2>"$work/durable-preview.err"
durable_prefix=$state_home/dwm-titus/appearance/durable-preview.preview
[[ -f $durable_prefix.meta ]]
sed -i 's/^deadline=.*/deadline=0/' "$durable_prefix.meta"
# A reboot removes the runtime directory only after terminating session
# processes. Stop the pre-reboot watchdog before recreating its lock path so
# the fixture cannot leave processes synchronized on different lock inodes.
durable_watchdog_pid=$(awk -F= '$1 == "watchdog_pid" { print $2; exit }' \
	"$durable_prefix.meta")
[[ $durable_watchdog_pid =~ ^[1-9][0-9]*$ ]]
kill -TERM "$durable_watchdog_pid" 2>/dev/null || true
for attempt in {1..100}; do
	[[ ! -r /proc/$durable_watchdog_pid/stat ]] && break
	durable_watchdog_state=$(awk '{ line = $0; sub(/^.*\) /, "", line); print substr(line, 1, 1) }' \
		"/proc/$durable_watchdog_pid/stat" 2>/dev/null || true)
	[[ -z $durable_watchdog_state || $durable_watchdog_state == Z ]] && break
	sleep 0.02
done
rm -rf "$runtime_dir"
mkdir -p "$runtime_dir"
run_theme _resume-preview
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
run_theme preview startup-unconfirmed 10 dracula >/dev/null \
	2>"$work/startup-unconfirmed-preview.err"
run_theme _resume-preview
[[ $(active_theme) == nord ]]
grep -Fqx $'result\tnone' < <(run_theme preview-status)

reset_fixture
mkdir -p "$state_home/dwm-titus/appearance"
printf 'orphan-preview\n' >"$state_home/dwm-titus/appearance/preview.current"
grep -Fqx $'result\tnone' < <(run_theme preview-status)
[[ ! -e $state_home/dwm-titus/appearance/preview.current ]]

reset_fixture
run_theme preview stale-keep 10 dracula >/dev/null 2>"$work/stale-keep-preview.err"
sed -i '0,/theme = "dracula"/s//theme = "nord"/' "$themes_file"
printf '\n# stale keep\n' >>"$themes_file"
if run_theme keep stale-keep 2>"$work/stale-keep.err"; then
	printf 'stale preview confirmation was accepted\n' >&2
	exit 1
fi
grep -Fq 'refusing to confirm stale state' "$work/stale-keep.err"
[[ ! -d $state_home/dwm-titus/appearance/stale-keep.preview.claim ]]
if run_theme revert stale-keep 2>"$work/stale-keep-revert.err"; then
	printf 'stale preview rollback overwrote an external change\n' >&2
	exit 1
fi
grep -Fq 'refusing to overwrite it' "$work/stale-keep-revert.err"
[[ ! -d $state_home/dwm-titus/appearance/stale-keep.preview.claim ]]
run_theme abandon stale-keep >"$work/stale-keep-abandon.out"
grep -Fqx $'result\tabandon\tstale-keep\tnord' "$work/stale-keep-abandon.out"
if ! grep -Fqx nord "$work/live-only.log"; then
	printf 'abandon did not live-converge the accepted source\n' >&2
	sed 's/^/live-only: /' "$work/live-only.log" >&2
	exit 1
fi
[[ $(grep -Fxc reload "$work/reload.log") == 1 ]]
run_theme apply nord >/dev/null 2>"$work/apply-after-abandon.err"
[[ $(active_theme) == nord ]]

reset_fixture
if DWM_TEST_LIVE_ONLY_FAIL_THEME=dracula run_theme apply dracula \
	>"$work/live-only-fail.out" 2>"$work/live-only-fail.err"; then
	printf 'failed final live convergence was reported as successful\n' >&2
	exit 1
fi
grep -Fq 'live convergence failed' "$work/live-only-fail.err"
[[ $(active_theme) == nord ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
apply_live_ready=$work/apply-live-race.ready
apply_live_release=$work/apply-live-race.release
DWM_TEST_LIVE_ONLY_READY=$apply_live_ready DWM_TEST_LIVE_ONLY_RELEASE=$apply_live_release \
	run_theme apply dracula >"$work/apply-live-race.out" 2>"$work/apply-live-race.err" &
apply_live_pid=$!
for attempt in {1..100}; do
	[[ -e $apply_live_ready ]] && break
	sleep 0.05
done
[[ -e $apply_live_ready ]]
sed -i '0,/theme = "dracula"/s//theme = "nord"/' "$themes_file"
: >"$apply_live_release"
set +e
wait "$apply_live_pid"
apply_live_status=$?
set -e
[[ $apply_live_status -ne 0 ]]
grep -Fq 'changed during final live convergence' "$work/apply-live-race.err"
[[ ! -s $work/apply-live-race.out ]]
[[ $(active_theme) == nord ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
failure_hash=$(sha256sum "$themes_file")
if DWM_TEST_APPLY_FAIL=1 run_theme apply dracula >"$work/fail.out" 2>"$work/fail.err"; then
	printf 'failed integration apply was reported as successful\n' >&2
	exit 1
fi
grep -Fq 'did not converge; restoring the previous theme' "$work/fail.err"
[[ $(sha256sum "$themes_file") == "$failure_hash" ]]
[[ -e $state_home/dwm-titus/appearance/transaction.meta ]]
if [[ -s $work/fail.out ]]; then
	printf 'failed apply emitted a success protocol\n' >&2
	exit 1
fi
recover_output=$(run_theme recover 2>"$work/fail-recover.err")
grep -Fqx $'result\trecovered' <<<"$recover_output"
[[ ! -e $state_home/dwm-titus/appearance/transaction.meta ]]

reset_fixture
signal_ready=$work/signal.ready
signal_release=$work/signal.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/apply.log \
	DWM_TEST_APPLY_READY=$signal_ready DWM_TEST_APPLY_WAIT=$signal_release \
	"$helper" apply dracula >"$work/signal.out" 2>"$work/signal.err" &
signal_pid=$!
for attempt in {1..100}; do
	[[ -e $signal_ready ]] && break
	sleep 0.05
done
[[ -e $signal_ready ]]
run_theme recovery-status >"$work/concurrent-recovery-status.out" &
recovery_status_pid=$!
sleep 0.1
if ! kill -0 "$recovery_status_pid" 2>/dev/null; then
	printf 'recovery status did not wait for the active transaction\n' >&2
	exit 1
fi
kill -TERM "$signal_pid"
: >"$signal_release"
set +e
wait "$signal_pid"
signal_status=$?
set -e
[[ $signal_status -eq 143 ]]
wait "$recovery_status_pid"
grep -Fqx $'recovery\tnone' "$work/concurrent-recovery-status.out"
[[ $(active_theme) == nord ]]
[[ ! -e $state_home/dwm-titus/appearance/transaction.meta ]]
if [[ -s $work/signal.out ]]; then
	printf 'interrupted apply emitted a success protocol\n' >&2
	exit 1
fi

reset_fixture
finish_ready=$work/finish.ready
finish_release=$work/finish.release
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
	DWM_TEST_APPLY_LOG=$work/apply.log DWM_TEST_LIVE_ONLY_LOG=$work/live-only.log \
	DWM_TEST_RELOAD_LOG=$work/reload.log DWM_TEST_FINISH_READY=$finish_ready \
	DWM_TEST_FINISH_RELEASE=$finish_release \
	"$helper" apply dracula >"$work/finish.out" 2>"$work/finish.err" &
finish_pid=$!
for attempt in {1..100}; do
	[[ -e $finish_ready ]] && break
	sleep 0.05
done
[[ -e $finish_ready ]]
kill -TERM "$finish_pid"
set +e
wait "$finish_pid"
finish_status=$?
set -e
[[ $finish_status -eq 143 ]]
[[ ! -e $state_home/dwm-titus/appearance/integration-transaction ]]
grep -Fqx $'recovery\tavailable\tapply\tdracula' < <(run_theme recovery-status)
# Emulate recovery metadata left by the previous release, whose integration
# list had the same first eleven paths and no personalization or XSETTINGS entry.
rm -f -- "$state_home/dwm-titus/appearance/transaction.integration.11.before" \
	"$state_home/dwm-titus/appearance/transaction.integration.11.after" \
	"$state_home/dwm-titus/appearance/transaction.integration.11.meta" \
	"$state_home/dwm-titus/appearance/transaction.integration.12.before" \
	"$state_home/dwm-titus/appearance/transaction.integration.12.after" \
	"$state_home/dwm-titus/appearance/transaction.integration.12.meta"
printf '11\n' >"$state_home/dwm-titus/appearance/transaction.integration.count"
run_theme recover >/dev/null
[[ $(active_theme) == nord ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
rm "$themes_file"
run_theme preview preview-absent 10 dracula >/dev/null 2>"$work/preview-absent.err"
[[ -f $themes_file && $(active_theme) == dracula ]]
rm "$themes_file"
run_theme revert preview-absent >/dev/null
[[ ! -e $themes_file ]]
suppression_hash=$(sha256sum "$managed_file" | awk '{print $1}')
cmp -s <(printf '%s\n' "$suppression_hash") \
	"$state_home/dwm-titus/appearance/integration-suppress"
grep -Fqx nord "$work/live-only.log"
[[ $(grep -Fxc reload "$work/reload.log") == 2 ]]

reset_fixture
ready=$work/interrupted.ready
release=$work/interrupted.release
child_pid_file=$work/interrupted.pid
HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_TEST_APPLY_LOG=$work/apply.log \
	DWM_TEST_APPLY_READY=$ready DWM_TEST_APPLY_WAIT=$release DWM_TEST_APPLY_PID=$child_pid_file \
	"$helper" apply dracula >"$work/interrupted.out" 2>"$work/interrupted.err" &
interrupted_pid=$!
for attempt in {1..100}; do
	[[ -e $ready && -s $child_pid_file ]] && break
	sleep 0.05
done
[[ -e $ready && -s $child_pid_file ]]
kill -KILL "$interrupted_pid"
kill -KILL "$(<"$child_pid_file")" 2>/dev/null || true
wait "$interrupted_pid" 2>/dev/null || true
[[ $(active_theme) == dracula ]]
grep -Fqx $'recovery\tavailable\tapply\tdracula' < <(run_theme recovery-status)
mkdir -p "$config_home/alacritty"
printf '# later external edit\n' >"$config_home/alacritty/active-theme.toml"
if run_theme recover >"$work/recover-external.out" 2>"$work/recover-external.err"; then
	printf 'interrupted recovery overwrote an integration edit with an unknown after-state\n' >&2
	exit 1
fi
grep -Fq 'integration file changed after the interrupted transaction' \
	"$work/recover-external.err"
rm "$config_home/alacritty/active-theme.toml"
recover_output=$(run_theme recover 2>"$work/recover.err")
grep -Fqx $'result\trecovered' <<<"$recover_output"
[[ $(active_theme) == nord ]]
grep -Fqx nord "$work/live-only.log"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
run_theme mutation-ready
run_theme personalization-ready
printf 'broken-protocol\n' >"$config_home/dwm-titus/personalization.conf"
if run_theme personalization-ready; then
	printf 'malformed personalization state was reported ready\n' >&2
	exit 1
fi
run_theme personalization-repair-ready
cp "$config_home/dwm-titus/personalization.conf" "$work/personalization-malformed.before"
mkdir -p "$config_home/gtk-3.0"
printf '[Settings]\nkeep-repair=yes\n' >"$config_home/gtk-3.0/settings.ini"
chmod 444 "$config_home/gtk-3.0/settings.ini"
mkdir -p "$config_home/alacritty"
chmod 500 "$config_home/alacritty"
run_theme personalization-repair-ready
cp -p "$config_home/gtk-3.0/settings.ini" "$work/personalization-repair-gtk.before"
repair_gtk_identity=$(stat -c '%d:%i' "$config_home/gtk-3.0/settings.ini")
repair_apply_count=$(wc -l <"$work/apply.log")
repair_live_count=$(wc -l <"$work/live-only.log")
repair_output=$(run_theme personalize-repair 2>"$work/personalization-repair.err")
grep -Fqx $'personalization-action-protocol\t1\t0' <<<"$repair_output"
grep -Fqx $'result\trepair\tall\tfollow-sources' <<<"$repair_output"
grep -Fqx $'personalization-protocol\t1\t0' \
	"$config_home/dwm-titus/personalization.conf"
[[ $(wc -l <"$config_home/dwm-titus/personalization.conf") == 1 ]]
cmp -s "$work/personalization-repair-gtk.before" \
	"$config_home/gtk-3.0/settings.ini"
[[ $(stat -c %a "$config_home/gtk-3.0/settings.ini") == 444 ]]
[[ $(stat -c '%d:%i' "$config_home/gtk-3.0/settings.ini") == "$repair_gtk_identity" ]]
[[ $(stat -c %a "$config_home/alacritty") == 500 ]]
[[ $(wc -l <"$work/apply.log") == "$repair_apply_count" ]]
[[ $(wc -l <"$work/live-only.log") == "$repair_live_count" ]]
[[ ! -e $work/kitty-reload.marker ]]
chmod 640 "$config_home/gtk-3.0/settings.ini"
chmod 700 "$config_home/alacritty"
run_theme personalization-ready
if run_theme personalization-repair-ready; then
	printf 'valid personalization state was reported repairable\n' >&2
	exit 1
fi
if run_theme personalize-repair >"$work/personalization-repair-valid.out" \
	2>"$work/personalization-repair-valid.err"; then
	printf 'valid personalization state was repaired unnecessarily\n' >&2
	exit 1
fi
grep -Fq 'personalization configuration does not need repair' \
	"$work/personalization-repair-valid.err"
printf 'personalization-protocol\t2\t0' \
	>"$config_home/dwm-titus/personalization.conf"
if run_theme personalization-repair-ready; then
	printf 'unsupported personalization protocol was reported repairable\n' >&2
	exit 1
fi
if run_theme personalize-repair >"$work/personalization-repair-unsupported.out" \
	2>"$work/personalization-repair-unsupported.err"; then
	printf 'unsupported personalization protocol was destructively repaired\n' >&2
	exit 1
fi
grep -Fq 'personalization protocol is unsupported; refusing destructive repair' \
	"$work/personalization-repair-unsupported.err"
grep -Fqx $'personalization-protocol\t2\t0' \
	"$config_home/dwm-titus/personalization.conf"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)
printf 'broken-protocol\n' >"$config_home/dwm-titus/personalization.conf"
repair_ready=$work/personalization-repair-race.ready
repair_release=$work/personalization-repair-race.release
DWM_TEST_PERSONALIZATION_REPAIR_READY=$repair_ready \
	DWM_TEST_PERSONALIZATION_REPAIR_RELEASE=$repair_release \
	run_theme personalize-repair >"$work/personalization-repair-race.out" \
	2>"$work/personalization-repair-race.err" &
repair_pid=$!
for attempt in {1..100}; do
	[[ -e $repair_ready ]] && break
	sleep 0.05
done
[[ -e $repair_ready ]]
printf 'personalization-protocol\t1\t0\nqt\tgtk3\n' \
	>"$config_home/dwm-titus/personalization.conf"
: >"$repair_release"
if wait "$repair_pid"; then
	printf 'personalization repair overwrote a concurrent valid edit\n' >&2
	exit 1
fi
grep -Fqx $'qt\tgtk3' "$config_home/dwm-titus/personalization.conf"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

printf 'broken-protocol\n' >"$config_home/dwm-titus/personalization.conf"
repair_recovery_theme_identity=$(stat -c '%d:%i' "$themes_file")
repair_recovery_gtk_identity=$(stat -c '%d:%i' "$config_home/gtk-3.0/settings.ini")
repair_finish_ready=$work/personalization-repair-finish.ready
repair_finish_release=$work/personalization-repair-finish.release
repair_process_pid=$work/personalization-repair-finish.pid
DWM_TEST_FINISH_READY=$repair_finish_ready DWM_TEST_FINISH_RELEASE=$repair_finish_release \
	DWM_TEST_PROCESS_PID=$repair_process_pid \
	run_theme personalize-repair >"$work/personalization-repair-finish.out" \
	2>"$work/personalization-repair-finish.err" &
repair_pid=$!
for attempt in {1..100}; do
	[[ -e $repair_finish_ready && -s $repair_process_pid ]] && break
	sleep 0.05
done
[[ -e $repair_finish_ready && -s $repair_process_pid ]]
kill -KILL "$(<"$repair_process_pid")"
wait "$repair_pid" 2>/dev/null || true
grep -Fqx $'recovery\tavailable\tpersonalize-repair\tnord' \
	< <(run_theme recovery-status)
mkdir -p "$config_home/alacritty"
printf '# unrelated edit after interrupted repair\n' \
	>"$config_home/alacritty/active-theme.toml"
run_theme recover >/dev/null 2>"$work/personalization-repair-recover.err"
cmp -s "$work/personalization-malformed.before" \
	"$config_home/dwm-titus/personalization.conf"
cmp -s "$work/personalization-repair-gtk.before" \
	"$config_home/gtk-3.0/settings.ini"
[[ $(stat -c '%d:%i' "$themes_file") == "$repair_recovery_theme_identity" ]]
[[ $(stat -c '%d:%i' "$config_home/gtk-3.0/settings.ini") == "$repair_recovery_gtk_identity" ]]
grep -Fqx '# unrelated edit after interrupted repair' \
	"$config_home/alacritty/active-theme.toml"
rm "$config_home/alacritty/active-theme.toml"
[[ ! -e $state_home/dwm-titus/appearance/integration-suppress ]]
ln "$themes_file" "$work/personalization-repair-hardlink-theme.toml"
if run_theme personalization-repair-ready; then
	printf 'repair was reported ready for a hard-linked theme source\n' >&2
	exit 1
fi
rm "$work/personalization-repair-hardlink-theme.toml"
mkdir -p "$work/personalization-repair-unsafe-integration"
ln -s "$work/personalization-repair-unsafe-integration" "$config_home/qt5ct"
if run_theme personalization-repair-ready; then
	printf 'repair was reported ready for an unsafe integration path\n' >&2
	exit 1
fi
rm "$config_home/qt5ct"
run_theme personalization-repair-ready
printf 'personalization-protocol\t1\t0\nqt\tgtk3\nqt\tqt6ct\n' \
	>"$config_home/dwm-titus/personalization.conf"
if run_theme personalization-ready; then
	printf 'duplicate personalization state was reported ready\n' >&2
	exit 1
fi
cp "$config_home/dwm-titus/personalization.conf" "$work/personalization-duplicate.before"
if run_theme personalize qt gtk3 >"$work/personalization-duplicate.out" \
	2>"$work/personalization-duplicate.err"; then
	printf 'personalization mutation replaced duplicate state\n' >&2
	exit 1
fi
grep -Fq 'personalization configuration is malformed or unsafe' \
	"$work/personalization-duplicate.err"
cmp -s "$work/personalization-duplicate.before" \
	"$config_home/dwm-titus/personalization.conf"
printf 'personalization-protocol\t1\t0\nqt\tgtk3\n' \
	>"$config_home/dwm-titus/personalization.conf"
ln "$config_home/dwm-titus/personalization.conf" "$work/personalization-hardlink.conf"
if run_theme personalization-ready; then
	printf 'hard-linked personalization state was reported ready\n' >&2
	exit 1
fi
if run_theme personalization-repair-ready; then
	printf 'hard-linked personalization state was reported safely repairable\n' >&2
	exit 1
fi
if run_theme personalize-repair >"$work/personalization-hardlink-repair.out" \
	2>"$work/personalization-hardlink-repair.err"; then
	printf 'hard-linked personalization state was repaired\n' >&2
	exit 1
fi
grep -Fq 'personalization configuration is unsafe' \
	"$work/personalization-hardlink-repair.err"
run_theme_apply_direct >/dev/null 2>"$work/personalization-hardlink.err"
grep -Fq 'ignoring invalid personalization configuration' \
	"$work/personalization-hardlink.err"
rm "$work/personalization-hardlink.conf"
rm "$config_home/dwm-titus/personalization.conf"
run_theme personalization-ready
sed -i '0,/theme = "nord"/s//theme = "missing-theme"/' "$themes_file"
run_theme mutation-ready
if run_theme personalization-ready; then
	printf 'invalid active theme was reported personalization-ready\n' >&2
	exit 1
fi

reset_fixture
printf 'broken-protocol\n' >"$config_home/dwm-titus/personalization.conf"
run_theme_real_apply apply dracula >/dev/null 2>"$work/personalization-invalid-base.err"
grep -Fq 'ignoring invalid personalization configuration' \
	"$work/personalization-invalid-base.err"
grep -Fqx 'broken-protocol' "$config_home/dwm-titus/personalization.conf"
[[ $(active_theme) == dracula ]]
reset_fixture

printf 'personalization-protocol\t1\t0\nfont\tunknown\n' \
	>"$config_home/dwm-titus/personalization.conf"
run_theme_real_apply apply dracula >/dev/null \
	2>"$work/personalization-reserved-name.err"
grep -Fq 'ignoring invalid font personalization value' \
	"$work/personalization-reserved-name.err"
reset_fixture

printf 'personalization-protocol\t1\t0\nfont\tBad"Font\nicon\tBad=Icons\n' \
	>"$config_home/dwm-titus/personalization.conf"
printf 'gtk-font-name="Baseline Font 11"\ngtk-icon-theme-name="Baseline Icons"\n' \
	>"$home_dir/.gtkrc-2.0"
run_theme_real_apply apply dracula >/dev/null 2>"$work/personalization-unsafe-name.err"
grep -Fq 'ignoring invalid font personalization value' \
	"$work/personalization-unsafe-name.err"
grep -Fq 'ignoring invalid icon personalization value' \
	"$work/personalization-unsafe-name.err"
grep -Fqx 'gtk-font-name="Baseline Font 11"' "$home_dir/.gtkrc-2.0"
grep -Fqx 'gtk-icon-theme-name="Baseline Icons"' "$home_dir/.gtkrc-2.0"
reset_fixture

mkdir -p "$config_home/gtk-3.0" "$config_home/gtk-4.0"
printf 'personalization-protocol\t1\t0\nfont\tfollow-system\ntext-size\tfollow-system\nicon\tfollow-system\n' \
	>"$config_home/dwm-titus/personalization.conf"
printf '[Settings]\ngtk-font-name=External Font 12\ngtk-icon-theme-name=External Icons\n' \
	>"$config_home/gtk-3.0/settings.ini"
cp "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"
printf 'gtk-font-name="External Font 12"\ngtk-icon-theme-name="External Icons"\n' \
	>"$home_dir/.gtkrc-2.0"
printf "'External Font 12'\n" >"$work/dconf/font-name"
printf '1.25\n' >"$work/dconf/text-scaling-factor"
printf "'External Icons'\n" >"$work/dconf/icon-theme"
run_theme_real_apply apply dracula >/dev/null 2>"$work/follow-system-base.err"
for settings_file in "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"; do
	grep -Fqx 'gtk-font-name=External Font 12' "$settings_file"
	grep -Fqx 'gtk-icon-theme-name=External Icons' "$settings_file"
done
grep -Fqx 'gtk-font-name="External Font 12"' "$home_dir/.gtkrc-2.0"
grep -Fqx 'gtk-icon-theme-name="External Icons"' "$home_dir/.gtkrc-2.0"
grep -Fqx "'External Font 12'" "$work/dconf/font-name"
grep -Fqx '1.25' "$work/dconf/text-scaling-factor"
grep -Fqx "'External Icons'" "$work/dconf/icon-theme"
reset_fixture
no_atomic_bin=$work/no-atomic-bin
real_mv=$(command -v mv)
mkdir -p "$no_atomic_bin"
cat >"$no_atomic_bin/mv" <<SH
#!/bin/sh
if [ "\${1:-}" = --help ]; then
	printf 'Usage: mv SOURCE DEST\n'
	exit 0
fi
exec "$real_mv" "\$@"
SH
chmod +x "$no_atomic_bin/mv"
if PATH="$no_atomic_bin:$PATH" run_theme mutation-ready; then
	printf 'missing atomic exchange support was reported mutation-ready\n' >&2
	exit 1
fi

foreign_parent=$work/foreign-theme-parent
foreign_theme=$foreign_parent/themes.toml
mkdir "$foreign_parent"
if ((UID == 0)); then
	chown 1 "$foreign_parent"
else
	foreign_parent=/tmp
	foreign_theme=$foreign_parent/.dwm-settings-theme-foreign-$UID-$$.toml
fi
if HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$foreign_theme \
	DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_APPEARANCE_APPLY_HELPER=$apply_stub DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
	DWM_TEST_APPLY_LOG=$work/apply.log DWM_TEST_RELOAD_LOG=$work/reload.log \
	"$helper" mutation-ready; then
	printf 'foreign-owned theme directory was reported mutation-ready\n' >&2
	exit 1
fi

mkdir -p "$work/unsafe-integration-target"
ln -s "$work/unsafe-integration-target" "$config_home/alacritty"
if run_theme mutation-ready; then
	printf 'symlinked integration directory was reported mutation-ready\n' >&2
	exit 1
fi
rm "$config_home/alacritty"
if HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_APPLY_HELPER=$work/missing-theme-apply \
	"$helper" mutation-ready; then
	printf 'missing apply helper was reported mutation-ready\n' >&2
	exit 1
fi
printf '\n[theme.invalid\n' >>"$themes_file"
if run_theme mutation-ready; then
	printf 'parser-invalid theme source was reported mutable\n' >&2
	exit 1
fi
reset_fixture
printf '\n[active]\ntheme = "dracula"\n' >>"$themes_file"
if run_theme mutation-ready; then
	printf 'duplicate active sections were reported mutable\n' >&2
	exit 1
fi
reset_fixture
sed -i '/^theme = "nord"/a theme = "dracula"' "$themes_file"
if run_theme mutation-ready; then
	printf 'duplicate active theme keys were reported mutable\n' >&2
	exit 1
fi
reset_fixture
sed -i '0,/theme = "nord"/s//theme = "dracula"/' "$themes_file"
sed -i '/^\[theme.nord\]$/,/^\[theme\./ { /^[[:space:]]*term_color15[[:space:]]*=/d; }' \
	"$themes_file"
if run_theme mutation-ready; then
	printf 'invalid managed-default collision was reported mutation-ready\n' >&2
	exit 1
fi
reset_fixture
chmod 500 "$config_home/dwm-titus"
if run_theme mutation-ready; then
	printf 'non-writable theme directory was reported mutable\n' >&2
	exit 1
fi
chmod 700 "$config_home/dwm-titus"
rm "$themes_file"
ln -s "$work/outside-themes.toml" "$themes_file"
cp "$repo/config/themes.toml" "$work/outside-themes.toml"
outside_hash=$(sha256sum "$work/outside-themes.toml")
symlink_apply_output=$(HOME=$home_dir XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_STATE_HOME=$state_home XDG_RUNTIME_DIR=$runtime_dir \
	DWM_APPEARANCE_THEMES_FILE=$themes_file DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	DWM_TEST_LIVE_LOG=$work/live.log PATH=$work/integration-bin:$PATH \
	"$repo/scripts/theme-apply.sh" 2>"$work/symlink-apply.err")
grep -Fqx "theme-apply: applied theme 'nord'" <<<"$symlink_apply_output"
[[ $(sha256sum "$work/outside-themes.toml") == "$outside_hash" ]]
if run_theme mutation-ready; then
	printf 'symlinked theme file was reported mutable\n' >&2
	exit 1
fi
if run_theme apply dracula 2>"$work/symlink.err"; then
	printf 'symlinked theme file was mutated\n' >&2
	exit 1
fi
grep -Fq 'theme file is not a regular file' "$work/symlink.err"
[[ $(sha256sum "$work/outside-themes.toml") == "$outside_hash" ]]

reset_fixture
ln "$themes_file" "$work/hardlink-themes.toml"
if run_theme mutation-ready; then
	printf 'hard-linked theme file was reported mutable\n' >&2
	exit 1
fi
if run_theme apply dracula 2>"$work/hardlink.err"; then
	printf 'hard-linked theme file was mutated\n' >&2
	exit 1
fi
grep -Fq 'theme file has multiple hard links' "$work/hardlink.err"

fallback_config=$work/fallback-config
fallback_home=$work/fallback-home
mkdir -p "$fallback_config" "$fallback_home"
if HOME=$fallback_home XDG_CONFIG_HOME=$fallback_config XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime_dir DWM_APPEARANCE_INTEGRATION_LOCK_HELD=1 \
	"$repo/scripts/theme-apply.sh" 8>&- >"$work/invalid-inherited-lock.out" \
	2>"$work/invalid-inherited-lock.err"; then
	printf 'theme apply accepted a missing caller-reported integration lock\n' >&2
	exit 1
fi
grep -Fqx 'theme-apply: caller-reported integration lock does not match descriptor 8' \
	"$work/invalid-inherited-lock.err"
fallback_output=$(HOME=$fallback_home XDG_CONFIG_HOME=$fallback_config XDG_DATA_HOME=$data_home \
	DISPLAY='' DBUS_SESSION_BUS_ADDRESS='' XDG_RUNTIME_DIR=$runtime_dir \
	DWM_TEST_LIVE_LOG=$work/live.log PATH=$work/integration-bin:$PATH \
	DWM_APPEARANCE_THEMES_FILE=$fallback_config/dwm-titus/themes.toml \
	DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	"$repo/scripts/theme-apply.sh" 2>"$work/fallback.err")
grep -Fqx "theme-apply: applied theme 'nord'" <<<"$fallback_output"
grep -Eq '^gtk-theme-name="(Nordic|Adwaita-dark)"$' "$fallback_home/.gtkrc-2.0"

if (cd "$work" && HOME=$fallback_home XDG_CONFIG_HOME=$fallback_config XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=. DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	"$repo/scripts/theme-apply.sh" >"$work/apply-relative.out" 2>"$work/apply-relative.err"); then
	printf 'theme apply accepted a relative runtime directory\n' >&2
	exit 1
fi
grep -Fqx 'theme-apply: XDG_RUNTIME_DIR must be an absolute path' "$work/apply-relative.err"

invalid_source=$work/invalid-theme-source
mkdir "$invalid_source"
if HOME=$fallback_home XDG_CONFIG_HOME=$fallback_config XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime_dir DWM_APPEARANCE_THEMES_FILE=$invalid_source \
	DWM_APPEARANCE_MANAGED_THEMES_FILE=$managed_file \
	"$repo/scripts/theme-apply.sh" >"$work/apply-invalid.out" 2>"$work/apply-invalid.err"; then
	printf 'theme apply accepted a nonregular user source\n' >&2
	exit 1
fi
grep -Fqx "theme-apply: user theme source is not a regular file: $invalid_source" \
	"$work/apply-invalid.err"

concurrent_config=$work/concurrent-config
concurrent_home=$work/concurrent-home
concurrent_runtime=$work/concurrent-runtime
theme_path=$work/theme-path
mkdir -p "$concurrent_config/alacritty" "$concurrent_config/kitty" "$concurrent_home" \
	"$concurrent_runtime" "$theme_path"
for command_name in awk cat chmod dirname flock grep mkdir mktemp mv sed sha256sum stat; do
	ln -s "$(command -v "$command_name")" "$theme_path/$command_name"
done
printf '%s\n' 'import = [' '  "~/.config/alacritty/keybindings.toml",' ']' \
	>"$concurrent_config/alacritty/alacritty.toml"
printf '# kitty\n' >"$concurrent_config/kitty/kitty.conf"
PATH=$theme_path HOME=$concurrent_home XDG_CONFIG_HOME=$concurrent_config \
	XDG_RUNTIME_DIR=$concurrent_runtime DWM_APPEARANCE_THEMES_FILE=$managed_file \
	"$repo/scripts/theme-apply.sh" >"$work/concurrent-a.out" 2>"$work/concurrent-a.err" &
concurrent_a=$!
PATH=$theme_path HOME=$concurrent_home XDG_CONFIG_HOME=$concurrent_config \
	XDG_RUNTIME_DIR=$concurrent_runtime DWM_APPEARANCE_THEMES_FILE=$managed_file \
	"$repo/scripts/theme-apply.sh" >"$work/concurrent-b.out" 2>"$work/concurrent-b.err" &
concurrent_b=$!
wait "$concurrent_a"
wait "$concurrent_b"
[[ $(grep -Fc 'active-theme.toml' "$concurrent_config/alacritty/alacritty.toml") == 1 ]]
[[ $(grep -Fxc 'include active-theme.conf' "$concurrent_config/kitty/kitty.conf") == 1 ]]

reset_fixture
mkdir -p "$config_home/gtk-3.0"
printf 'External XFCE GTK\n' >"$work/xfconf/theme-name"
printf 'External XFCE Cursor\n' >"$work/xfconf/cursor-theme"
printf '[Settings]\nunchanged=yes\ngtk-font-name = Keep Font 13\n' \
	>"$config_home/gtk-3.0/settings.ini"
printf 'gtk-key-theme-name="Keep"\n' >"$home_dir/.gtkrc-2.0"
printf 'personalization-protocol\t1\t0\nfont\tKeep Font\n' \
	>"$config_home/dwm-titus/personalization.conf"
if run_theme personalize cursor follow-system >"$work/personalize-invalid-cursor.out" \
	2>"$work/personalize-invalid-cursor.err"; then
	printf 'cursor accepted the font-only follow-system sentinel\n' >&2
	exit 1
fi
grep -Fq 'invalid personalization value for cursor' "$work/personalize-invalid-cursor.err"
if run_theme personalize font follow-theme >"$work/personalize-invalid-font.out" \
	2>"$work/personalize-invalid-font.err"; then
	printf 'font accepted the cursor-only follow-theme sentinel\n' >&2
	exit 1
fi
grep -Fq 'invalid personalization value for font' "$work/personalize-invalid-font.err"
if run_theme personalize font 'Bad"Font' >"$work/personalize-quoted-font.out" \
	2>"$work/personalize-quoted-font.err"; then
	printf 'font accepted a GTK2-unsafe quote delimiter\n' >&2
	exit 1
fi
grep -Fq 'invalid personalization value for font' "$work/personalize-quoted-font.err"
if run_theme personalize font unknown >"$work/personalize-unknown-font.out" \
	2>"$work/personalize-unknown-font.err"; then
	printf 'font accepted the reserved unknown sentinel\n' >&2
	exit 1
fi
grep -Fq 'invalid personalization value for font' \
	"$work/personalize-unknown-font.err"
printf 'Keep/Setting "yes"\n' >"$config_home/dwm-titus/xsettingsd.conf"
text_scale_output=$(run_theme_real_apply personalize text-size 1.25 \
	2>"$work/personalize-text-size.err")
grep -Fqx $'result\tapply\ttext-size\t1.25' <<<"$text_scale_output"
grep -Fqx '1.25' "$work/dconf/text-scaling-factor"
grep -Fqx '# Auto-generated by theme-apply.sh - do not edit manually.' \
	"$config_home/dwm-titus/xsettingsd.conf"
grep -Fqx 'Keep/Setting "yes"' "$config_home/dwm-titus/xsettingsd.conf"
grep -Fqx 'Xft/DPI 122880' "$config_home/dwm-titus/xsettingsd.conf"
grep -Fqx reload "$work/xsettings.log"
run_theme_real_apply personalize-reset text-size >/dev/null \
	2>"$work/personalize-reset-text-size.err"
grep -Fqx $'text-size\tfollow-system' "$config_home/dwm-titus/personalization.conf"
grep -Fqx 'Keep/Setting "yes"' "$config_home/dwm-titus/xsettingsd.conf"
if grep -Eq '^Xft/DPI[[:space:]]' "$config_home/dwm-titus/xsettingsd.conf"; then
	printf 'system-follow reset retained managed Xft/DPI\n' >&2
	exit 1
fi
personalize_output=$(DWM_TEST_GSETTINGS_FAIL_ALL=1 run_theme_real_apply personalize qt gtk3 \
	2>"$work/personalize-qt.err")
grep -Fqx $'personalization-action-protocol\t1\t0' <<<"$personalize_output"
grep -Fqx $'result\tapply\tqt\tgtk3' <<<"$personalize_output"
grep -Fqx $'personalization-protocol\t1\t0' \
	"$config_home/dwm-titus/personalization.conf"
grep -Fqx $'font\tKeep Font' "$config_home/dwm-titus/personalization.conf"
grep -Fqx $'qt\tgtk3' "$config_home/dwm-titus/personalization.conf"
grep -Fqx 'export QT_QPA_PLATFORMTHEME=gtk3' "$config_home/dwm-titus/theme-env.sh"
grep -Fqx 'gtk-font-name=Keep Font 11' "$config_home/gtk-3.0/settings.ini"
[[ $(grep -Fxc 'gtk-font-name=Keep Font 11' "$config_home/gtk-3.0/settings.ini") == 1 ]]
grep -Fqx 'External XFCE GTK' "$work/xfconf/theme-name"
grep -Fqx 'External XFCE Cursor' "$work/xfconf/cursor-theme"

run_theme_real_apply apply dracula >/dev/null 2>"$work/personalize-theme-change.err"
grep -Fqx $'qt\tgtk3' "$config_home/dwm-titus/personalization.conf"
grep -Fqx 'export QT_QPA_PLATFORMTHEME=gtk3' "$config_home/dwm-titus/theme-env.sh"

printf 'External XFCE GTK\n' >"$work/xfconf/theme-name"
printf 'External XFCE Cursor\n' >"$work/xfconf/cursor-theme"
run_theme_real_apply personalize gtk Adwaita >/dev/null 2>"$work/personalize-gtk.err"
grep -Fqx Adwaita "$work/xfconf/theme-name"
grep -Fqx 'External XFCE Cursor' "$work/xfconf/cursor-theme"
grep -Fqx 'unchanged=yes' "$config_home/gtk-3.0/settings.ini"
grep -Fqx 'gtk-key-theme-name="Keep"' "$home_dir/.gtkrc-2.0"
grep -Fqx 'gtk-cursor-theme-size=32' "$home_dir/.gtkrc-2.0"
if ! grep -Fqx 'gtk-theme-name="Adwaita"' "$home_dir/.gtkrc-2.0"; then
	printf 'personalized GTK2 output did not retain the selected theme:\n' >&2
	sed -n '1,20p' "$home_dir/.gtkrc-2.0" >&2
	exit 1
fi

custom_gtk_root=$work/custom-gtk-root
mkdir -p "$custom_gtk_root/themes/CustomXdg/gtk-3.0"
XDG_DATA_DIRS=$custom_gtk_root \
	run_theme_real_apply personalize gtk CustomXdg >/dev/null \
	2>"$work/personalize-custom-gtk.err"
grep -Fqx $'gtk\tCustomXdg' "$config_home/dwm-titus/personalization.conf"
grep -Fqx 'gtk-theme-name=CustomXdg' "$config_home/gtk-3.0/settings.ini"
grep -Fqx 'gtk-theme-name="CustomXdg"' "$home_dir/.gtkrc-2.0"

reset_personalize_output=$(run_theme_real_apply personalize-reset qt \
	2>"$work/personalize-reset.err")
grep -Fqx $'result\treset\tqt\tfollow-theme' <<<"$reset_personalize_output"
grep -Fqx $'qt\tfollow-theme' "$config_home/dwm-titus/personalization.conf"
grep -Eq '^export QT_QPA_PLATFORMTHEME=(qt6ct|qt5ct|gtk3)$' \
	"$config_home/dwm-titus/theme-env.sh"

reset_fixture
mkdir -p "$config_home/gtk-3.0" "$config_home/gtk-4.0"
for settings_file in "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"; do
	printf '  [Settings]  \nkeep=yes\ngtk-font-name=Managed Font 12\ngtk-icon-theme-name=Managed Icons\n' \
		>"$settings_file"
done
printf '  gtk-font-name = "Managed Font 12"\n gtk-icon-theme-name = "Managed Icons"\nkeep-gtk2="yes"\n' \
	>"$home_dir/.gtkrc-2.0"
printf "'Managed Font 10'\n" >"$work/dconf/font-name"
DWM_TEST_GSETTINGS_STAGE_DEFAULT=1 run_theme_real_apply personalize font 'Font One' >/dev/null \
	2>"$work/personalize-padded-header.err"
for settings_file in "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"; do
	grep -Fqx '  [Settings]  ' "$settings_file"
	grep -Fqx 'gtk-font-name=Font One 10' "$settings_file"
done
grep -Fqx 'gtk-font-name="Font One 10"' "$home_dir/.gtkrc-2.0"
[[ $(grep -Ec '^[[:space:]]*gtk-font-name[[:space:]]*=' "$home_dir/.gtkrc-2.0") == 1 ]]
LC_ALL=C.UTF-8 run_theme_real_apply personalize cursor 'Cursör' >/dev/null \
	2>"$work/personalize-unicode-cursor.err"
grep -Fqx $'export XCURSOR_THEME=Curs\\\303\\\266r' \
	"$config_home/dwm-titus/theme-env.sh"
printf 'personalization-protocol\t1\t0\nfont\tManaged Font\nicon\tManaged Icons\n' \
	>"$config_home/dwm-titus/personalization.conf"
run_theme_real_apply personalize-reset font >/dev/null 2>"$work/personalize-reset-font.err"
run_theme_real_apply personalize-reset icon >/dev/null 2>"$work/personalize-reset-icon.err"
for settings_file in "$config_home/gtk-3.0/settings.ini" "$config_home/gtk-4.0/settings.ini"; do
	grep -Fqx '  [Settings]  ' "$settings_file"
	grep -Fqx 'keep=yes' "$settings_file"
	if grep -Eq '^[[:space:]]*gtk-(font-name|icon-theme-name)[[:space:]]*=' "$settings_file"; then
		printf 'system-follow reset retained a managed GTK key in %s\n' "$settings_file" >&2
		exit 1
	fi
done
grep -Fqx 'keep-gtk2="yes"' "$home_dir/.gtkrc-2.0"
if grep -Eq '^[[:space:]]*gtk-(font-name|icon-theme-name)[[:space:]]*=' \
	"$home_dir/.gtkrc-2.0"; then
	printf 'system-follow reset retained a managed GTK2 key\n' >&2
	exit 1
fi

reset_fixture
gtk2_target_dir=$work/gtk2-target
gtk2_target=$gtk2_target_dir/gtkrc
gtk3_target=$gtk2_target_dir/settings.ini
mkdir -p "$gtk2_target_dir" "$config_home/gtk-3.0" "$config_home/gtk-4.0"
printf 'keep-symlink-target="yes"\ngtk-font-name="Managed Font 12"\n' >"$gtk2_target"
printf '[Settings]\nkeep-symlink-target=yes\ngtk-font-name=Managed Font 12\n' >"$gtk3_target"
rm -f "$home_dir/.gtkrc-2.0"
ln -s "$gtk2_target" "$home_dir/.gtkrc-2.0"
rm -f "$config_home/gtk-3.0/settings.ini"
ln -s "$gtk3_target" "$config_home/gtk-3.0/settings.ini"
rm -f "$config_home/gtk-4.0/settings.ini"
ln -s "$gtk3_target" "$config_home/gtk-4.0/settings.ini"
printf 'personalization-protocol\t1\t0\nfont\tFont One\n' \
	>"$config_home/dwm-titus/personalization.conf"
run_theme_apply_direct >"$work/theme-apply-symlink-font.out" \
	2>"$work/theme-apply-symlink-font.err"
[[ -L $home_dir/.gtkrc-2.0 ]]
[[ $(readlink -f -- "$home_dir/.gtkrc-2.0") == "$gtk2_target" ]]
[[ -L $config_home/gtk-3.0/settings.ini ]]
[[ $(readlink -f -- "$config_home/gtk-3.0/settings.ini") == "$gtk3_target" ]]
[[ -L $config_home/gtk-4.0/settings.ini ]]
[[ $(readlink -f -- "$config_home/gtk-4.0/settings.ini") == "$gtk3_target" ]]
grep -Fqx 'keep-symlink-target="yes"' "$gtk2_target"
grep -Fqx 'gtk-font-name="Font One 11"' "$gtk2_target"
grep -Fqx 'keep-symlink-target=yes' "$gtk3_target"
grep -Fqx 'gtk-font-name=Font One 11' "$gtk3_target"
printf 'personalization-protocol\t1\t0\nfont\tfollow-system\n' \
	>"$config_home/dwm-titus/personalization.conf"
DWM_APPEARANCE_PERSONALIZATION_CAPABILITY=font \
	run_theme_apply_direct >"$work/theme-apply-reset-symlink-font.out" \
	2>"$work/theme-apply-reset-symlink-font.err"
[[ -L $home_dir/.gtkrc-2.0 ]]
[[ -L $config_home/gtk-3.0/settings.ini ]]
[[ -L $config_home/gtk-4.0/settings.ini ]]
grep -Fqx 'keep-symlink-target="yes"' "$gtk2_target"
grep -Fqx 'keep-symlink-target=yes' "$gtk3_target"
if grep -Eq '^[[:space:]]*gtk-font-name[[:space:]]*=' "$gtk2_target"; then
	printf 'system-follow reset retained a managed GTK2 key through a symlink\n' >&2
	exit 1
fi
if grep -Eq '^[[:space:]]*gtk-font-name[[:space:]]*=' "$gtk3_target"; then
	printf 'system-follow reset retained a managed GTK3 key through a symlink\n' >&2
	exit 1
fi
if ! run_theme_real_apply personalize font 'Font One' >/dev/null \
	2>"$work/personalize-symlink-font.err"; then
	cat "$work/personalize-symlink-font.err" >&2
	exit 1
fi
[[ -L $home_dir/.gtkrc-2.0 ]]
[[ $(readlink -f -- "$home_dir/.gtkrc-2.0") == "$gtk2_target" ]]
[[ -L $config_home/gtk-3.0/settings.ini ]]
[[ $(readlink -f -- "$config_home/gtk-3.0/settings.ini") == "$gtk3_target" ]]
[[ -L $config_home/gtk-4.0/settings.ini ]]
[[ $(readlink -f -- "$config_home/gtk-4.0/settings.ini") == "$gtk3_target" ]]
grep -Fqx 'keep-symlink-target="yes"' "$gtk2_target"
grep -Fqx 'gtk-font-name="Font One 11"' "$gtk2_target"
grep -Fqx 'keep-symlink-target=yes' "$gtk3_target"
grep -Fqx 'gtk-font-name=Font One 11' "$gtk3_target"
run_theme_real_apply personalize-reset font >/dev/null \
	2>"$work/personalize-reset-symlink-font.err"
[[ -L $home_dir/.gtkrc-2.0 ]]
[[ -L $config_home/gtk-3.0/settings.ini ]]
[[ -L $config_home/gtk-4.0/settings.ini ]]
grep -Fqx 'keep-symlink-target="yes"' "$gtk2_target"
grep -Fqx 'keep-symlink-target=yes' "$gtk3_target"
if grep -Eq '^[[:space:]]*gtk-font-name[[:space:]]*=' "$gtk2_target"; then
	printf 'transactional reset retained a managed GTK2 key through a symlink\n' >&2
	exit 1
fi
if grep -Eq '^[[:space:]]*gtk-font-name[[:space:]]*=' "$gtk3_target"; then
	printf 'transactional reset retained a managed GTK3 key through a symlink\n' >&2
	exit 1
fi
rm -f "$home_dir/.gtkrc-2.0"

reset_fixture
rm "$themes_file"
managed_before=$(sha256sum "$managed_file")
run_theme_real_apply personalize qt gtk3 >/dev/null 2>"$work/personalize-managed.err"
[[ ! -e $themes_file ]]
[[ $(sha256sum "$managed_file") == "$managed_before" ]]
grep -Fqx $'qt\tgtk3' "$config_home/dwm-titus/personalization.conf"

reset_fixture
rm "$themes_file"
managed_finish_ready=$work/managed-finish.ready
managed_finish_release=$work/managed-finish.release
managed_finish_pid_file=$work/managed-finish.pid
DWM_TEST_FINISH_READY=$managed_finish_ready \
	DWM_TEST_FINISH_RELEASE=$managed_finish_release \
	DWM_TEST_PROCESS_PID=$managed_finish_pid_file \
	run_theme_real_apply personalize qt gtk3 \
	>"$work/managed-finish.out" 2>"$work/managed-finish.err" &
managed_finish_job=$!
for _ in {1..200}; do
	[[ -e $managed_finish_ready && -s $managed_finish_pid_file ]] && break
	sleep 0.02
done
[[ -e $managed_finish_ready && -s $managed_finish_pid_file ]]
IFS= read -r managed_finish_pid <"$managed_finish_pid_file"
kill -KILL "$managed_finish_pid"
wait "$managed_finish_job" 2>/dev/null || true
printf '\n# package update during interrupted personalization\n' >>"$managed_file"
if run_theme_real_apply recover >"$work/managed-source-recover.out" \
	2>"$work/managed-source-recover.err"; then
	printf 'recovery accepted a changed managed theme source\n' >&2
	exit 1
fi
grep -Fq 'changed after the interrupted transaction' "$work/managed-source-recover.err"
grep -Fqx $'recovery\tavailable\tpersonalize-qt\tnord' \
	< <(run_theme recovery-status)
cp "$repo/config/themes.toml" "$managed_file"
reset_fixture

printf 'personalization-protocol\t1\t0\nfont\tFont One\n' \
	>"$config_home/dwm-titus/personalization.conf"
printf '%s\n' "\"Bob's Font 13\"" >"$work/dconf/font-name"
run_theme_apply_direct >/dev/null 2>"$work/theme-apply-double-quoted-font.err"
grep -Fqx 'gtk-font-name=Font One 13' "$config_home/gtk-3.0/settings.ini"
grep -Fqx 'gtk-font-name="Font One 13"' "$home_dir/.gtkrc-2.0"

printf '%s\n' "'Large Font 100'" >"$work/dconf/font-name"
run_theme_apply_direct >/dev/null 2>"$work/theme-apply-large-font.err"
grep -Fqx 'gtk-font-name=Font One 100' "$config_home/gtk-3.0/settings.ini"
grep -Fqx 'gtk-font-name="Font One 100"' "$home_dir/.gtkrc-2.0"

reset_fixture

gsettings_calls=$work/personalization-gsettings.calls
: >"$gsettings_calls"
DWM_TEST_GSETTINGS_CALLS=$gsettings_calls \
	run_theme_real_apply personalize font 'Font One' >/dev/null \
	2>"$work/personalize-font-selected-only.err"
grep -Fqx $'set\tfont-name' "$gsettings_calls"
[[ $(wc -l <"$gsettings_calls") == 1 ]]

run_theme_real_apply personalize icon "Bob's Icons" >/dev/null \
	2>"$work/personalize-icon-apostrophe.err"
grep -Fqx "\"Bob's Icons\"" "$work/dconf/icon-theme"
grep -Fqx "$(printf 'icon\t%s' "Bob's Icons")" \
	"$config_home/dwm-titus/personalization.conf"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
personalization_baseline_ready=$work/personalization-baseline.ready
personalization_baseline_release=$work/personalization-baseline.release
DWM_TEST_BEFORE_INTEGRATION_PUBLISH=$personalization_baseline_ready \
	DWM_TEST_INTEGRATION_PUBLISH_RELEASE=$personalization_baseline_release \
	run_theme_real_apply personalize font 'Font One' \
	>"$work/personalization-baseline.out" 2>"$work/personalization-baseline.err" &
personalization_baseline_job=$!
for _ in {1..200}; do
	[[ -e $personalization_baseline_ready ]] && break
	sleep 0.02
done
[[ -e $personalization_baseline_ready ]]
printf "'External Font 12'\n" >"$work/dconf/font-name"
: >"$personalization_baseline_release"
if wait "$personalization_baseline_job"; then
	printf 'personalization overwrote a GSettings edit made during preparation\n' >&2
	exit 1
fi
grep -Fq 'font GSettings changed during transaction preparation' \
	"$work/personalization-baseline.err"
grep -Fqx "'External Font 12'" "$work/dconf/font-name"
[[ ! -e $config_home/dwm-titus/personalization.conf ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
personalization_live_ready=$work/personalization-live.ready
personalization_live_release=$work/personalization-live.release
DWM_TEST_BEFORE_PERSONALIZATION_LIVE_WRITE=$personalization_live_ready \
	DWM_TEST_PERSONALIZATION_LIVE_WRITE_RELEASE=$personalization_live_release \
	run_theme_real_apply personalize font 'Font One' \
	>"$work/personalization-live.out" 2>"$work/personalization-live.err" &
personalization_live_job=$!
for _ in {1..200}; do
	[[ -e $personalization_live_ready ]] && break
	sleep 0.02
done
[[ -e $personalization_live_ready ]]
printf "'Late External Font 12'\n" >"$work/dconf/font-name"
: >"$personalization_live_release"
if wait "$personalization_live_job"; then
	printf 'personalization overwrote a GSettings edit made at the live-write boundary\n' >&2
	exit 1
fi
grep -Fq 'personalization GSettings changed before the live write' \
	"$work/personalization-live.err"
grep -Fqx "'Late External Font 12'" "$work/dconf/font-name"
grep -Fqx $'recovery\tavailable\tpersonalize-font\tnord' \
	< <(run_theme recovery-status)

reset_fixture
personalization_xfconf_live_ready=$work/personalization-xfconf-live.ready
personalization_xfconf_live_release=$work/personalization-xfconf-live.release
DWM_TEST_BEFORE_PERSONALIZATION_LIVE_WRITE=$personalization_xfconf_live_ready \
	DWM_TEST_PERSONALIZATION_LIVE_WRITE_RELEASE=$personalization_xfconf_live_release \
	run_theme_real_apply personalize cursor Capitaine-Cursors \
	>"$work/personalization-xfconf-live.out" \
	2>"$work/personalization-xfconf-live.err" &
personalization_xfconf_live_job=$!
for _ in {1..200}; do
	[[ -e $personalization_xfconf_live_ready ]] && break
	sleep 0.02
done
[[ -e $personalization_xfconf_live_ready ]]
printf 'Late External Cursor\n' >"$work/xfconf/cursor-theme"
: >"$personalization_xfconf_live_release"
if wait "$personalization_xfconf_live_job"; then
	printf 'personalization overwrote an xfconf edit made at the live-write boundary\n' >&2
	exit 1
fi
grep -Fq 'personalization xfconf changed before the live write' \
	"$work/personalization-xfconf-live.err"
grep -Fqx 'Late External Cursor' "$work/xfconf/cursor-theme"
grep -Fqx $'recovery\tavailable\tpersonalize-cursor\tnord' \
	< <(run_theme recovery-status)

reset_fixture
if DWM_TEST_GSETTINGS_MISMATCH_KEY=font-name \
	run_theme_real_apply personalize font 'Font One' \
	>"$work/personalization-mismatch.out" 2>"$work/personalization-mismatch.err"; then
	printf 'personalization accepted a nonconverged GSettings value\n' >&2
	exit 1
fi
grep -Fq 'font GSettings did not converge to the journaled state' \
	"$work/personalization-mismatch.err"
grep -Fqx "'Unexpected external value'" "$work/dconf/font-name"
grep -Fqx $'recovery\tavailable\tpersonalize-font\tnord' \
	< <(run_theme recovery-status)

reset_fixture
if DWM_TEST_GSETTINGS_FAIL_KEY=font-name run_theme_real_apply personalize font 'Font One' \
	>"$work/personalize-font-failure.out" 2>"$work/personalize-font-failure.err"; then
	printf 'personalization accepted a failed selected GSettings key\n' >&2
	exit 1
fi
grep -Fq 'personalization font was committed but live convergence failed' \
	"$work/personalize-font-failure.err"
[[ ! -e $config_home/dwm-titus/personalization.conf ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
personalization_finish_ready=$work/personalization-finish.ready
personalization_finish_release=$work/personalization-finish.release
personalization_finish_pid_file=$work/personalization-finish.pid
DWM_TEST_FINISH_READY=$personalization_finish_ready \
	DWM_TEST_FINISH_RELEASE=$personalization_finish_release \
	DWM_TEST_PROCESS_PID=$personalization_finish_pid_file \
	run_theme_real_apply personalize font 'Font One' \
	>"$work/personalization-finish.out" 2>"$work/personalization-finish.err" &
personalization_finish_job=$!
for _ in {1..200}; do
	[[ -e $personalization_finish_ready && -s $personalization_finish_pid_file ]] && break
	sleep 0.02
done
[[ -e $personalization_finish_ready && -s $personalization_finish_pid_file ]]
[[ -s $work/dconf/font-name ]]
cmp -s "$work/dconf/font-name" \
	"$state_home/dwm-titus/appearance/transaction.gsettings.after"
IFS= read -r personalization_finish_pid <"$personalization_finish_pid_file"
kill -KILL "$personalization_finish_pid"
wait "$personalization_finish_job" 2>/dev/null || true
grep -Fqx $'recovery\tavailable\tpersonalize-font\tnord' \
	< <(run_theme recovery-status)
run_theme_real_apply recover >/dev/null 2>"$work/personalization-finish-recover.err"
[[ ! -e $work/dconf/font-name ]]
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
text_finish_ready=$work/text-finish.ready
text_finish_release=$work/text-finish.release
text_finish_pid_file=$work/text-finish.pid
DWM_TEST_FINISH_READY=$text_finish_ready \
	DWM_TEST_FINISH_RELEASE=$text_finish_release \
	DWM_TEST_PROCESS_PID=$text_finish_pid_file \
	run_theme_real_apply personalize text-size 1.25 \
	>"$work/text-finish.out" 2>"$work/text-finish.err" &
text_finish_job=$!
for _ in {1..200}; do
	[[ -e $text_finish_ready && -s $text_finish_pid_file ]] && break
	sleep 0.02
done
[[ -e $text_finish_ready && -s $text_finish_pid_file ]]
[[ -f $config_home/dwm-titus/xsettingsd.conf ]]
IFS= read -r text_finish_pid <"$text_finish_pid_file"
kill -KILL "$text_finish_pid"
wait "$text_finish_job" 2>/dev/null || true
: >"$work/xsettings.log"
run_theme_real_apply recover >/dev/null 2>"$work/text-finish-recover.err"
[[ ! -e $config_home/dwm-titus/xsettingsd.conf ]]
grep -Fqx reload "$work/xsettings.log"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
printf "'External Baseline Cursor'\n" >"$work/dconf/cursor-theme"
printf 'External XFCE Cursor\n' >"$work/xfconf/cursor-theme"
cursor_finish_ready=$work/cursor-finish.ready
cursor_finish_release=$work/cursor-finish.release
cursor_finish_pid_file=$work/cursor-finish.pid
DWM_TEST_FINISH_READY=$cursor_finish_ready \
	DWM_TEST_FINISH_RELEASE=$cursor_finish_release \
	DWM_TEST_PROCESS_PID=$cursor_finish_pid_file \
	run_theme_real_apply personalize cursor Capitaine-Cursors \
	>"$work/cursor-finish.out" 2>"$work/cursor-finish.err" &
cursor_finish_job=$!
for _ in {1..200}; do
	[[ -e $cursor_finish_ready && -s $cursor_finish_pid_file ]] && break
	sleep 0.02
done
[[ -e $cursor_finish_ready && -s $cursor_finish_pid_file ]]
grep -Fqx Capitaine-Cursors "$work/xfconf/cursor-theme"
IFS= read -r cursor_finish_pid <"$cursor_finish_pid_file"
kill -KILL "$cursor_finish_pid"
wait "$cursor_finish_job" 2>/dev/null || true
run_theme_real_apply recover >/dev/null 2>"$work/cursor-finish-recover.err"
grep -Fqx "'External Baseline Cursor'" "$work/dconf/cursor-theme"
grep -Fqx 'External XFCE Cursor' "$work/xfconf/cursor-theme"
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
personalization_edit_ready=$work/personalization-edit.ready
personalization_edit_release=$work/personalization-edit.release
personalization_edit_pid_file=$work/personalization-edit.pid
DWM_TEST_FINISH_READY=$personalization_edit_ready \
	DWM_TEST_FINISH_RELEASE=$personalization_edit_release \
	DWM_TEST_PROCESS_PID=$personalization_edit_pid_file \
	run_theme_real_apply personalize cursor Capitaine-Cursors \
	>"$work/personalization-edit.out" 2>"$work/personalization-edit.err" &
personalization_edit_job=$!
for _ in {1..200}; do
	[[ -e $personalization_edit_ready && -s $personalization_edit_pid_file ]] && break
	sleep 0.02
done
[[ -e $personalization_edit_ready && -s $personalization_edit_pid_file ]]
IFS= read -r personalization_edit_pid <"$personalization_edit_pid_file"
kill -KILL "$personalization_edit_pid"
wait "$personalization_edit_job" 2>/dev/null || true
printf "'External Cursor'\n" >"$work/dconf/cursor-theme"
if run_theme_real_apply recover >"$work/personalization-edit-recover.out" \
	2>"$work/personalization-edit-recover.err"; then
	printf 'personalization recovery overwrote a later GSettings edit\n' >&2
	exit 1
fi
grep -Fq 'changed after the interrupted transaction' \
	"$work/personalization-edit-recover.err"
grep -Fqx "'External Cursor'" "$work/dconf/cursor-theme"
grep -Fqx $'recovery\tavailable\tpersonalize-cursor\tnord' \
	< <(run_theme recovery-status)

reset_fixture
personalization_marker=$work/personalization-publish-ready
personalization_release=$work/personalization-publish-release
personalization_pid_file=$work/personalization-helper.pid
DWM_TEST_BEFORE_INTEGRATION_PUBLISH=$personalization_marker \
	DWM_TEST_INTEGRATION_PUBLISH_RELEASE=$personalization_release \
	DWM_TEST_PROCESS_PID=$personalization_pid_file \
	run_theme personalize qt gtk3 >"$work/personalization-crash.out" \
	2>"$work/personalization-crash.err" &
personalization_job=$!
for _ in {1..200}; do
	[[ -e $personalization_marker && -s $personalization_pid_file ]] && break
	sleep 0.02
done
[[ -e $personalization_marker && -s $personalization_pid_file ]]
IFS= read -r personalization_pid <"$personalization_pid_file"
[[ $personalization_pid =~ ^[1-9][0-9]*$ ]]
kill -KILL "$personalization_pid"
wait "$personalization_job" 2>/dev/null || true
grep -Fqx $'recovery\tavailable\tpersonalize-qt\tnord' \
	< <(run_theme recovery-status)
[[ ! -e $config_home/dwm-titus/personalization.conf ]]
run_theme recover >/dev/null
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)
[[ ! -e $config_home/dwm-titus/personalization.conf ]]

printf 'dwm settings theme tests passed\n'
