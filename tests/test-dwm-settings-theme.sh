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

run_theme() {
	HOME=$home_dir \
		XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home \
		XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime_dir \
		DWM_APPEARANCE_APPLY_HELPER=$apply_stub \
		DWM_APPEARANCE_RELOAD_HELPER=$reload_stub \
		DWM_TEST_APPLY_LOG=$work/apply.log \
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
		PATH=$work/integration-bin:$PATH \
		"$helper" "$@"
}

integration_snapshot() {
	local path
	for path in \
		"$config_home/alacritty/active-theme.toml" \
		"$config_home/alacritty/alacritty.toml" \
		"$config_home/kitty/active-theme.conf" \
		"$config_home/kitty/kitty.conf" \
		"$config_home/gtk-3.0/settings.ini" \
		"$config_home/gtk-4.0/settings.ini" \
		"$home_dir/.gtkrc-2.0" \
		"$config_home/dwm-titus/cursor.Xresources" \
		"$config_home/dwm-titus/theme-env.sh" \
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
for side_effect_command in dbus-update-activation-environment gsettings kitty pgrep qt6ct systemctl xfconf-query xrdb; do
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
	rm -rf "$config_home" "$state_home" "$runtime_dir"
	mkdir -p "$config_home/dwm-titus" "$state_home" "$runtime_dir"
	cp "$repo/config/themes.toml" "$themes_file"
	chmod 640 "$themes_file"
	: >"$work/apply.log"
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
printf '%s\n' 'import = [' '  "~/.config/alacritty/custom-theme.toml",' ']' \
	>"$config_home/alacritty/alacritty.toml"
run_theme_real_apply preview integration-external 10 dracula >/dev/null 2>"$work/integration-external-preview.err"
printf '# external integration edit\n' >>"$config_home/alacritty/alacritty.toml"
integration_external_before=$(integration_snapshot)
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
grep -Fqx $'result\tabandon\tstale-keep\tdracula' "$work/stale-keep-abandon.out"
run_theme apply nord >/dev/null 2>"$work/apply-after-abandon.err"
[[ $(active_theme) == nord ]]

reset_fixture
if DWM_TEST_LIVE_ONLY_FAIL=1 run_theme apply dracula \
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
rm "$themes_file"
run_theme preview preview-absent 10 dracula >/dev/null 2>"$work/preview-absent.err"
[[ -f $themes_file && $(active_theme) == dracula ]]
run_theme revert preview-absent >/dev/null
[[ ! -e $themes_file ]]
suppression_hash=$(sha256sum "$managed_file" | awk '{print $1}')
cmp -s <(printf '%s\n' "$suppression_hash") \
	"$state_home/dwm-titus/appearance/integration-suppress"
grep -Fqx nord "$work/apply.log"
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
grep -Fqx $'recovery\tnone' < <(run_theme recovery-status)

reset_fixture
run_theme mutation-ready
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
for command_name in awk cat chmod dirname flock grep mkdir sed sha256sum stat; do
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

printf 'dwm settings theme tests passed\n'
