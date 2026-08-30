#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo/scripts/dwm-settings-wallpaper
tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
mkdir -p -- "$tmp_root"
work=$(mktemp -d "$tmp_root/dwm-wallpaper-test.XXXXXX")
trap 'rm -rf -- "$work"' EXIT

home=$work/home
config_home=$home/.config
state_home=$home/.local/state
runtime=$work/runtime
wallpaper_dir=$home/Pictures/backgrounds
bin_dir=$work/bin
log=$work/feh.log
mkdir -p "$config_home" "$state_home" "$runtime" "$wallpaper_dir" "$bin_dir"
chmod 700 "$runtime"
export DWM_TEST_WALLPAPER_SESSION_IDENTITY_PREFIX=wallpaper-test
printf 'first image\n' >"$wallpaper_dir/Nord One.png"
printf 'second image\n' >"$wallpaper_dir/forest.jpg"

cat >"$bin_dir/feh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
loadable_mode=false
for argument in "$@"; do
	[[ $argument != --loadable ]] || loadable_mode=true
done
if [[ $loadable_mode == true ]]; then
	if [[ -n ${DWM_TEST_FEH_LOADABLE_COUNT_FILE:-} ]]; then
		loadable_count=0
		[[ ! -s $DWM_TEST_FEH_LOADABLE_COUNT_FILE ]] ||
			IFS= read -r loadable_count <"$DWM_TEST_FEH_LOADABLE_COUNT_FILE"
		[[ $loadable_count =~ ^[0-9]+$ ]] || exit 2
		printf '%s\n' "$((loadable_count + 1))" >"$DWM_TEST_FEH_LOADABLE_COUNT_FILE"
	fi
	if [[ -n ${DWM_TEST_DEFAULT_SEQUENCE_FILE:-} && -s $DWM_TEST_DEFAULT_SEQUENCE_FILE ]]; then
		mapfile -t default_candidates <"$DWM_TEST_DEFAULT_SEQUENCE_FILE"
		printf '%s\n' "${default_candidates[0]}"
		: >"$DWM_TEST_DEFAULT_SEQUENCE_FILE"
		for ((index = 1; index < ${#default_candidates[@]}; index++)); do
			printf '%s\n' "${default_candidates[index]}" >>"$DWM_TEST_DEFAULT_SEQUENCE_FILE"
		done
		exit 0
	fi
	if [[ -n ${DWM_TEST_DEFAULT_CANDIDATE:-} ]]; then
		printf '%s\n' "$DWM_TEST_DEFAULT_CANDIDATE"
		exit 0
	fi
	if [[ -n ${DWM_TEST_INVALID_BASELINE:-} && -n ${DWM_TEST_VALID_BASELINE:-} ]]; then
		printf '%s\n%s\n' "$DWM_TEST_INVALID_BASELINE" "$DWM_TEST_VALID_BASELINE"
		exit 0
	fi
	[[ -z ${DWM_TEST_FEH_FAIL_ALL:-} ]] || exit 1
	for argument in "$@"; do
		[[ $argument != -* ]] || continue
		[[ ${DWM_TEST_FEH_FAIL_PATH:-} != "$argument" ]] || continue
		if [[ -f $argument ]]; then
			printf '%s\n' "$argument"
		elif [[ -d $argument ]]; then
			while IFS= read -r candidate; do
				[[ ${DWM_TEST_FEH_FAIL_PATH:-} != "$candidate" ]] || continue
				printf '%s\n' "$candidate"
			done < <(/usr/bin/find -L "$argument" -type f -print)
		fi
	done
	if [[ -n ${DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE:-} ]]; then
		printf '%s\n' "$$" >"$DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE"
		exec sleep 5
	fi
	exit 0
fi
printf 'call\n' >>"$DWM_TEST_FEH_LOG"
printf 'display=%s\n' "${DISPLAY:-}" >>"$DWM_TEST_FEH_LOG"
printf 'xauthority=%s\n' "${XAUTHORITY:-}" >>"$DWM_TEST_FEH_LOG"
for argument in "$@"; do
	printf 'arg=%s\n' "$argument" >>"$DWM_TEST_FEH_LOG"
done
if [[ -n ${DWM_TEST_FEH_FAIL_COUNT_FILE:-} && -f $DWM_TEST_FEH_FAIL_COUNT_FILE ]]; then
	IFS= read -r fail_count <"$DWM_TEST_FEH_FAIL_COUNT_FILE"
	[[ $fail_count =~ ^[0-9]+$ ]] || exit 2
	if ((fail_count > 0)); then
		printf '%s\n' "$((fail_count - 1))" >"$DWM_TEST_FEH_FAIL_COUNT_FILE"
		exit 1
	fi
fi
[[ -z ${DWM_TEST_FEH_FAIL_ALL:-} ]] || exit 1
if [[ -n ${DWM_TEST_FEH_FAIL_DISPLAY:-} && ${DISPLAY:-} == "$DWM_TEST_FEH_FAIL_DISPLAY" ]]; then
	exit 1
fi
if [[ -n ${DWM_TEST_FEH_IGNORE_TERM:-} ]]; then
	trap '' TERM
fi
if [[ -n ${DWM_TEST_FEH_BLOCK:-} ]]; then
	should_block=true
	if [[ -n ${DWM_TEST_FEH_BLOCK_PATH:-} ]]; then
		should_block=false
		for argument in "$@"; do
			[[ $argument != "$DWM_TEST_FEH_BLOCK_PATH" ]] || should_block=true
		done
	fi
	if [[ $should_block == true ]]; then
		[[ -z ${DWM_TEST_FEH_PID_FILE:-} ]] || printf '%s\n' "$$" >"$DWM_TEST_FEH_PID_FILE"
		sleep 5
	fi
fi
if [[ -n ${DWM_TEST_FEH_FAIL_PATH:-} ]]; then
	for argument in "$@"; do
		[[ $argument != "$DWM_TEST_FEH_FAIL_PATH" ]] || exit 1
	done
fi
if [[ -n ${DWM_TEST_FEH_MUTATE_CONFIG:-} ]]; then
	for argument in "$@"; do
		[[ $argument != --randomize ]] || {
			printf 'version=1\npath=%s\nfit=max\n' \
				"${DWM_TEST_FEH_RANDOM_MUTATE_PATH:-$DWM_TEST_FEH_MUTATE_PATH}" \
				>"$DWM_TEST_FEH_MUTATE_CONFIG"
		}
	done
fi
if [[ -n ${DWM_TEST_FEH_MUTATE_SELECTION_PATH:-} ]]; then
	for argument in "$@"; do
		[[ $argument != "$DWM_TEST_FEH_MUTATE_SELECTION_PATH" ]] ||
			printf 'version=1\npath=%s\nfit=max\n' "$DWM_TEST_FEH_MUTATE_PATH" \
				>"$DWM_TEST_FEH_MUTATE_CONFIG"
	done
fi
EOF
chmod +x "$bin_dir/feh"

run_helper() {
	DISPLAY=:915 HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
		DWM_TEST_FEH_LOG=$log PATH="$bin_dir:$PATH" "$helper" "$@"
}

run_helper_display() {
	local display=$1
	shift
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
		XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
		DWM_TEST_FEH_LOG=$log PATH="$bin_dir:$PATH" "$helper" "$@"
}

process_running() {
	local pid=$1 record
	[[ $pid =~ ^[1-9][0-9]*$ && -r /proc/$pid/stat ]] || return 1
	record=$(sed 's/^.*) //' "/proc/$pid/stat" 2>/dev/null) || return 1
	[[ ${record%% *} != Z ]]
}

read_only_initial=$(run_helper status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper changes are unavailable in this session' \
	<<<"$read_only_initial"
test ! -e "$config_home/dwm-titus"
test ! -e "$state_home/dwm-titus"
test ! -e "$runtime/dwm-settings-wallpaper"

missing_feh_status=$(DWM_WALLPAPER_FEH=$work/missing-feh \
	run_helper status --read-only)
grep -Fqx $'provider\twallpaper\tpartial\tuser-session\tFeh is optional and is not installed' \
	<<<"$missing_feh_status"
grep -Fqx $'selection\tpartial\t\tfill\tNo managed wallpaper selection; session startup uses the legacy random wallpaper' \
	<<<"$missing_feh_status"
grep -Fqx $'mutation\trestricted\tWallpaper changes are unavailable in this session' \
	<<<"$missing_feh_status"
test ! -e "$state_home/dwm-titus"
test ! -e "$runtime/dwm-settings-wallpaper"

mv -- "$wallpaper_dir" "$work/backgrounds.saved"
if run_helper session-apply >/dev/null 2>&1; then
	printf 'Missing optional wallpaper default unexpectedly applied\n' >&2
	exit 1
fi
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
external_without_default=$work/external-without-default.jpg
printf 'external image\n' >"$external_without_default"
if run_helper preview no-rollback-target 20 "$external_without_default" fill \
	>"$work/no-rollback-preview.out" 2>"$work/no-rollback-preview.err"; then
	printf 'Wallpaper preview started without a rollback target\n' >&2
	exit 1
fi
grep -Fq 'cannot start without a recoverable current or default wallpaper' \
	"$work/no-rollback-preview.err"
if run_helper apply "$external_without_default" fill \
	>"$work/no-rollback-apply.out" 2>"$work/no-rollback-apply.err"; then
	printf 'Wallpaper apply started without a rollback target\n' >&2
	exit 1
fi
grep -Fq 'cannot be changed without a recoverable current or default wallpaper' \
	"$work/no-rollback-apply.err"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
no_rollback_status=$(run_helper status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper changes require a recoverable current or default wallpaper' \
	<<<"$no_rollback_status"
if run_helper mutation-ready; then
	printf 'Wallpaper mutation probe succeeded without a recoverable baseline\n' >&2
	exit 1
fi
run_helper reset-ready
grep -Fqx $'reset\tavailable\tWallpaper selection can be reset to the session default' \
	<<<"$no_rollback_status"
mkdir "$wallpaper_dir"
empty_default_status=$(run_helper status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper changes require a recoverable current or default wallpaper' \
	<<<"$empty_default_status"
rmdir "$wallpaper_dir"
mv -- "$work/backgrounds.saved" "$wallpaper_dir"

# Session initialization primes the read-only mutation capability cache before
# the first Settings inventory request.
rm -f -- "$runtime/dwm-settings-wallpaper/exchange-support"
run_helper session-apply
session_status=$(run_helper status --read-only)
grep -Fqx $'mutation\tavailable\tWallpaper preview and user-session changes are available' \
	<<<"$session_status"
ready_missing_feh_status=$(DWM_WALLPAPER_FEH=$work/missing-feh \
	run_helper status --read-only)
grep -Fqx $'provider\twallpaper\tpartial\tuser-session\tFeh is optional and is not installed' \
	<<<"$ready_missing_feh_status"
grep -Fqx $'mutation\trestricted\tWallpaper changes are unavailable in this session' \
	<<<"$ready_missing_feh_status"

# Default mode keeps Feh's per-monitor behavior by applying a bounded random
# path list instead of collapsing every Xinerama head onto one image.
: >"$log"
cat >"$bin_dir/xrandr" <<'EOF'
#!/bin/sh
[ "$*" = "--display :915 --listmonitors" ] || exit 2
printf 'Monitors: 2\n'
printf ' 0: +*DP-1 1920/520x1080/290+0+0  DP-1\n'
printf ' 1: +HDMI-1 1920/520x1080/290+1920+0  HDMI-1\n'
EOF
chmod +x "$bin_dir/xrandr"
run_helper session-apply
test "$(grep -Fxc 'call' "$log")" -eq 1
grep -Fqx "arg=$wallpaper_dir/Nord One.png" "$log"
grep -Fqx "arg=$wallpaper_dir/forest.jpg" "$log"
multi_monitor_preview=$work/multi-monitor-preview.jpg
printf 'preview image\n' >"$multi_monitor_preview"
run_helper preview multi-monitor-baseline 20 "$multi_monitor_preview" fill >/dev/null
multi_monitor_meta=$state_home/dwm-titus/appearance/wallpaper/multi-monitor-baseline.meta
test "$(grep -Fc 'baseline_path=' "$multi_monitor_meta")" -eq 2
: >"$log"
run_helper revert multi-monitor-baseline >/dev/null
rm -f -- "$bin_dir/xrandr"
test "$(grep -Fxc 'call' "$log")" -eq 1
grep -Fqx "arg=$wallpaper_dir/Nord One.png" "$log"
grep -Fqx "arg=$wallpaper_dir/forest.jpg" "$log"
rm -f -- "$multi_monitor_preview"

status=$(run_helper status)
grep -Fqx $'wallpaper-protocol\t1\t0' <<<"$status"
grep -Fqx $'selection\tpartial\t\tfill\tNo managed wallpaper selection; session startup uses the legacy random wallpaper' \
	<<<"$status"
grep -Fqx $'mutation\tavailable\tWallpaper preview and user-session changes are available' <<<"$status"
run_helper mutation-ready

# The readiness probe consumes its bounded Feh scan before returning so a
# decoder that emits one candidate and then stalls cannot survive the probe.
loadable_block_pid_file=$work/loadable-block.pid
export DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE=$loadable_block_pid_file
run_helper mutation-ready
unset DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE
loadable_block_pid=$(cat "$loadable_block_pid_file")
if process_running "$loadable_block_pid"; then
	printf 'Wallpaper readiness probe leaked its bounded Feh scan\n' >&2
	exit 1
fi

# Terminating a read-only status request also terminates its decoder scan so
# closing the Appearance pane cannot leave recursive wallpaper work behind.
loadable_cancel_pid_file=$work/loadable-cancel.pid
export DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE=$loadable_cancel_pid_file
DISPLAY=:915 HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_FEH_LOG=$log PATH="$bin_dir:$PATH" "$helper" status --read-only \
	>"$work/cancelled-status.out" 2>"$work/cancelled-status.err" &
cancelled_status_pid=$!
for _ in {1..100}; do
	[[ ! -s $loadable_cancel_pid_file ]] || break
	sleep 0.01
done
[[ -s $loadable_cancel_pid_file ]]
loadable_cancel_pid=$(cat "$loadable_cancel_pid_file")
kill -TERM "$cancelled_status_pid"
wait "$cancelled_status_pid" || [[ $? -eq 143 ]]
unset DWM_TEST_FEH_LOADABLE_BLOCK_PID_FILE
for _ in {1..100}; do
	process_running "$loadable_cancel_pid" || break
	sleep 0.01
done
if process_running "$loadable_cancel_pid"; then
	printf 'Terminated wallpaper status left its Feh scan running\n' >&2
	exit 1
fi

# Rollback readiness must continue past an invalid extension-matching entry to
# a later usable default image.
invalid_baseline=$wallpaper_dir/invalid$'\034'.png
printf 'invalid image path\n' >"$invalid_baseline"
export DWM_TEST_INVALID_BASELINE=$invalid_baseline
export DWM_TEST_VALID_BASELINE=$wallpaper_dir/Nord\ One.png
baseline_status=$(run_helper status --read-only)
unset DWM_TEST_INVALID_BASELINE DWM_TEST_VALID_BASELINE
rm -f -- "$invalid_baseline"
grep -Fqx $'mutation\tavailable\tWallpaper preview and user-session changes are available' \
	<<<"$baseline_status"

first=$wallpaper_dir/Nord\ One.png
second=$wallpaper_dir/forest.jpg
mkdir -p "$config_home/dwm-titus"
chmod 750 "$config_home/dwm-titus"
apply_output=$(run_helper apply "$first" max)
grep -Fqx $'wallpaper-action-protocol\t1\t0' <<<"$apply_output"
grep -Fqx $'result\tapply\t'"$first"$'\tmax' <<<"$apply_output"
cat >"$work/expected.conf" <<EOF
version=1
mode=selection
path=$first
fit=max
EOF
cmp "$work/expected.conf" "$config_home/dwm-titus/wallpaper.conf"
test "$(stat -c %a "$config_home/dwm-titus/wallpaper.conf")" = 600
test "$(stat -c %a "$config_home/dwm-titus")" = 750
grep -Fqx 'arg=--no-fehbg' "$log"
grep -Fqx 'arg=--bg-max' "$log"
grep -Fqx 'arg=--' "$log"
grep -Fqx "arg=$first" "$log"
test ! -e "$home/.fehbg"

# Read-only status probes the configured selection and fallback inventory in a
# single bounded Feh call, leaving headroom for the outer Appearance provider.
loadable_count_file=$work/loadable-count
printf '0\n' >"$loadable_count_file"
export DWM_TEST_FEH_LOADABLE_COUNT_FILE=$loadable_count_file
run_helper status --read-only >/dev/null
unset DWM_TEST_FEH_LOADABLE_COUNT_FILE
grep -Fqx '1' "$loadable_count_file"

: >"$log"
run_helper session-apply
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-max' "$log"

# A one-off random wallpaper keeps the saved selection authoritative for the
# next session while previews restore the exact randomized image currently live.
cp -- "$config_home/dwm-titus/wallpaper.conf" "$work/before-randomize.conf"
export DWM_TEST_DEFAULT_CANDIDATE=$second
randomize_output=$(run_helper randomize)
unset DWM_TEST_DEFAULT_CANDIDATE
grep -Fqx $'result\trandomize\tapplied' <<<"$randomize_output"
cmp "$work/before-randomize.conf" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "path=$second" "$state_home/dwm-titus/appearance/wallpaper/session.default"
randomize_preview=$work/randomize-preview.jpg
printf 'randomize preview\n' >"$randomize_preview"
run_helper preview randomize-baseline 20 "$randomize_preview" fill >/dev/null
: >"$log"
run_helper revert randomize-baseline >/dev/null
grep -Fqx "arg=$second" "$log"
: >"$log"
run_helper session-apply
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-max' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/session.default"
rm -f -- "$randomize_preview"

# startx may export XAUTHORITY as a path relative to its launch directory.
# Persist the resolved path so preview recovery still works from a watchdog or
# a later helper process with a different working directory.
relative_session=$work/relative-session
mkdir -p "$relative_session"
: >"$relative_session/.Xauthority"
: >"$log"
(
	cd "$relative_session"
	XAUTHORITY=.Xauthority run_helper apply "$first" max >/dev/null
	XAUTHORITY=.Xauthority run_helper preview relative-authority 20 "$second" fill >/dev/null
)
grep -Fqx "xauthority=$relative_session/.Xauthority" "$log"
grep -Fqx "xauthority=$relative_session/.Xauthority" \
	"$state_home/dwm-titus/appearance/wallpaper/relative-authority.meta"
: >"$log"
run_helper revert relative-authority >/dev/null
grep -Fqx "xauthority=$relative_session/.Xauthority" "$log"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"

if run_helper preview leading-zero-duration 08 "$second" fill \
	>"$work/leading-zero.out" 2>"$work/leading-zero.err"; then
	printf 'Wallpaper preview accepted a leading-zero duration\n' >&2
	exit 1
fi
grep -Fq 'preview timeout must be between 1 and 99 seconds' "$work/leading-zero.err"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"

preview_output=$(run_helper preview keep-me 20 "$second" tile)
grep -Fqx $'preview\tkeep-me\t20\t'"$second"$'\ttile' <<<"$preview_output"
preview_status=$(run_helper status)
grep -Eq $'^preview\tactive\tkeep-me\t([1-9]|1[0-9]|20)\t'"${second//./\.}"$'\ttile\t' <<<"$preview_status"
: >"$log"
export DWM_TEST_FEH_FAIL_ALL=1
read_only_status=$(run_helper status --read-only)
unset DWM_TEST_FEH_FAIL_ALL
grep -Fq $'preview\tactive\tkeep-me\t' <<<"$read_only_status"
test ! -s "$log"
preview_meta=$state_home/dwm-titus/appearance/wallpaper/keep-me.meta
watchdog_pid=$(awk -F= '$1 == "pid" { print $2 }' "$preview_meta")
watchdog_sleep_pid=
for _ in {1..40}; do
	watchdog_sleep_pid=$(pgrep -P "$watchdog_pid" -x sleep 2>/dev/null || true)
	[[ -n $watchdog_sleep_pid ]] && break
	sleep 0.025
done
[[ -n $watchdog_sleep_pid ]]

# Read-only status must not claim that a dead watchdog is still armed. It leaves
# state untouched so a later writable status can perform the rearm.
kill -TERM "$watchdog_pid"
for _ in {1..40}; do
	process_running "$watchdog_pid" || break
	sleep 0.025
done
dead_watchdog_status=$(run_helper status --read-only)
grep -Fqx $'preview\tfailed\tkeep-me\t0\t'"$second"$'\ttile\tAutomatic wallpaper rollback is not armed; run a writable status check to recover' \
	<<<"$dead_watchdog_status"
test -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
preview_status=$(run_helper status)
grep -Eq $'^preview\tactive\tkeep-me\t([1-9]|1[0-9]|20)\t'"${second//./\.}"$'\ttile\t' \
	<<<"$preview_status"
rearmed_watchdog_pid=$(awk -F= '$1 == "pid" { print $2 }' "$preview_meta")
test "$rearmed_watchdog_pid" != "$watchdog_pid"
process_running "$rearmed_watchdog_pid"
watchdog_pid=$rearmed_watchdog_pid
: >"$log"
run_helper keep keep-me >/dev/null
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "arg=$second" "$log"
grep -Fqx 'arg=--bg-tile' "$log"
grep -Fqx 'display=:915' "$log"

# A saved image that Feh cannot decode falls back to an exact loadable session
# default instead of leaving login without either wallpaper path.
: >"$log"
export DWM_TEST_FEH_FAIL_PATH=$second
run_helper session-apply
grep -Fqx "arg=$second" "$log"
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-fill' "$log"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"
degraded_status=$(run_helper status --read-only)
grep -Fqx $'selection\tpartial\t'"$second"$'\ttile\tConfigured wallpaper could not be applied; the legacy random wallpaper fallback is required' \
	<<<"$degraded_status"
test -f "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
grep -Fqx 'version=3' "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
replacement=$work/replacement.jpg
printf 'replacement image\n' >"$replacement"
export DWM_TEST_DEFAULT_CANDIDATE=$first
: >"$log"
run_helper preview degraded-baseline 20 "$replacement" fill >/dev/null
grep -Fqx "baseline_path=$first" \
	"$state_home/dwm-titus/appearance/wallpaper/degraded-baseline.meta"
run_helper revert degraded-baseline >/dev/null
unset DWM_TEST_DEFAULT_CANDIDATE DWM_TEST_FEH_FAIL_PATH
grep -Fqx "arg=$first" "$log"
if grep -Fqx "arg=$second" "$log"; then
	printf 'Preview retried a failed selection instead of its exact session baseline\n' >&2
	exit 1
fi
rm -f -- "$replacement"
for reserved_token in selection mutation; do
	if run_helper preview "$reserved_token" 20 "$first" fill \
		>"$work/reserved-$reserved_token.out" 2>"$work/reserved-$reserved_token.err"; then
		printf 'Reserved wallpaper preview token was accepted: %s\n' "$reserved_token" >&2
		exit 1
	fi
	grep -Fq 'invalid wallpaper preview token' "$work/reserved-$reserved_token.err"
done
test -f "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
run_helper session-apply
ready_status=$(run_helper status --read-only)
grep -Fqx $'selection\tavailable\t'"$second"$'\ttile\tManaged wallpaper selection is ready for this and future sessions' \
	<<<"$ready_status"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.owner"

# Confirming a successfully applied preview retires a transient failure from
# the same display even when the confirmed config hash is unchanged.
transient_keep_failure_count=$work/transient-keep-failure.count
printf '1\n' >"$transient_keep_failure_count"
export DWM_TEST_FEH_FAIL_COUNT_FILE=$transient_keep_failure_count
export DWM_TEST_DEFAULT_CANDIDATE=$first
run_helper preview recovered-keep 20 "$second" tile >/dev/null
unset DWM_TEST_FEH_FAIL_COUNT_FILE DWM_TEST_DEFAULT_CANDIDATE
test -f "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
run_helper keep recovered-keep >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.owner"

# Read-only state verifies Feh loadability rather than treating a readable file
# with a supported suffix as a usable saved selection.
export DWM_TEST_FEH_FAIL_PATH=$second
undecodable_status=$(run_helper status --read-only)
unset DWM_TEST_FEH_FAIL_PATH
grep -Fqx $'selection\tpartial\t'"$second"$'\ttile\tConfigured wallpaper is missing or undecodable; session startup falls back to the legacy random wallpaper' \
	<<<"$undecodable_status"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
for _ in {1..40}; do
	process_running "$watchdog_pid" || break
	sleep 0.025
done
if process_running "$watchdog_pid"; then
	printf 'Wallpaper preview watchdog survived keep\n' >&2
	exit 1
fi
if process_running "$watchdog_sleep_pid"; then
	printf 'Wallpaper preview watchdog left an orphaned sleep\n' >&2
	exit 1
fi

run_helper preview revert-me 20 "$first" center >/dev/null
: >"$log"
run_helper revert revert-me >/dev/null
grep -Fqx "arg=$second" "$log"
grep -Fqx 'arg=--bg-tile' "$log"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"

run_helper preview rearm-me 20 "$first" fill >/dev/null
rearm_meta=$state_home/dwm-titus/appearance/wallpaper/rearm-me.meta
rearm_pid=$(awk -F= '$1 == "pid" { print $2 }' "$rearm_meta")
kill -TERM "$rearm_pid"
for _ in {1..40}; do
	process_running "$rearm_pid" || break
	sleep 0.025
done
sed -i "s/^pid=.*/pid=$$/; s/^pid_start=.*/pid_start=1/" "$rearm_meta"
run_helper status >/dev/null
new_rearm_pid=$(awk -F= '$1 == "pid" { print $2 }' "$rearm_meta")
test "$new_rearm_pid" != "$$"
kill -0 "$new_rearm_pid"
run_helper revert rearm-me >/dev/null

run_helper preview expire-me 2 "$first" scale >/dev/null
sleep 2.25
for _ in {1..80}; do
	preview_status=$(run_helper status)
	grep -Fqx $'preview\tnone\t\t0\t\tfill\tNo wallpaper preview is active' <<<"$preview_status" && break
	sleep 0.025
done
grep -Fqx $'preview\tnone\t\t0\t\tfill\tNo wallpaper preview is active' <<<"$preview_status"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"

# Confirmation must fail after the deadline even when no status request has
# reconciled preview metadata yet.
run_helper preview expired-keep 2 "$first" scale >/dev/null
sleep 2.25
if run_helper keep expired-keep >"$work/expired-keep.out" 2>"$work/expired-keep.err"; then
	printf 'Expired wallpaper preview was kept\n' >&2
	exit 1
fi
grep -Eq 'wallpaper preview has expired|wallpaper preview is not active' \
	"$work/expired-keep.err"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"

run_helper preview external-change 20 "$first" fill >/dev/null
cat >"$config_home/dwm-titus/wallpaper.conf" <<EOF
version=1
path=$second
fit=center
EOF
if run_helper revert external-change >"$work/revert.out" 2>"$work/revert.err"; then
	printf 'Wallpaper revert overwrote an external config change\n' >&2
	exit 1
fi
grep -Fq 'changed outside the preview' "$work/revert.err"
failed_status=$(run_helper status)
grep -Fq $'preview\tfailed\texternal-change\t0\t' <<<"$failed_status"
run_helper abandon external-change >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=center' "$config_home/dwm-titus/wallpaper.conf"

run_helper preview symlinked-failure 20 "$first" fill >/dev/null
symlink_failure_target=$work/symlink-failure-target
printf 'preserve symlink target\n' >"$symlink_failure_target"
ln -s "$symlink_failure_target" \
	"$state_home/dwm-titus/appearance/wallpaper/symlinked-failure.failed"
cat >"$config_home/dwm-titus/wallpaper.conf" <<EOF
version=1
path=$first
fit=max
EOF
if run_helper revert symlinked-failure >/dev/null 2>"$work/symlinked-failure.err"; then
	printf 'Wallpaper revert accepted an external config change\n' >&2
	exit 1
fi
grep -Fqx 'preserve symlink target' "$symlink_failure_target"
test ! -L "$state_home/dwm-titus/appearance/wallpaper/symlinked-failure.failed"
test "$(stat -c %h "$state_home/dwm-titus/appearance/wallpaper/symlinked-failure.failed")" = 1
run_helper abandon symlinked-failure >/dev/null

run_helper preview hardlinked-failure 20 "$second" fill >/dev/null
hardlink_failure_target=$work/hardlink-failure-target
printf 'preserve hardlink target\n' >"$hardlink_failure_target"
ln "$hardlink_failure_target" \
	"$state_home/dwm-titus/appearance/wallpaper/hardlinked-failure.failed"
cat >"$config_home/dwm-titus/wallpaper.conf" <<EOF
version=1
path=$second
fit=center
EOF
if run_helper revert hardlinked-failure >/dev/null 2>"$work/hardlinked-failure.err"; then
	printf 'Wallpaper revert accepted an external config change\n' >&2
	exit 1
fi
grep -Fqx 'preserve hardlink target' "$hardlink_failure_target"
test "$(stat -c %h "$hardlink_failure_target")" = 1
test "$(stat -c %h "$state_home/dwm-titus/appearance/wallpaper/hardlinked-failure.failed")" = 1
run_helper abandon hardlinked-failure >/dev/null

preview_auth=$work/preview.xauth
caller_auth=$work/caller.xauth
export XAUTHORITY=$preview_auth
run_helper preview external-expiry 2 "$first" fill >/dev/null
external_expiry_meta=$state_home/dwm-titus/appearance/wallpaper/external-expiry.meta
external_expiry_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$external_expiry_meta")
kill -TERM "$external_expiry_watchdog"
for _ in {1..40}; do
	process_running "$external_expiry_watchdog" || break
	sleep 0.025
done
: >"$log"
export XAUTHORITY=$caller_auth
cat >"$config_home/dwm-titus/wallpaper.conf" <<EOF
version=1
mode=selection
path=$second
fit=center
EOF
sleep 2.25
for _ in {1..80}; do
	preview_status=$(run_helper_display :916 status)
	grep -Fqx $'preview\tnone\t\t0\t\tfill\tNo wallpaper preview is active' <<<"$preview_status" && break
	sleep 0.025
done
grep -Fqx $'preview\tnone\t\t0\t\tfill\tNo wallpaper preview is active' <<<"$preview_status"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=center' "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "arg=$second" "$log"
grep -Fqx 'arg=--bg-center' "$log"
grep -Fqx 'display=:915' "$log"
grep -Fqx "xauthority=$preview_auth" "$log"
if grep -Fqx 'display=:916' "$log"; then
	printf 'External preview expiry applied rollback on the caller display\n' >&2
	exit 1
fi
if grep -Fqx "xauthority=$caller_auth" "$log"; then
	printf 'External preview expiry used the caller X authority\n' >&2
	exit 1
fi
unset XAUTHORITY

run_helper preview failed-abandon 20 "$first" fill >/dev/null
printf '%s\n' 'Configured and fallback wallpapers are unavailable' \
	>"$state_home/dwm-titus/appearance/wallpaper/failed-abandon.failed"
rm -f -- "$second"
export DWM_TEST_FEH_FAIL_PATH=$wallpaper_dir
run_helper abandon failed-abandon >/dev/null
unset DWM_TEST_FEH_FAIL_PATH
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
printf 'second image\n' >"$second"

rm -f "$second"
missing_status=$(run_helper status)
grep -Fqx $'selection\tpartial\t'"$second"$'\tcenter\tConfigured wallpaper is missing or undecodable; session startup falls back to the legacy random wallpaper' \
	<<<"$missing_status"
: >"$log"
mkdir -p "$wallpaper_dir/nested"
nested_first=$wallpaper_dir/nested/Nord\ One.png
mv -- "$first" "$nested_first"
run_helper session-apply
grep -Fqx 'arg=--bg-fill' "$log"
grep -Fqx 'arg=--' "$log"
grep -Fqx "arg=$nested_first" "$log"
mv -- "$nested_first" "$first"

# Reset must not delete a configuration published while Feh is running.
printf 'second image\n' >"$second"
export DWM_TEST_FEH_MUTATE_CONFIG=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_FEH_MUTATE_PATH=$first
export DWM_TEST_DEFAULT_CANDIDATE=$second
export DWM_TEST_FEH_MUTATE_SELECTION_PATH=$second
if run_helper reset >"$work/reset-race.out" 2>"$work/reset-race.err"; then
	printf 'Wallpaper reset deleted a concurrent configuration change\n' >&2
	exit 1
fi
unset DWM_TEST_DEFAULT_CANDIDATE DWM_TEST_FEH_MUTATE_CONFIG DWM_TEST_FEH_MUTATE_PATH
unset DWM_TEST_FEH_MUTATE_SELECTION_PATH
grep -Fq 'changed while' "$work/reset-race.err"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"

reset_output=$(run_helper reset)
grep -Fqx $'result\treset\tapplied' <<<"$reset_output"
grep -Fqx 'version=1' "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'mode=default' "$config_home/dwm-titus/wallpaper.conf"

# A reset whose optional default cannot be applied still publishes default mode
# when no live recovery record is pending.
export DWM_TEST_FEH_FAIL_ALL=1
reset_output=$(run_helper reset)
grep -Fqx $'result\treset\tunavailable' <<<"$reset_output"
grep -Fqx 'mode=default' "$config_home/dwm-titus/wallpaper.conf"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
unset DWM_TEST_FEH_FAIL_ALL

# A reset that cannot apply the default must not clear pending live recovery.
printf '%s\n' 'Wallpaper live rollback failed; retry session recovery before previewing' \
	>"$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
chmod 600 "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
export DWM_TEST_FEH_FAIL_ALL=1
reset_output=$(run_helper reset)
grep -Fqx $'result\treset\tunavailable' <<<"$reset_output"
test -f "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
recovery_status=$(run_helper status)
grep -Fqx $'mutation\trestricted\tWallpaper live rollback failed; retry session recovery before previewing' \
	<<<"$recovery_status"
unset DWM_TEST_FEH_FAIL_ALL
run_helper session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"

# Default-mode preview rollback restores the exact image that was visible when
# the preview began, even if a later default scan would choose another image.
export DWM_TEST_DEFAULT_CANDIDATE=$first
run_helper session-apply
grep -Fqx "path=$first" "$state_home/dwm-titus/appearance/wallpaper/session.default"
run_helper preview exact-default-baseline 20 "$second" fill >/dev/null
export DWM_TEST_DEFAULT_CANDIDATE=$second
: >"$log"
run_helper revert exact-default-baseline >/dev/null
unset DWM_TEST_DEFAULT_CANDIDATE
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-fill' "$log"
if grep -Fqx "arg=$second" "$log"; then
	printf 'Default-mode rollback selected a new random wallpaper\n' >&2
	exit 1
fi

# If the exact baseline becomes undecodable during a preview, rollback falls
# back to another loadable default instead of leaving the preview live.
fallback=$work/fallback.png
printf 'fallback image\n' >"$fallback"
export DWM_TEST_DEFAULT_CANDIDATE=$first
run_helper preview unreadable-exact-baseline 20 "$second" fill >/dev/null
export DWM_TEST_FEH_FAIL_PATH=$first
export DWM_TEST_DEFAULT_CANDIDATE=$fallback
: >"$log"
run_helper revert unreadable-exact-baseline >/dev/null
unset DWM_TEST_DEFAULT_CANDIDATE DWM_TEST_FEH_FAIL_PATH
grep -Fqx "arg=$first" "$log"
grep -Fqx "arg=$fallback" "$log"
rm -f -- "$fallback"

# A config edit made while Feh is restoring a preview must be applied before
# the helper clears the recovery record.
export DWM_TEST_DEFAULT_CANDIDATE=$first
run_helper preview rollback-config-race 20 "$second" fill >/dev/null
: >"$log"
export DWM_TEST_FEH_MUTATE_CONFIG=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_FEH_MUTATE_PATH=$first
export DWM_TEST_FEH_MUTATE_SELECTION_PATH=$first
run_helper revert rollback-config-race >/dev/null
unset DWM_TEST_DEFAULT_CANDIDATE DWM_TEST_FEH_MUTATE_CONFIG DWM_TEST_FEH_MUTATE_PATH
unset DWM_TEST_FEH_MUTATE_SELECTION_PATH
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-max' "$log"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"

printf 'second image\n' >"$second"
run_helper preview unsafe-config-abandon 20 "$first" fill >/dev/null
rm -f -- "$config_home/dwm-titus/wallpaper.conf"
ln -s "$work/unsafe.conf" "$config_home/dwm-titus/wallpaper.conf"
printf '%s\n' 'Wallpaper configuration became unsafe during preview' \
	>"$state_home/dwm-titus/appearance/wallpaper/unsafe-config-abandon.failed"
chmod 600 "$state_home/dwm-titus/appearance/wallpaper/unsafe-config-abandon.failed"
if run_helper mutation-ready; then
	printf 'Symlinked wallpaper config was mutation-ready\n' >&2
	exit 1
fi
unsafe_status=$(run_helper status)
grep -Fqx $'selection\tunavailable\t\tfill\tWallpaper configuration is invalid or unsafe' <<<"$unsafe_status"
abandon_output=$(run_helper abandon unsafe-config-abandon)
grep -Fqx $'result\tabandon\tunsafe-config-abandon' <<<"$abandon_output"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test -L "$config_home/dwm-titus/wallpaper.conf"
if run_helper apply "$first" fill >"$work/unsafe.out" 2>"$work/unsafe.err"; then
	printf 'Symlinked wallpaper config accepted a mutation\n' >&2
	exit 1
fi
test ! -e "$work/unsafe.conf"
rm -f "$config_home/dwm-titus/wallpaper.conf"

# A malformed regular config remains readable as an attributed failure, but it
# cannot advertise or accept a mutation that would overwrite unknown contents.
printf 'not a wallpaper config\n' >"$config_home/dwm-titus/wallpaper.conf"
malformed_status=$(run_helper status --read-only)
grep -Fqx $'selection\tunavailable\t\tfill\tWallpaper configuration is invalid or unsafe' \
	<<<"$malformed_status"
grep -Fqx $'mutation\trestricted\tWallpaper configuration is invalid or unsafe' \
	<<<"$malformed_status"
if run_helper mutation-ready; then
	printf 'Malformed wallpaper config was mutation-ready\n' >&2
	exit 1
fi
: >"$log"
if run_helper preview malformed-config 20 "$first" fill \
	>"$work/malformed-preview.out" 2>"$work/malformed-preview.err"; then
	printf 'Malformed wallpaper config accepted a preview\n' >&2
	exit 1
fi
if run_helper apply "$first" fill \
	>"$work/malformed-apply.out" 2>"$work/malformed-apply.err"; then
	printf 'Malformed wallpaper config accepted an apply\n' >&2
	exit 1
fi
grep -Fqx 'not a wallpaper config' "$config_home/dwm-titus/wallpaper.conf"
test ! -s "$log"
rm -f -- "$config_home/dwm-titus/wallpaper.conf"

if run_helper apply "$first" stretch >/dev/null 2>&1; then
	printf 'Unsupported wallpaper fit was accepted\n' >&2
	exit 1
fi
printf 'not an image\n' >"$wallpaper_dir/readme.txt"
if run_helper apply "$wallpaper_dir/readme.txt" fill >/dev/null 2>&1; then
	printf 'Unsupported wallpaper asset was accepted\n' >&2
	exit 1
fi
separator_path=$wallpaper_dir/unsafe$'\034'separator.png
printf 'unsafe separator image\n' >"$separator_path"
if run_helper apply "$separator_path" fill >/dev/null 2>&1; then
	printf 'Wallpaper path containing the inventory separator was accepted\n' >&2
	exit 1
fi

preview_current=$state_home/dwm-titus/appearance/wallpaper/preview.current
mkdir "$preview_current"
: >"$log"
if run_helper preview directory-owner 20 "$first" fill \
	>"$work/directory-owner.out" 2>"$work/directory-owner.err"; then
	printf 'Directory-valued wallpaper preview owner was accepted\n' >&2
	exit 1
fi
grep -Fq 'preview owner state is invalid' "$work/directory-owner.err"
test ! -s "$log"
rmdir "$preview_current"
run_helper session-apply

# Config publication and removal use a no-clobber capture so a late external
# writer wins without leaving the just-applied live wallpaper unpersisted.
real_mv=$(command -v mv)
cat >"$bin_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
arguments=("$@")
source_path=${arguments[${#arguments[@]}-2]}
destination_path=${arguments[${#arguments[@]}-1]}
if [[ ${DWM_TEST_MV_MODE:-} == fail-publish && $source_path == *.staged.* ]]; then
	exit 1
fi
if [[ ${DWM_TEST_MV_MODE:-} == fail-exchange && $source_path == *.wallpaper-exchange-a.* ]]; then
	exit 1
fi
if [[ ${DWM_TEST_MV_MODE:-} == fail-session-default &&
	$destination_path == "$DWM_TEST_SESSION_DEFAULT" ]]; then
	exit 1
fi
if [[ ${DWM_TEST_MV_MODE:-} == race-publish && $destination_path == "$DWM_TEST_CONFIG_FILE" ]]; then
	printf 'version=1\npath=%s\nfit=tile\n' "$DWM_TEST_EXTERNAL_PATH" >"$destination_path"
fi
if [[ ${DWM_TEST_MV_MODE:-} == race-rollback-fail && $destination_path == "$DWM_TEST_CONFIG_FILE" ]]; then
	for argument in "${arguments[@]}"; do
		[[ $argument == --exchange ]] || continue
		count=0
		[[ ! -f $DWM_TEST_EXCHANGE_COUNT ]] || count=$(<"$DWM_TEST_EXCHANGE_COUNT")
		((count += 1))
		printf '%s\n' "$count" >"$DWM_TEST_EXCHANGE_COUNT"
		if ((count == 1)); then
			printf 'version=1\npath=%s\nfit=tile\n' "$DWM_TEST_EXTERNAL_PATH" >"$destination_path"
		else
			exit 1
		fi
		break
	done
fi
if [[ ${DWM_TEST_MV_MODE:-} == race-compensating-exchange &&
	$destination_path == "$DWM_TEST_CONFIG_FILE" ]]; then
	for argument in "${arguments[@]}"; do
		[[ $argument == --exchange ]] || continue
		count=0
		[[ ! -f $DWM_TEST_EXCHANGE_COUNT ]] || count=$(<"$DWM_TEST_EXCHANGE_COUNT")
		((count += 1))
		printf '%s\n' "$count" >"$DWM_TEST_EXCHANGE_COUNT"
		if ((count == 1)); then
			printf 'version=1\npath=%s\nfit=tile\n' "$DWM_TEST_EXTERNAL_PATH" >"$destination_path"
		elif ((count == 2)); then
			printf 'version=1\npath=%s\nfit=fill\n' "$DWM_TEST_LATE_EXTERNAL_PATH" >"$destination_path"
		fi
		break
	done
fi
if [[ ${DWM_TEST_MV_MODE:-} == directory-publish && $destination_path == "$DWM_TEST_CONFIG_FILE" ]]; then
	mkdir "$destination_path"
fi
if [[ ${DWM_TEST_MV_MODE:-} == block-preview-current &&
	$destination_path == "$DWM_TEST_PREVIEW_CURRENT" ]]; then
	"$DWM_TEST_REAL_MV" "$@"
	printf 'ready\n' >"$DWM_TEST_PREVIEW_READY"
	sleep 10
	exit 0
fi
if [[ ${DWM_TEST_MV_MODE:-} == block-before-preview-current &&
	$destination_path == "$DWM_TEST_PREVIEW_CURRENT" ]]; then
	printf 'ready\n' >"$DWM_TEST_PREVIEW_READY"
	sleep 10
fi
exec "$DWM_TEST_REAL_MV" "$@"
EOF
chmod +x "$bin_dir/mv"
export DWM_TEST_REAL_MV=$real_mv DWM_TEST_CONFIG_FILE=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_SESSION_DEFAULT=$state_home/dwm-titus/appearance/wallpaper/session.default
export DWM_TEST_EXTERNAL_PATH=$second

: >"$log"
export DWM_TEST_MV_MODE=fail-publish
if run_helper apply "$first" fill >"$work/publish-fail.out" 2>"$work/publish-fail.err"; then
	printf 'Wallpaper apply succeeded without publishing its configuration\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
test ! -e "$config_home/dwm-titus/wallpaper.conf"
grep -Fq 'could not be published' "$work/publish-fail.err"
test "$(grep -Fc call "$log")" -eq 3

export DWM_TEST_MV_MODE=directory-publish
if run_helper apply "$first" fill >"$work/directory-publish.out" 2>"$work/directory-publish.err"; then
	printf 'Wallpaper apply published its configuration inside a raced directory\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
test -d "$config_home/dwm-titus/wallpaper.conf"
test -z "$(find "$config_home/dwm-titus/wallpaper.conf" -mindepth 1 -print -quit)"
grep -Fq 'could not be published' "$work/directory-publish.err"
rmdir "$config_home/dwm-titus/wallpaper.conf"

run_helper apply "$first" center >/dev/null
export DWM_TEST_MV_MODE=race-publish
if run_helper apply "$second" max >"$work/apply-race.out" 2>"$work/apply-race.err"; then
	printf 'Wallpaper apply overwrote a late external configuration\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
grep -Fq 'changed or could not be published' "$work/apply-race.err"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"
recovery_configs=("$config_home"/dwm-titus/wallpaper.conf.staged.*)
test "${#recovery_configs[@]}" -eq 1
grep -Fqx "path=$second" "${recovery_configs[0]}"
grep -Fqx 'fit=tile' "${recovery_configs[0]}"
rm -f -- "${recovery_configs[0]}"

exchange_count=$work/exchange.count
export DWM_TEST_EXTERNAL_PATH=$first DWM_TEST_EXCHANGE_COUNT=$exchange_count
export DWM_TEST_MV_MODE=race-rollback-fail
if run_helper apply "$second" max >"$work/rollback-race.out" 2>"$work/rollback-race.err"; then
	printf 'Wallpaper apply succeeded after its compensating exchange failed\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
grep -Fq 'external wallpaper configuration retained at' "$work/rollback-race.err"
recovery_configs=("$config_home"/dwm-titus/wallpaper.conf.staged.*)
test "${#recovery_configs[@]}" -eq 1
grep -Fqx "path=$first" "${recovery_configs[0]}"
grep -Fqx 'fit=tile' "${recovery_configs[0]}"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"
rm -f -- "${recovery_configs[0]}" "$exchange_count"

run_helper apply "$first" center >/dev/null
export DWM_TEST_EXTERNAL_PATH=$second DWM_TEST_LATE_EXTERNAL_PATH=$first
export DWM_TEST_MV_MODE=race-compensating-exchange
if run_helper apply "$second" max >"$work/compensating-race.out" 2>"$work/compensating-race.err"; then
	printf 'Wallpaper apply discarded a config racing its compensating exchange\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
grep -Fq 'external wallpaper configuration retained at' "$work/compensating-race.err"
recovery_configs=("$config_home"/dwm-titus/wallpaper.conf.staged.*)
test "${#recovery_configs[@]}" -eq 1
grep -Fqx "path=$first" "${recovery_configs[0]}"
grep -Fqx 'fit=fill' "${recovery_configs[0]}"
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"
rm -f -- "${recovery_configs[0]}" "$exchange_count"

export DWM_TEST_EXTERNAL_PATH=$first
export DWM_TEST_MV_MODE=race-publish
if run_helper reset >"$work/reset-late-race.out" 2>"$work/reset-late-race.err"; then
	printf 'Wallpaper reset deleted a late external configuration\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE
grep -Eq 'changed|could not be published' "$work/reset-late-race.err"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"
recovery_configs=("$config_home"/dwm-titus/wallpaper.conf.staged.*)
test "${#recovery_configs[@]}" -eq 1
grep -Fqx "path=$first" "${recovery_configs[0]}"
grep -Fqx 'fit=tile' "${recovery_configs[0]}"
rm -f -- "${recovery_configs[0]}"

# Reset stages durable session state before publishing default mode and restores
# the prior config and live image if the final state-file rename fails.
run_helper apply "$first" center >/dev/null
: >"$log"
export DWM_TEST_MV_MODE=fail-session-default DWM_TEST_DEFAULT_CANDIDATE=$second
if run_helper reset >"$work/reset-session-state.out" 2>"$work/reset-session-state.err"; then
	printf 'Wallpaper reset succeeded without durable session state\n' >&2
	exit 1
fi
unset DWM_TEST_MV_MODE DWM_TEST_DEFAULT_CANDIDATE
grep -Fq 'prior selection was restored' "$work/reset-session-state.err"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=center' "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "arg=$second" "$log"
test "$(grep -Fxc "arg=$first" "$log")" -eq 2
test ! -e "$state_home/dwm-titus/appearance/wallpaper/session.default"
test -z "$(find "$state_home/dwm-titus/appearance/wallpaper" -maxdepth 1 \
	-name '.session-default.*' -print -quit)"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"

# The rollback watchdog is verified and detached before preview.current becomes
# visible, so interrupting the publishing helper cannot strand an unbounded
# preview with pid=0 metadata.
cat >"$bin_dir/setsid" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
chmod +x "$bin_dir/setsid"
: >"$log"
if run_helper preview watchdog-exec-failure 20 "$second" fill \
	>"$work/watchdog-exec.out" 2>"$work/watchdog-exec.err"; then
	printf 'Wallpaper preview accepted a watchdog that never execed the helper\n' >&2
	exit 1
fi
rm -f -- "$bin_dir/setsid"
grep -Fq 'wallpaper preview rollback could not be armed' "$work/watchdog-exec.err"
test ! -e "$preview_current"
if grep -Fqx "arg=$second" "$log"; then
	printf 'Wallpaper candidate was applied before watchdog readiness\n' >&2
	exit 1
fi

preview_publish_ready=$work/preview-publish.ready
export DWM_TEST_MV_MODE=block-preview-current
export DWM_TEST_PREVIEW_CURRENT=$preview_current DWM_TEST_PREVIEW_READY=$preview_publish_ready
setsid env DISPLAY=:915 HOME="$home" XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
	XDG_RUNTIME_DIR="$runtime" DWM_APPEARANCE_WALLPAPER_DIR="$wallpaper_dir" \
	DWM_TEST_FEH_LOG="$log" PATH="$bin_dir:$PATH" \
	"$helper" preview interrupted-publish 2 "$second" fill \
	>"$work/interrupted-publish.out" 2>"$work/interrupted-publish.err" &
interrupted_publish_pid=$!
for _ in {1..100}; do
	[[ -s $preview_publish_ready ]] && break
	sleep 0.01
done
[[ -s $preview_publish_ready ]]
kill -TERM -- "-$interrupted_publish_pid" 2>/dev/null || true
wait "$interrupted_publish_pid" 2>/dev/null || true
unset DWM_TEST_MV_MODE DWM_TEST_PREVIEW_CURRENT DWM_TEST_PREVIEW_READY
for _ in {1..80}; do
	[[ -e $preview_current || -L $preview_current ]] || break
	sleep 0.05
done
test ! -e "$preview_current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/interrupted-publish.meta"

# SIGKILL bypasses the setup trap. Reconciliation must use the durable owner
# token to reap the already-armed watchdog and remove its unpublished metadata.
rm -f -- "$preview_publish_ready"
export DWM_TEST_MV_MODE=block-before-preview-current
export DWM_TEST_PREVIEW_CURRENT=$preview_current DWM_TEST_PREVIEW_READY=$preview_publish_ready
setsid env DISPLAY=:915 HOME="$home" XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
	XDG_RUNTIME_DIR="$runtime" DWM_APPEARANCE_WALLPAPER_DIR="$wallpaper_dir" \
	DWM_TEST_FEH_LOG="$log" PATH="$bin_dir:$PATH" \
	"$helper" preview killed-before-publish 20 "$second" fill \
	>"$work/killed-before-publish.out" 2>"$work/killed-before-publish.err" &
killed_before_publish_pid=$!
for _ in {1..100}; do
	[[ -s $preview_publish_ready ]] && break
	sleep 0.01
done
[[ -s $preview_publish_ready ]]
killed_before_publish_meta=$state_home/dwm-titus/appearance/wallpaper/killed-before-publish.meta
killed_before_publish_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$killed_before_publish_meta")
process_running "$killed_before_publish_watchdog"
kill -KILL -- "-$killed_before_publish_pid" 2>/dev/null || true
wait "$killed_before_publish_pid" 2>/dev/null || true
unset DWM_TEST_MV_MODE DWM_TEST_PREVIEW_CURRENT DWM_TEST_PREVIEW_READY
run_helper status >/dev/null
for _ in {1..80}; do
	process_running "$killed_before_publish_watchdog" || break
	sleep 0.05
done
if process_running "$killed_before_publish_watchdog"; then
	printf 'Unpublished wallpaper preview watchdog survived reconciliation\n' >&2
	exit 1
fi
test ! -e "$killed_before_publish_meta"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test ! -e "$preview_current"

rm -f -- "$bin_dir/mv"
unset DWM_TEST_REAL_MV DWM_TEST_CONFIG_FILE DWM_TEST_EXTERNAL_PATH
unset DWM_TEST_LATE_EXTERNAL_PATH DWM_TEST_EXCHANGE_COUNT

# If the persisted config changes after Feh applies a candidate and the live
# rollback also fails, expose durable recovery state until a later retry works.
missing_recovery_path=$work/missing-recovery.jpg
export DWM_TEST_FEH_MUTATE_CONFIG=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_FEH_MUTATE_SELECTION_PATH=$second
export DWM_TEST_FEH_MUTATE_PATH=$missing_recovery_path
export DWM_TEST_FEH_FAIL_PATH=$wallpaper_dir
if run_helper apply "$second" max >"$work/live-recovery.out" 2>"$work/live-recovery.err"; then
	printf 'Wallpaper apply hid a failed compensating live rollback\n' >&2
	exit 1
fi
test -f "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
test -f "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"
recovery_status=$(run_helper status)
grep -Fqx $'mutation\trestricted\tWallpaper live rollback failed; retry session recovery before previewing' \
	<<<"$recovery_status"
if run_helper_display :916 apply "$first" fill \
	>"$work/pending-recovery-apply.out" 2>"$work/pending-recovery-apply.err"; then
	printf 'Wallpaper apply cleared another display rollback failure\n' >&2
	exit 1
fi
grep -Fq 'wallpaper live rollback recovery is pending' "$work/pending-recovery-apply.err"
test -f "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
test -f "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"
if run_helper preview recovery-blocked 20 "$first" fill >/dev/null 2>&1; then
	printf 'Wallpaper preview started with failed live rollback recovery pending\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_MUTATE_CONFIG DWM_TEST_FEH_MUTATE_SELECTION_PATH
unset DWM_TEST_FEH_MUTATE_PATH DWM_TEST_FEH_FAIL_PATH
: >"$log"
run_helper_display :916 session-apply
grep -Fqx 'display=:915' "$log"
grep -Fqx 'display=:916' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"

# A SIGKILL can leave the durable owner record before cleanup has a chance to
# write mutation.failed. Treat that owner alone as pending recovery, converge
# its recorded display first, and only then apply the current session display.
cat >"$state_home/dwm-titus/appearance/wallpaper/mutation.owner" <<'EOF'
version=1
token=mutation
display=:915
xauthority=
EOF
chmod 600 "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"
orphan_owner_status=$(run_helper_display :916 status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper mutation was interrupted; live recovery is pending' \
	<<<"$orphan_owner_status"
: >"$log"
run_helper_display :916 session-apply
grep -Fqx 'display=:915' "$log"
grep -Fqx 'display=:916' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"

# If the owning X server disappeared during logout, retry with the new
# session's display credentials instead of keeping the stale owner forever.
cat >"$state_home/dwm-titus/appearance/wallpaper/mutation.owner" <<'EOF'
version=1
token=mutation
display=:915
xauthority=
EOF
chmod 600 "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" != :915 ]
EOF
chmod +x "$bin_dir/xprop"
export DWM_TEST_FEH_FAIL_DISPLAY=:915
: >"$log"
run_helper_display :916 session-apply
unset DWM_TEST_FEH_FAIL_DISPLAY
rm -f -- "$bin_dir/xprop"
grep -Fqx 'display=:915' "$log"
grep -Fqx 'display=:916' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.owner"

run_helper apply "$first" tile >/dev/null

# A config edit during default convergence must replace the exact rollback
# baseline. A later candidate failure restores the newly selected image, not
# the stale random default applied by the first convergence attempt.
printf 'version=1\nmode=default\n' >"$config_home/dwm-titus/wallpaper.conf"
export DWM_TEST_DEFAULT_CANDIDATE=$first
export DWM_TEST_FEH_MUTATE_CONFIG=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_FEH_MUTATE_SELECTION_PATH=$first
export DWM_TEST_FEH_MUTATE_PATH=$second
export DWM_TEST_FEH_FAIL_PATH=$work/concurrent-baseline-failure.jpg
printf 'failed candidate\n' >"$DWM_TEST_FEH_FAIL_PATH"
: >"$log"
if run_helper apply "$DWM_TEST_FEH_FAIL_PATH" fill \
	>"$work/concurrent-baseline.out" 2>"$work/concurrent-baseline.err"; then
	printf 'Wallpaper apply accepted a failing candidate after concurrent baseline convergence\n' >&2
	exit 1
fi
unset DWM_TEST_DEFAULT_CANDIDATE DWM_TEST_FEH_MUTATE_CONFIG
unset DWM_TEST_FEH_MUTATE_SELECTION_PATH DWM_TEST_FEH_MUTATE_PATH DWM_TEST_FEH_FAIL_PATH
grep -Fqx "path=$second" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"
test "$(grep -Fxc "arg=$first" "$log")" -eq 1
test "$(grep -Fxc "arg=$second" "$log")" -eq 2
run_helper apply "$first" tile >/dev/null

: >"$log"
export DWM_TEST_FEH_MUTATE_CONFIG=$config_home/dwm-titus/wallpaper.conf
export DWM_TEST_FEH_MUTATE_SELECTION_PATH=$second
export DWM_TEST_FEH_MUTATE_PATH=$first
if run_helper apply "$second" max >"$work/live-convergence.out" 2>"$work/live-convergence.err"; then
	printf 'Wallpaper apply accepted a concurrent configuration change\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_MUTATE_CONFIG DWM_TEST_FEH_MUTATE_SELECTION_PATH
unset DWM_TEST_FEH_MUTATE_PATH
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=max' "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "arg=$first" "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
run_helper apply "$first" tile >/dev/null

exchange_cache=$runtime/dwm-settings-wallpaper/exchange-support
rm -f -- "$exchange_cache"
cache_alias_target=$work/exchange-cache-alias-target
printf 'preserve cache alias target\n' >"$cache_alias_target"
ln -s "$cache_alias_target" "$exchange_cache"
run_helper mutation-ready
grep -Fqx 'preserve cache alias target' "$cache_alias_target"
test -f "$exchange_cache"
test ! -L "$exchange_cache"
test "$(stat -c %h "$exchange_cache")" = 1
rm -f -- "$exchange_cache"
ln "$cache_alias_target" "$exchange_cache"
run_helper mutation-ready
grep -Fqx 'preserve cache alias target' "$cache_alias_target"
test "$(stat -c %h "$cache_alias_target")" = 1
test "$(stat -c %h "$exchange_cache")" = 1

mutation_lock=$runtime/dwm-settings-wallpaper/mutation.lock
rm -f -- "$mutation_lock"
lock_alias_target=$work/mutation-lock-alias-target
printf 'preserve lock alias target\n' >"$lock_alias_target"
ln "$lock_alias_target" "$mutation_lock"
if run_helper status >"$work/unsafe-lock.out" 2>"$work/unsafe-lock.err"; then
	printf 'Hard-linked wallpaper mutation lock was accepted\n' >&2
	exit 1
fi
grep -Fqx 'preserve lock alias target' "$lock_alias_target"
grep -Fq 'unsafe wallpaper mutation lock' "$work/unsafe-lock.err"
rm -f -- "$mutation_lock"
rm -f -- "$exchange_cache"

real_mv=$(command -v mv)
# Recreate the move fault injector only for the exchange capability probe.
cat >"$bin_dir/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
arguments=("$@")
source_path=${arguments[${#arguments[@]}-2]}
if [[ ${DWM_TEST_MV_MODE:-} == fail-exchange && $source_path == *.wallpaper-exchange-a.* ]]; then
	exit 1
fi
exec "$DWM_TEST_REAL_MV" "$@"
EOF
chmod +x "$bin_dir/mv"
export DWM_TEST_REAL_MV=$real_mv DWM_TEST_MV_MODE=fail-exchange
if run_helper mutation-ready; then
	printf 'Wallpaper mutation was advertised without atomic exchange support\n' >&2
	exit 1
fi
restricted_status=$(run_helper status)
grep -Fqx $'mutation\trestricted\tWallpaper changes are unavailable in this session' \
	<<<"$restricted_status"
unset DWM_TEST_MV_MODE DWM_TEST_REAL_MV
rm -f -- "$bin_dir/mv" "$exchange_cache"

# Interrupting Feh must terminate its process group, remove staged state, and
# restore the persisted wallpaper instead of leaking the in-flight selection.
interrupted_feh_pid_file=$work/interrupted-feh.pid
export DWM_TEST_FEH_BLOCK=1 DWM_TEST_FEH_BLOCK_PATH=$second DWM_TEST_FEH_IGNORE_TERM=1
export DWM_TEST_FEH_PID_FILE=$interrupted_feh_pid_file
DISPLAY=:915 HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_FEH_LOG=$log PATH="$bin_dir:$PATH" \
	"$helper" apply "$second" max >"$work/interrupted.out" 2>"$work/interrupted.err" &
interrupted_helper_pid=$!
for _ in {1..100}; do
	[[ -s $interrupted_feh_pid_file ]] && break
	sleep 0.01
done
[[ -s $interrupted_feh_pid_file ]]
interrupted_feh_pid=$(cat "$interrupted_feh_pid_file")
kill -TERM "$interrupted_helper_pid"
if wait "$interrupted_helper_pid"; then
	printf 'Interrupted wallpaper apply unexpectedly succeeded\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_BLOCK DWM_TEST_FEH_BLOCK_PATH DWM_TEST_FEH_PID_FILE DWM_TEST_FEH_IGNORE_TERM
for _ in {1..40}; do
	process_running "$interrupted_feh_pid" || break
	sleep 0.025
done
if process_running "$interrupted_feh_pid"; then
	printf 'Interrupted wallpaper apply left Feh running\n' >&2
	exit 1
fi
if compgen -G "$config_home/dwm-titus/wallpaper.conf.staged.*" >/dev/null; then
	printf 'Interrupted wallpaper apply left staged configuration\n' >&2
	exit 1
fi
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"

# Once Feh has changed the root window, interruption must keep rollback armed
# until the corresponding configuration has been published.
real_sha256sum=$(command -v sha256sum)
post_feh_hash_count=$work/post-feh-hash.count
post_feh_hash_ready=$work/post-feh-hash.ready
cat >"$bin_dir/sha256sum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[[ ! -f $DWM_TEST_HASH_COUNT ]] || count=$(<"$DWM_TEST_HASH_COUNT")
((count += 1))
printf '%s\n' "$count" >"$DWM_TEST_HASH_COUNT"
if ((count == 5)); then
	printf 'ready\n' >"$DWM_TEST_HASH_READY"
	sleep 5
fi
exec "$DWM_TEST_REAL_SHA256SUM" "$@"
EOF
chmod +x "$bin_dir/sha256sum"
: >"$log"
DISPLAY=:915 HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_FEH_LOG=$log DWM_TEST_HASH_COUNT=$post_feh_hash_count \
	DWM_TEST_HASH_READY=$post_feh_hash_ready DWM_TEST_REAL_SHA256SUM=$real_sha256sum \
	PATH="$bin_dir:$PATH" "$helper" apply "$second" max \
	>"$work/post-feh-interrupted.out" 2>"$work/post-feh-interrupted.err" &
post_feh_helper_pid=$!
for _ in {1..100}; do
	[[ -s $post_feh_hash_ready ]] && break
	sleep 0.01
done
[[ -s $post_feh_hash_ready ]]
kill -TERM "$post_feh_helper_pid"
if wait "$post_feh_helper_pid"; then
	printf 'Post-Feh interrupted wallpaper apply unexpectedly succeeded\n' >&2
	exit 1
fi
rm -f -- "$bin_dir/sha256sum"
grep -Fqx "path=$first" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'fit=tile' "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx "arg=$second" "$log"
grep -Fqx "arg=$first" "$log"
grep -Fqx 'arg=--bg-tile' "$log"
if compgen -G "$config_home/dwm-titus/wallpaper.conf.staged.*" >/dev/null; then
	printf 'Post-Feh interrupted wallpaper apply left staged configuration\n' >&2
	exit 1
fi

run_helper_display :915 preview display-owned 20 "$second" center >/dev/null
display_preview_meta=$state_home/dwm-titus/appearance/wallpaper/display-owned.meta
display_watchdog_pid=$(awk -F= '$1 == "pid" { print $2 }' "$display_preview_meta")
run_helper_display :916 session-apply
kill -0 "$display_watchdog_pid"
test -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
other_display_status=$(run_helper_display :916 status)
grep -Fqx $'mutation\trestricted\tAnother X11 session owns the active wallpaper preview' \
	<<<"$other_display_status"
grep -Fqx $'preview\tnone\t\t0\t\tfill\tAnother X11 session owns the active wallpaper preview' \
	<<<"$other_display_status"
owner_display_status=$(run_helper_display :915.0 status)
grep -Fq $'preview\tactive\tdisplay-owned\t' <<<"$owner_display_status"
if run_helper_display :916 revert display-owned >/dev/null 2>"$work/cross-display-revert.err"; then
	printf 'Another X11 session reverted an owned wallpaper preview\n' >&2
	exit 1
fi
grep -Fq 'belongs to another X11 session' "$work/cross-display-revert.err"
run_helper_display :915.0 revert display-owned >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"

run_helper_display :915 preview foreign-rearm 20 "$second" center >/dev/null
foreign_rearm_meta=$state_home/dwm-titus/appearance/wallpaper/foreign-rearm.meta
foreign_rearm_old_pid=$(awk -F= '$1 == "pid" { print $2 }' "$foreign_rearm_meta")
kill -TERM "$foreign_rearm_old_pid"
for _ in {1..40}; do
	process_running "$foreign_rearm_old_pid" || break
	sleep 0.025
done
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" = :915 ]
EOF
chmod +x "$bin_dir/xprop"
run_helper_display :916 session-apply
test -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
foreign_rearm_new_pid=$(awk -F= '$1 == "pid" { print $2 }' "$foreign_rearm_meta")
test "$foreign_rearm_new_pid" != "$foreign_rearm_old_pid"
kill -0 "$foreign_rearm_new_pid"
run_helper_display :915 revert foreign-rearm >/dev/null
rm -f -- "$bin_dir/xprop"

# Persisted metadata can outlive a boot, so a reused PID and start time must not
# authorize signaling a process that is not this preview's watchdog.
run_helper_display :915 preview reused-watchdog-pid 20 "$second" center >/dev/null
reused_meta=$state_home/dwm-titus/appearance/wallpaper/reused-watchdog-pid.meta
real_reused_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$reused_meta")
kill -TERM "$real_reused_watchdog"
for _ in {1..40}; do
	process_running "$real_reused_watchdog" || break
	sleep 0.025
done
sleep 20 &
unrelated_pid=$!
unrelated_start=$(sed 's/^.*) //' "/proc/$unrelated_pid/stat" | awk '{ print $20 }')
sed -i -e "s/^pid=.*/pid=$unrelated_pid/" -e "s/^pid_start=.*/pid_start=$unrelated_start/" \
	"$reused_meta"
run_helper_display :915 revert reused-watchdog-pid >/dev/null
if ! kill -0 "$unrelated_pid" 2>/dev/null; then
	printf 'Wallpaper preview cleanup signaled a reused unrelated PID\n' >&2
	exit 1
fi
kill -TERM "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true

run_helper_display :915 preview stale-display 20 "$second" center >/dev/null
stale_display_meta=$state_home/dwm-titus/appearance/wallpaper/stale-display.meta
stale_display_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$stale_display_meta")
kill -TERM "$stale_display_watchdog"
for _ in {1..40}; do
	process_running "$stale_display_watchdog" || break
	sleep 0.025
done
run_helper_display :916 session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
run_helper_display :916 apply "$first" tile >/dev/null

# A transient owner-display rollback failure must not leave a failed preview
# wedged after session recovery has restored the configured wallpaper.
run_helper_display :915 preview transient-session-recovery 20 "$second" center >/dev/null
transient_failure_count=$work/transient-failure.count
printf '2\n' >"$transient_failure_count"
export DWM_TEST_FEH_FAIL_COUNT_FILE=$transient_failure_count
run_helper_display :915 session-apply
unset DWM_TEST_FEH_FAIL_COUNT_FILE
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/transient-session-recovery.meta"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/transient-session-recovery.failed"
run_helper_display :915 apply "$first" tile >/dev/null

# Active preview deadlines use monotonic uptime, so a backward wall-clock
# adjustment cannot extend a rearmed watchdog.
cat >"$bin_dir/date" <<'EOF'
#!/bin/sh
cat "$DWM_TEST_DATE_FILE"
EOF
chmod +x "$bin_dir/date"
fake_wall_clock=$work/fake-wall-clock
fake_boot_id=$work/fake-boot-id
fake_monotonic=$work/fake-monotonic
printf '1000\n' >"$fake_wall_clock"
printf '11111111-1111-1111-1111-111111111111\n' >"$fake_boot_id"
printf '1000.00 0.00\n' >"$fake_monotonic"
export DWM_TEST_DATE_FILE=$fake_wall_clock
export DWM_TEST_WALLPAPER_BOOT_ID_FILE=$fake_boot_id
export DWM_TEST_WALLPAPER_MONOTONIC_FILE=$fake_monotonic
run_helper_display :915 preview backward-clock 20 "$second" center >/dev/null
backward_clock_meta=$state_home/dwm-titus/appearance/wallpaper/backward-clock.meta
grep -Fqx 'deadline=1020000' "$backward_clock_meta"
backward_clock_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$backward_clock_meta")
kill -TERM "$backward_clock_watchdog"
for _ in {1..40}; do
	process_running "$backward_clock_watchdog" || break
	sleep 0.025
done
printf '500\n' >"$fake_wall_clock"
printf '1010.00 0.00\n' >"$fake_monotonic"
backward_clock_status=$(run_helper_display :915 status)
backward_clock_remaining=$(awk -F '\t' '$1 == "preview" { print $4 }' <<<"$backward_clock_status")
test "$backward_clock_remaining" -eq 10
grep -Fqx 'deadline=1020000' "$backward_clock_meta"
run_helper_display :915 revert backward-clock >/dev/null

# Fractional monotonic uptime must not truncate a one-second preview to the
# next whole-second boundary.
printf '100.990 0.00\n' >"$fake_monotonic"
run_helper_display :915 preview fractional-deadline 1 "$second" center >/dev/null
fractional_deadline_meta=$state_home/dwm-titus/appearance/wallpaper/fractional-deadline.meta
grep -Fqx 'deadline=101990' "$fractional_deadline_meta"
run_helper_display :915 revert fractional-deadline >/dev/null

# A suspended session advances monotonic uptime while a relative sleep is
# paused. The watchdog rechecks the deadline within one second after resume.
printf '1100.00 0.00\n' >"$fake_monotonic"
run_helper_display :915 preview resume-deadline 20 "$second" center >/dev/null
resume_deadline_meta=$state_home/dwm-titus/appearance/wallpaper/resume-deadline.meta
grep -Fqx 'deadline=1120000' "$resume_deadline_meta"
: >"$log"
printf '1130.00 0.00\n' >"$fake_monotonic"
for _ in {1..60}; do
	[[ ! -e $state_home/dwm-titus/appearance/wallpaper/preview.current ]] && break
	sleep 0.05
done
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$resume_deadline_meta"
grep -Fqx "arg=$first" "$log"

# Persisted state from another boot is stale because its watchdog cannot have
# survived. Restore immediately instead of comparing unrelated uptime values.
printf '2000.00 0.00\n' >"$fake_monotonic"
run_helper_display :915 preview stale-boot 20 "$second" center >/dev/null
stale_boot_meta=$state_home/dwm-titus/appearance/wallpaper/stale-boot.meta
stale_boot_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$stale_boot_meta")
kill -TERM "$stale_boot_watchdog"
for _ in {1..40}; do
	process_running "$stale_boot_watchdog" || break
	sleep 0.025
done
printf '22222222-2222-2222-2222-222222222222\n' >"$fake_boot_id"
printf '5.00 0.00\n' >"$fake_monotonic"
: >"$log"
run_helper_display :915 status >/dev/null
grep -Fqx "arg=$first" "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$stale_boot_meta"

unset DWM_TEST_DATE_FILE DWM_TEST_WALLPAPER_BOOT_ID_FILE DWM_TEST_WALLPAPER_MONOTONIC_FILE
rm -f -- "$bin_dir/date"

run_helper_display :915 preview failed-display 20 "$second" center >/dev/null
failed_display_meta=$state_home/dwm-titus/appearance/wallpaper/failed-display.meta
failed_display_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$failed_display_meta")
kill -TERM "$failed_display_watchdog"
for _ in {1..40}; do
	process_running "$failed_display_watchdog" || break
	sleep 0.025
done
printf '%s\n' 'Owner display rollback failed' \
	>"$state_home/dwm-titus/appearance/wallpaper/failed-display.failed"
: >"$log"
run_helper_display :916 session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
grep -Fqx 'display=:915' "$log"
grep -Fqx 'display=:916' "$log"

run_helper_display :915 preview reused-display-failure 20 "$second" center >/dev/null
reused_display_meta=$state_home/dwm-titus/appearance/wallpaper/reused-display-failure.meta
reused_display_watchdog=$(awk -F= '$1 == "pid" { print $2 }' "$reused_display_meta")
kill -TERM "$reused_display_watchdog"
for _ in {1..40}; do
	process_running "$reused_display_watchdog" || break
	sleep 0.025
done
printf '%s\n' 'Previous session rollback failed' \
	>"$state_home/dwm-titus/appearance/wallpaper/reused-display-failure.failed"
run_helper_display :915 session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"

# A valid configured selection avoids scanning the legacy default directory.
cat >"$bin_dir/find" <<'EOF'
#!/bin/sh
printf 'unexpected scan\n' >>"$DWM_TEST_FIND_LOG"
exit 99
EOF
chmod +x "$bin_dir/find"
find_log=$work/find.log
DISPLAY=:915 HOME=$home XDG_CONFIG_HOME=$config_home XDG_STATE_HOME=$state_home \
	XDG_RUNTIME_DIR=$runtime DWM_APPEARANCE_WALLPAPER_DIR=$wallpaper_dir \
	DWM_TEST_FEH_LOG=$log DWM_TEST_FIND_LOG=$find_log PATH="$bin_dir:$PATH" \
	"$helper" status >/dev/null
test ! -e "$find_log"

export DWM_TEST_FEH_FAIL_ALL=1
if run_helper session-apply >"$work/session-failure.out" 2>"$work/session-failure.err"; then
	printf 'Wallpaper session apply hid a Feh failure\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_FAIL_ALL
run_helper session-apply

export DWM_WALLPAPER_FEH_TIMEOUT=1 DWM_TEST_FEH_BLOCK=1 DWM_TEST_FEH_BLOCK_PATH=$second
read -r started_uptime _ </proc/uptime
if run_helper preview bounded-feh 5 "$second" fill >"$work/bounded.out" 2>"$work/bounded.err"; then
	printf 'Blocking Feh unexpectedly completed a wallpaper preview\n' >&2
	exit 1
fi
read -r finished_uptime _ </proc/uptime
unset DWM_WALLPAPER_FEH_TIMEOUT DWM_TEST_FEH_BLOCK DWM_TEST_FEH_BLOCK_PATH
awk -v started="$started_uptime" -v finished="$finished_uptime" \
	'BEGIN { exit ! (finished - started < 4.5) }'
grep -Fq 'wallpaper preview could not be applied' "$work/bounded.err"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/bounded-feh.failed"
bounded_status=$(run_helper status --read-only)
grep -Fqx $'preview\tnone\t\t0\t\tfill\tNo wallpaper preview is active' <<<"$bounded_status"

# A failed watchdog metadata update must stop the watchdog and refuse to apply
# the preview instead of claiming that automatic rollback is armed.
real_chmod=$(command -v chmod)
cat >"$bin_dir/chmod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
last=${!#}
if [[ $last == */.preview-meta.* ]]; then
	count=0
	[[ ! -f $DWM_TEST_CHMOD_COUNT ]] || read -r count <"$DWM_TEST_CHMOD_COUNT"
	count=$((count + 1))
	printf '%s\n' "$count" >"$DWM_TEST_CHMOD_COUNT"
	if ((count == DWM_TEST_CHMOD_FAIL_AT)); then
		: >"$last"
		exit 1
	fi
fi
exec "$DWM_TEST_REAL_CHMOD" "$@"
EOF
"$real_chmod" +x "$bin_dir/chmod"
export DWM_TEST_CHMOD_COUNT=$work/chmod.count DWM_TEST_REAL_CHMOD=$real_chmod
export DWM_TEST_CHMOD_FAIL_AT=2
: >"$log"
if run_helper preview metadata-write-failure 20 "$second" fill \
	>"$work/metadata-write.out" 2>"$work/metadata-write.err"; then
	printf 'Wallpaper preview accepted a failed watchdog metadata update\n' >&2
	exit 1
fi
grep -Fq 'wallpaper preview rollback could not be armed' "$work/metadata-write.err"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/metadata-write-failure.meta"
if grep -Fqx "arg=$second" "$log"; then
	printf 'Wallpaper candidate was applied without durable watchdog metadata\n' >&2
	exit 1
fi

# Keep and revert must also contain a failed deadline repair instead of exiting
# silently under set -e and leaving an apparently active unbounded preview.
rm -f -- "$DWM_TEST_CHMOD_COUNT"
export DWM_TEST_CHMOD_FAIL_AT=999
run_helper preview finish-clamp-failure 20 "$second" fill >/dev/null
finish_clamp_meta=$state_home/dwm-titus/appearance/wallpaper/finish-clamp-failure.meta
finish_clamp_deadline=$(awk -F= '$1 == "deadline" { print $2 }' "$finish_clamp_meta")
sed -i "s/^deadline=.*/deadline=$((finish_clamp_deadline + 1000000000))/" "$finish_clamp_meta"
rm -f -- "$DWM_TEST_CHMOD_COUNT"
export DWM_TEST_CHMOD_FAIL_AT=1
if run_helper keep finish-clamp-failure \
	>"$work/finish-clamp.out" 2>"$work/finish-clamp.err"; then
	printf 'Wallpaper keep accepted a failed deadline repair\n' >&2
	exit 1
fi
grep -Fq 'wallpaper preview deadline could not be repaired' "$work/finish-clamp.err"
finish_clamp_status=$(run_helper status --read-only)
grep -Fqx $'preview\tfailed\tfinish-clamp-failure\t0\t'"$second"$'\tfill\tWallpaper preview deadline could not be repaired' \
	<<<"$finish_clamp_status"
export DWM_TEST_CHMOD_FAIL_AT=999
run_helper abandon finish-clamp-failure >/dev/null

# Status remains available when deadline repair cannot rewrite preview metadata.
rm -f -- "$DWM_TEST_CHMOD_COUNT"
export DWM_TEST_CHMOD_FAIL_AT=999
run_helper preview reconcile-clamp-failure 20 "$second" fill >/dev/null
clamp_meta=$state_home/dwm-titus/appearance/wallpaper/reconcile-clamp-failure.meta
clamp_deadline=$(awk -F= '$1 == "deadline" { print $2 }' "$clamp_meta")
sed -i "s/^deadline=.*/deadline=$((clamp_deadline + 1000000000))/" "$clamp_meta"
rm -f -- "$DWM_TEST_CHMOD_COUNT"
export DWM_TEST_CHMOD_FAIL_AT=1
reconcile_status=$(run_helper status)
grep -Fqx $'wallpaper-protocol\t1\t0' <<<"$reconcile_status"
grep -Fqx $'preview\tfailed\treconcile-clamp-failure\t0\t'"$second"$'\tfill\tWallpaper preview deadline could not be repaired' \
	<<<"$reconcile_status"
export DWM_TEST_CHMOD_FAIL_AT=999
run_helper abandon reconcile-clamp-failure >/dev/null

# Status also remains available when a dead watchdog cannot persist its rearm.
rm -f -- "$DWM_TEST_CHMOD_COUNT"
run_helper preview reconcile-rearm-failure 20 "$second" fill >/dev/null
rearm_failure_meta=$state_home/dwm-titus/appearance/wallpaper/reconcile-rearm-failure.meta
rearm_failure_pid=$(awk -F= '$1 == "pid" { print $2 }' "$rearm_failure_meta")
kill -TERM "$rearm_failure_pid"
for _ in {1..40}; do
	process_running "$rearm_failure_pid" || break
	sleep 0.025
done
sed -i "s/^pid=.*/pid=$$/; s/^pid_start=.*/pid_start=1/" "$rearm_failure_meta"
rm -f -- "$DWM_TEST_CHMOD_COUNT"
export DWM_TEST_CHMOD_FAIL_AT=1
reconcile_status=$(run_helper status)
grep -Fqx $'wallpaper-protocol\t1\t0' <<<"$reconcile_status"
grep -Fqx $'preview\tfailed\treconcile-rearm-failure\t0\t'"$second"$'\tfill\tAutomatic wallpaper rollback could not be rearmed' \
	<<<"$reconcile_status"
unset DWM_TEST_CHMOD_COUNT DWM_TEST_REAL_CHMOD DWM_TEST_CHMOD_FAIL_AT
rm -f -- "$bin_dir/chmod"
run_helper abandon reconcile-rearm-failure >/dev/null

# A staging failure before the temporary metadata file exists must still stop
# the replacement watchdog and leave status available for explicit recovery.
real_mktemp=$(command -v mktemp)
cat >"$bin_dir/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
last=${!#}
if [[ $last == */.preview-meta.* ]]; then
	count=0
	[[ ! -f $DWM_TEST_MKTEMP_COUNT ]] || read -r count <"$DWM_TEST_MKTEMP_COUNT"
	count=$((count + 1))
	printf '%s\n' "$count" >"$DWM_TEST_MKTEMP_COUNT"
	if ((count == DWM_TEST_MKTEMP_FAIL_AT)); then
		exit 1
	fi
fi
exec "$DWM_TEST_REAL_MKTEMP" "$@"
EOF
chmod +x "$bin_dir/mktemp"
export DWM_TEST_MKTEMP_COUNT=$work/mktemp.count DWM_TEST_REAL_MKTEMP=$real_mktemp
export DWM_TEST_MKTEMP_FAIL_AT=999
run_helper preview rearm-mktemp-failure 20 "$second" fill >/dev/null
mktemp_failure_meta=$state_home/dwm-titus/appearance/wallpaper/rearm-mktemp-failure.meta
mktemp_failure_pid=$(awk -F= '$1 == "pid" { print $2 }' "$mktemp_failure_meta")
kill -TERM "$mktemp_failure_pid"
for _ in {1..40}; do
	process_running "$mktemp_failure_pid" || break
	sleep 0.025
done
rm -f -- "$DWM_TEST_MKTEMP_COUNT"
export DWM_TEST_MKTEMP_FAIL_AT=1
mktemp_failure_status=$(run_helper status)
grep -Fqx $'wallpaper-protocol\t1\t0' <<<"$mktemp_failure_status"
grep -Fqx $'preview\tfailed\trearm-mktemp-failure\t0\t'"$second"$'\tfill\tAutomatic wallpaper rollback could not be rearmed' \
	<<<"$mktemp_failure_status"
if pgrep -f -- "$helper preview-watchdog rearm-mktemp-failure" >/dev/null; then
	printf 'Wallpaper metadata staging failure leaked a replacement watchdog\n' >&2
	exit 1
fi
unset DWM_TEST_MKTEMP_COUNT DWM_TEST_REAL_MKTEMP DWM_TEST_MKTEMP_FAIL_AT
rm -f -- "$bin_dir/mktemp"
run_helper abandon rearm-mktemp-failure >/dev/null

# Persisted decimal fields are canonical. A leading zero is invalid state, not
# a Bash arithmetic expression that can abort status reconciliation.
run_helper preview noncanonical-deadline 20 "$second" fill >/dev/null
noncanonical_meta=$state_home/dwm-titus/appearance/wallpaper/noncanonical-deadline.meta
noncanonical_pid=$(awk -F= '$1 == "pid" { print $2 }' "$noncanonical_meta")
kill -TERM "$noncanonical_pid"
for _ in {1..40}; do
	process_running "$noncanonical_pid" || break
	sleep 0.025
done
sed -i 's/^deadline=.*/deadline=08/' "$noncanonical_meta"
if ! noncanonical_status=$(run_helper status 2>"$work/noncanonical-deadline.err"); then
	printf 'Wallpaper status aborted on a noncanonical decimal deadline\n' >&2
	exit 1
fi
test ! -s "$work/noncanonical-deadline.err"
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$noncanonical_status"
grep -Fqx $'preview\tfailed\tnoncanonical-deadline\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$noncanonical_status"
run_helper abandon noncanonical-deadline >/dev/null

# Invalid or missing active-preview metadata keeps explicit recovery state until
# the configured wallpaper is successfully restored by an abandon action.
run_helper preview corrupt-active-meta 20 "$second" fill >/dev/null
corrupt_active_meta=$state_home/dwm-titus/appearance/wallpaper/corrupt-active-meta.meta
corrupt_active_pid=$(awk -F= '$1 == "pid" { print $2 }' "$corrupt_active_meta")
kill -TERM "$corrupt_active_pid"
for _ in {1..40}; do
	process_running "$corrupt_active_pid" || break
	sleep 0.025
done
printf 'invalid\n' >"$corrupt_active_meta"
invalid_status=$(run_helper status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$invalid_status"
grep -Fqx $'preview\tfailed\tcorrupt-active-meta\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$invalid_status"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
invalid_status=$(run_helper status)
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$invalid_status"
grep -Fqx $'preview\tfailed\tcorrupt-active-meta\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$invalid_status"
test -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
: >"$log"
run_helper_display :916 abandon corrupt-active-meta >/dev/null
grep -Fqx 'display=:915' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"

# A malformed current-token marker is recovered with the independent owner
# credentials rather than wedging every future preview.
run_helper_display :915 preview corrupt-current-owner 20 "$second" fill >/dev/null
corrupt_owner_meta=$state_home/dwm-titus/appearance/wallpaper/corrupt-current-owner.meta
corrupt_owner_pid=$(awk -F= '$1 == "pid" { print $2 }' "$corrupt_owner_meta")
kill -TERM "$corrupt_owner_pid"
for _ in {1..40}; do
	process_running "$corrupt_owner_pid" || break
	sleep 0.025
done
: >"$state_home/dwm-titus/appearance/wallpaper/preview.current"
: >"$log"
malformed_read_only=$(run_helper_display :916 status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$malformed_read_only"
grep -Fqx $'preview\tfailed\tcorrupt-current-owner\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$malformed_read_only"
run_helper_display :916 status >/dev/null
grep -Fqx 'display=:915' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
run_helper_display :916 preview after-corrupt-owner 20 "$second" fill >/dev/null
run_helper_display :916 revert after-corrupt-owner >/dev/null

# A syntactically valid current token that differs from the independent owner
# token is also orphaned state. Recover through the owner instead of preserving
# a marker that neither token can abandon.
run_helper_display :915 preview mismatched-owner-token 20 "$second" fill >/dev/null
mismatched_owner_meta=$state_home/dwm-titus/appearance/wallpaper/mismatched-owner-token.meta
mismatched_owner_pid=$(awk -F= '$1 == "pid" { print $2 }' "$mismatched_owner_meta")
kill -TERM "$mismatched_owner_pid"
for _ in {1..40}; do
	process_running "$mismatched_owner_pid" || break
	sleep 0.025
done
printf '%s\n' valid-but-mismatched-token \
	>"$state_home/dwm-titus/appearance/wallpaper/preview.current"
: >"$log"
run_helper_display :916 status >/dev/null
grep -Fqx 'display=:915' "$log"
grep -Fqx "arg=$first" "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test ! -e "$mismatched_owner_meta"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
run_helper_display :916 preview after-mismatched-owner 20 "$second" fill >/dev/null
run_helper_display :916 revert after-mismatched-owner >/dev/null

# If the independent owner display is gone, recover malformed current-token
# state on the caller display and remove the stale records.
run_helper_display :915 preview corrupt-current-stale-owner 20 "$second" fill >/dev/null
stale_owner_meta=$state_home/dwm-titus/appearance/wallpaper/corrupt-current-stale-owner.meta
stale_owner_pid=$(awk -F= '$1 == "pid" { print $2 }' "$stale_owner_meta")
kill -TERM "$stale_owner_pid"
for _ in {1..40}; do
	process_running "$stale_owner_pid" || break
	sleep 0.025
done
: >"$state_home/dwm-titus/appearance/wallpaper/preview.current"
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" != :915 ]
EOF
chmod +x "$bin_dir/xprop"
export DWM_TEST_FEH_FAIL_DISPLAY=:915
: >"$log"
run_helper_display :916 status >/dev/null
unset DWM_TEST_FEH_FAIL_DISPLAY
rm -f -- "$bin_dir/xprop"
grep -Fqx 'display=:915' "$log"
grep -Fqx 'display=:916' "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
run_helper_display :916 preview after-stale-corrupt-owner 20 "$second" fill >/dev/null
run_helper_display :916 revert after-stale-corrupt-owner >/dev/null

# Losing preview.current after the candidate is live leaves the durable owner
# record as the only recovery anchor. Reconcile on that display before clearing
# the watchdog and metadata so the unconfirmed wallpaper cannot remain live.
run_helper_display :915 preview missing-current-after-apply 20 "$second" fill >/dev/null
missing_current_meta=$state_home/dwm-titus/appearance/wallpaper/missing-current-after-apply.meta
missing_current_pid=$(awk -F= '$1 == "pid" { print $2 }' "$missing_current_meta")
kill -TERM "$missing_current_pid"
for _ in {1..40}; do
	process_running "$missing_current_pid" || break
	sleep 0.025
done
rm -f -- "$state_home/dwm-titus/appearance/wallpaper/preview.current"
: >"$log"
owner_only_status=$(run_helper_display :916 status --read-only)
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$owner_only_status"
grep -Fqx $'preview\tfailed\tmissing-current-after-apply\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$owner_only_status"
test -f "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test -f "$missing_current_meta"
run_helper_display :916 status >/dev/null
grep -Fqx 'display=:915' "$log"
grep -Fqx "arg=$first" "$log"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test ! -e "$missing_current_meta"

# Selection-failure bookkeeping during orphan recovery must not replace the
# preview owner's display before reachability is checked. If that live owner
# cannot be restored, keep the preview recovery records instead of applying
# only on the caller display and discarding the recovery anchor.
run_helper_display :915 preview overlapping-owner-recovery 20 "$second" fill >/dev/null
overlapping_owner_meta=$state_home/dwm-titus/appearance/wallpaper/overlapping-owner-recovery.meta
overlapping_owner_pid=$(awk -F= '$1 == "pid" { print $2 }' "$overlapping_owner_meta")
kill -TERM "$overlapping_owner_pid"
for _ in {1..40}; do
	process_running "$overlapping_owner_pid" || break
	sleep 0.025
done
rm -f -- "$state_home/dwm-titus/appearance/wallpaper/preview.current"
selection_owner=$state_home/dwm-titus/appearance/wallpaper/selection.owner
selection_hash=$(sha256sum "$config_home/dwm-titus/wallpaper.conf" | awk '{ print $1 }')
cat >"$selection_owner" <<EOF
version=3
hash=$selection_hash
display=:915
xauthority=
EOF
chmod 600 "$selection_owner"
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" = :915 ]
EOF
chmod +x "$bin_dir/xprop"
export DWM_TEST_FEH_FAIL_DISPLAY=:915
: >"$log"
overlapping_owner_status=$(run_helper_display :916 status)
unset DWM_TEST_FEH_FAIL_DISPLAY
rm -f -- "$bin_dir/xprop"
grep -Fqx 'display=:915' "$log"
grep -Fqx $'mutation\trestricted\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$overlapping_owner_status"
test -f "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test -f "$overlapping_owner_meta"
test -f "$selection_owner"
run_helper_display :915 status >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.owner"
test ! -e "$overlapping_owner_meta"

# A configured selection failure belongs to the X11 display where Feh failed.
# A successful apply on another live display must not hide that degraded state.
printf -v long_selection_xauthority '/%04094d' 0
export XAUTHORITY=$long_selection_xauthority
export DWM_TEST_FEH_FAIL_DISPLAY=:915
if run_helper_display :915 session-apply >/dev/null 2>&1; then
	printf 'Wallpaper session apply hid a display-scoped selection failure\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_FAIL_DISPLAY
grep -Fqx 'display=:915' "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
export DWM_TEST_FEH_FAIL_DISPLAY=:916
if run_helper_display :916 session-apply >/dev/null 2>&1; then
	printf 'Wallpaper session apply hid a second display-scoped selection failure\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_FAIL_DISPLAY
test "$(grep -Fxc 'display=:915' "$state_home/dwm-titus/appearance/wallpaper/selection.owner")" -eq 1
test "$(grep -Fxc 'display=:916' "$state_home/dwm-titus/appearance/wallpaper/selection.owner")" -eq 1
test "$(stat -c %s "$state_home/dwm-titus/appearance/wallpaper/selection.owner")" -gt 8192
unset XAUTHORITY
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" = :915 ]
EOF
chmod +x "$bin_dir/xprop"
run_helper_display :916 session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test -f "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
test "$(grep -Fxc 'display=:915' "$state_home/dwm-titus/appearance/wallpaper/selection.owner")" -eq 1
test "$(grep -Fxc 'display=:916' "$state_home/dwm-titus/appearance/wallpaper/selection.owner")" -eq 0
run_helper_display :916 apply "$first" tile >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test -f "$state_home/dwm-titus/appearance/wallpaper/selection.owner"
cross_display_selection_status=$(run_helper_display :916 status --read-only)
grep -Fqx $'selection\tpartial\t'"$first"$'\ttile\tConfigured wallpaper could not be applied; the legacy random wallpaper fallback is required' \
	<<<"$cross_display_selection_status"
rm -f -- "$bin_dir/xprop"
run_helper_display :915 session-apply
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.owner"

# A partially recovered legacy multi-display record is migrated atomically to
# the self-contained format before its matching hash marker is retired.
selection_failure=$state_home/dwm-titus/appearance/wallpaper/selection.failed
selection_owner=$state_home/dwm-titus/appearance/wallpaper/selection.owner
sha256sum "$config_home/dwm-titus/wallpaper.conf" | awk '{ print $1 }' >"$selection_failure"
cat >"$selection_owner" <<'EOF'
version=2
display=:915
xauthority=
display=:916
xauthority=
EOF
chmod 600 "$selection_failure" "$selection_owner"
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" = :915 ]
EOF
chmod +x "$bin_dir/xprop"
run_helper_display :916 session-apply
grep -Fqx 'version=3' "$selection_owner"
grep -Fqx 'display=:915' "$selection_owner"
test "$(grep -Fxc 'display=:916' "$selection_owner")" -eq 0
test ! -e "$selection_failure"
rm -f -- "$bin_dir/xprop"
run_helper_display :915 session-apply
test ! -e "$selection_owner"

# A legacy failure marker without owner credentials remains unresolved because
# another display cannot prove which X server still needs recovery.
sha256sum "$config_home/dwm-titus/wallpaper.conf" | awk '{ print $1 }' >"$selection_failure"
chmod 600 "$selection_failure"
run_helper_display :916 session-apply
test -f "$selection_failure"
legacy_marker_status=$(run_helper_display :916 status --read-only)
grep -Fqx $'selection\tpartial\t'"$first"$'\ttile\tConfigured wallpaper could not be applied; the legacy random wallpaper fallback is required' \
	<<<"$legacy_marker_status"
rm -f -- "$selection_failure"

# A successful fresh session retires a failure owned by an X server that has
# exited, while the live cross-display case above remains protected.
export DWM_TEST_FEH_FAIL_DISPLAY=:915
if run_helper_display :915 session-apply >/dev/null 2>&1; then
	printf 'Wallpaper session apply hid a stale-display selection setup failure\n' >&2
	exit 1
fi
unset DWM_TEST_FEH_FAIL_DISPLAY
cat >"$bin_dir/xprop" <<'EOF'
#!/bin/sh
[ "${1:-}" = -display ] && [ "${2:-}" != :915 ]
EOF
chmod +x "$bin_dir/xprop"
run_helper_display :916 session-apply
rm -f -- "$bin_dir/xprop"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.failed"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/selection.owner"

# A failed direct apply from default mode restores the exact default selected
# during preflight instead of choosing a second random rollback image.
saved_selection_config=$work/saved-selection.conf
cp -- "$config_home/dwm-titus/wallpaper.conf" "$saved_selection_config"
rm -f -- "$config_home/dwm-titus/wallpaper.conf"
default_sequence=$work/default-sequence
printf '%s\n%s\n%s\n' "$first" "$first" "$second" >"$default_sequence"
failed_direct_selection=$work/failed-direct-selection.jpg
printf 'failed direct selection\n' >"$failed_direct_selection"
export DWM_TEST_DEFAULT_SEQUENCE_FILE=$default_sequence
export DWM_TEST_FEH_FAIL_PATH=$failed_direct_selection
: >"$log"
if run_helper apply "$failed_direct_selection" fill \
	>"$work/exact-direct-rollback.out" 2>"$work/exact-direct-rollback.err"; then
	printf 'Failing direct wallpaper selection unexpectedly succeeded\n' >&2
	exit 1
fi
unset DWM_TEST_DEFAULT_SEQUENCE_FILE DWM_TEST_FEH_FAIL_PATH
grep -Fq 'wallpaper could not be applied' "$work/exact-direct-rollback.err"
test "$(grep -Fxc "arg=$first" "$log")" -eq 2
test "$(grep -Fxc "arg=$second" "$log")" -eq 0
test ! -e "$config_home/dwm-titus/wallpaper.conf"
mv -- "$saved_selection_config" "$config_home/dwm-titus/wallpaper.conf"

run_helper preview missing-active-meta 20 "$second" fill >/dev/null
missing_active_meta=$state_home/dwm-titus/appearance/wallpaper/missing-active-meta.meta
missing_active_pid=$(awk -F= '$1 == "pid" { print $2 }' "$missing_active_meta")
kill -TERM "$missing_active_pid"
for _ in {1..40}; do
	process_running "$missing_active_pid" || break
	sleep 0.025
done
rm -f -- "$missing_active_meta"
invalid_status=$(run_helper status)
grep -Fqx $'preview\tfailed\tmissing-active-meta\t0\t\tfill\tWallpaper preview state is invalid; restore it explicitly before changing wallpaper' \
	<<<"$invalid_status"
test -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"
run_helper abandon missing-active-meta >/dev/null
test ! -e "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -e "$state_home/dwm-titus/appearance/wallpaper/mutation.failed"

# A malformed owner marker without recovery credentials must block direct
# mutations instead of being treated as an absent preview and left behind.
config_before_malformed_owner=$work/config-before-malformed-owner
cp -- "$config_home/dwm-titus/wallpaper.conf" "$config_before_malformed_owner"
printf 'not a valid token\n' >"$state_home/dwm-titus/appearance/wallpaper/preview.current"
: >"$log"
if run_helper apply "$second" fill \
	>"$work/malformed-owner-apply.out" 2>"$work/malformed-owner-apply.err"; then
	printf 'Wallpaper apply bypassed a malformed preview owner marker\n' >&2
	exit 1
fi
grep -Fq 'wallpaper preview owner state is invalid' "$work/malformed-owner-apply.err"
if run_helper reset \
	>"$work/malformed-owner-reset.out" 2>"$work/malformed-owner-reset.err"; then
	printf 'Wallpaper reset bypassed a malformed preview owner marker\n' >&2
	exit 1
fi
grep -Fq 'wallpaper preview owner state is invalid' "$work/malformed-owner-reset.err"
cmp -- "$config_before_malformed_owner" "$config_home/dwm-titus/wallpaper.conf"
grep -Fqx 'not a valid token' "$state_home/dwm-titus/appearance/wallpaper/preview.current"
test ! -s "$log"

printf 'Wallpaper settings helper: PASS\n'
