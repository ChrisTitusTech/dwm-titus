#!/usr/bin/env bash

set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
owns_work=false
if [[ -n ${DWM_TEST_WORKSPACE:-} ]]; then
	work=$DWM_TEST_WORKSPACE
else
	tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
	mkdir -p -- "$tmp_root" || {
		printf 'Could not create font test temporary root: %s\n' "$tmp_root" >&2
		exit 1
	}
	work=$(mktemp -d "$tmp_root/dwm-font-test.XXXXXX")
	owns_work=true
fi
trap 'if [[ $owns_work == true ]]; then rm -rf -- "$work"; fi' EXIT
trap 'status=$?; printf "dwm-settings-font test failed at line %s (status %s)\n" "$LINENO" "$status" >&2' ERR

fixture=$work/fixture
home=$fixture/home
config=$fixture/config
state=$fixture/state
bin=$fixture/bin
font_config=$config/dwm-titus/font.conf
mkdir -p "$home" "$config" "$state" "$bin"

process_is_live() {
	local pid=$1 process_stat process_state

	kill -0 "$pid" 2>/dev/null || return 1
	[[ -r /proc/$pid/stat ]] || return 1
	process_stat=$(<"/proc/$pid/stat")
	process_state=${process_stat#*) }
	process_state=${process_state%% *}
	[[ $process_state != Z ]]
}

for command in awk bash chmod cp date flock id mkdir mktemp mv setsid sha256sum sleep stat timeout unlink; do
	path=$(command -v "$command")
	ln -sfn "$path" "$bin/$command"
done
real_mv=$(command -v mv)

cat >"$work/mv-without-exchange-options" <<EOF
#!/bin/bash
set -eu
if [[ \${1:-} == --help ]]; then
	printf 'Usage: mv SOURCE DEST\n'
	exit 0
fi
exec "$real_mv" "\$@"
EOF
cat >"$work/mv-without-filesystem-exchange" <<EOF
#!/bin/bash
set -eu
if [[ \${1:-} == --help ]]; then
	exec "$real_mv" "\$@"
fi
for argument in "\$@"; do
	[[ \$argument == --exchange ]] && exit 1
done
exec "$real_mv" "\$@"
EOF
chmod +x "$work/mv-without-exchange-options" "$work/mv-without-filesystem-exchange"

cat >"$bin/fc-match" <<'EOF'
#!/bin/sh
family=${3:-}
family=${family%:charset=20-7e}
case $family in
'MesloLGS Nerd Font Mono')
	if [ "${DWM_TEST_FONT_DEFAULT_ALIAS:-0}" = 1 ]; then
		printf '%s\n' 'MesloLGS NF'
	else
		printf '%s\n' "$family"
	fi
	;;
Inter | 'Noto Sans') printf '%s\n' "$family" ;;
*) printf '%s\n' 'Fallback Sans' ;;
esac
EOF
chmod +x "$bin/fc-match"

run_font() {
	PATH="$bin" HOME="$home" XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$state" \
		DWM_SETTINGS_FONT_NO_WATCHDOG=1 "$repo/scripts/dwm-settings-font" "$@"
}

run_font_watchdog() {
	PATH="$bin" HOME="$home" XDG_CONFIG_HOME="$config" XDG_STATE_HOME="$state" \
		"$repo/scripts/dwm-settings-font" "$@"
}

run_font_relative_xdg() {
	PATH="$bin" HOME="$home" XDG_CONFIG_HOME=relative-config XDG_STATE_HOME=relative-state \
		DWM_SETTINGS_FONT_NO_WATCHDOG=1 "$repo/scripts/dwm-settings-font" "$@"
}

status=$(run_font status)
grep -Fqx $'appearance-font-action-protocol\t1\t0' <<<"$status"
grep -Fqx $'provider\tfont\tavailable\tuser-session\tManaged shell font and text scale' <<<"$status"
grep -Fqx $'selection\tavailable\tMesloLGS Nerd Font Mono\t1.00\tManaged shell font defaults are active' <<<"$status"
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
run_font mutation-ready
ln -sfn "$work/mv-without-exchange-options" "$bin/mv"
if run_font mutation-ready 2>"$work/mv-options.err"; then
	printf 'Font mutation readiness accepted mv without exchange options\n' >&2
	exit 1
fi
grep -Fqx 'GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)' \
	"$work/mv-options.err"
ln -sfn "$work/mv-without-filesystem-exchange" "$bin/mv"
if run_font mutation-ready 2>"$work/mv-filesystem.err"; then
	printf 'Font mutation readiness accepted a filesystem without atomic exchange\n' >&2
	exit 1
fi
grep -Fqx 'Atomic file exchange is unavailable on the font configuration filesystem' \
	"$work/mv-filesystem.err"
ln -sfn "$real_mv" "$bin/mv"

relative_status=$(run_font_relative_xdg status)
grep -Fqx $'selection\tavailable\tMesloLGS Nerd Font Mono\t1.00\tManaged shell font defaults are active' \
	<<<"$relative_status"
run_font_relative_xdg apply Inter 1.10 >/dev/null
grep -Fqx $'family\tInter' "$home/.config/dwm-titus/font.conf"
grep -Fqx $'scale\t1.10' "$home/.config/dwm-titus/font.conf"
run_font_relative_xdg reset >/dev/null

run_font preview preview-absent-baseline 30 Inter 1.25 >/dev/null
unlink "$font_config"
status=$(run_font status)
grep -Fq $'preview\tfailed\tpreview-absent-baseline\tMesloLGS Nerd Font Mono\t1.00\t0\t' \
	<<<"$status"
run_font revert preview-absent-baseline >"$work/absent-revert.out"
grep -Fqx $'result\trevert' "$work/absent-revert.out"
[[ ! -e $font_config ]]
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]

export DWM_TEST_FONT_DEFAULT_ALIAS=1
status=$(run_font status)
grep -Fqx $'selection\tavailable\tMesloLGS Nerd Font Mono\t1.00\tManaged shell font defaults are active' <<<"$status"
run_font apply 'MesloLGS Nerd Font Mono' 1.00 >/dev/null
grep -Fqx $'family\tMesloLGS Nerd Font Mono' "$config/dwm-titus/font.conf"
run_font reset >/dev/null
unset DWM_TEST_FONT_DEFAULT_ALIAS

if run_font apply Missing 1.00 2>"$work/missing.err"; then
	printf 'Uninstalled font selection unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fqx 'font family is not installed or lacks basic interface glyphs: Missing' "$work/missing.err"

if run_font apply Inter 1.33 2>"$work/scale.err"; then
	printf 'Unsupported font scale unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'text scale must be one of' "$work/scale.err"

run_font apply Inter 1.25 >"$work/apply.out"
grep -Fqx $'result\tapplied' "$work/apply.out"
grep -Fqx $'appearance-font-protocol\t1\t0' "$font_config"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.25' "$font_config"
[[ $(stat -c %a "$font_config") == 600 ]]
ln -sfn "$work/mv-without-exchange-options" "$bin/mv"
if run_font apply 'Noto Sans' 0.90 >"$work/mv-publish.out" 2>"$work/mv-publish.err"; then
	printf 'Font apply accepted mv without atomic exchange support\n' >&2
	exit 1
fi
grep -Fqx 'dwm-settings-font: GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)' \
	"$work/mv-publish.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.25' "$font_config"
ln -sfn "$real_mv" "$bin/mv"

chmod 640 "$font_config"
run_font apply 'Noto Sans' 0.90 >/dev/null
[[ $(stat -c %a "$font_config") == 640 ]]
chmod 400 "$font_config"
run_font apply 'Noto Sans' 0.90 >/dev/null
[[ $(stat -c %a "$font_config") == 400 ]]
chmod 640 "$font_config"
status=$(run_font status)
grep -Fqx $'selection\tavailable\tNoto Sans\t0.90\tManaged shell font selection is persisted' <<<"$status"

real_chmod=$(command -v chmod)
unlink "$bin/chmod"
cat >"$bin/chmod" <<EOF
#!/bin/bash
set -eu
target=\${@: -1}
if [[ \${DWM_TEST_FONT_CHMOD_FAIL:-0} == 1 && \$target == */.font.conf.* ]]; then
	exit 1
fi
exec "$real_chmod" "\$@"
EOF
chmod +x "$bin/chmod"
staging_failure_hash=$(sha256sum "$font_config" | awk '{ print $1 }')
if DWM_TEST_FONT_CHMOD_FAIL=1 run_font apply Inter 1.25 \
	>"$work/staging-failure.out" 2>"$work/staging-failure.err"; then
	printf 'Font apply unexpectedly published after a staging mode failure\n' >&2
	exit 1
fi
grep -Fqx 'font configuration changed outside Settings; selection was not applied' \
	"$work/staging-failure.err"
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$staging_failure_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
unlink "$bin/chmod"
ln -s "$real_chmod" "$bin/chmod"

baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')
DWM_SETTINGS_FONT_NOW=1000 run_font preview preview-revert 30 Inter 1.50 >"$work/preview.out"
grep -Fqx $'result\tpreview-started' "$work/preview.out"
grep -Fqx $'family\tInter' "$font_config"
status=$(DWM_SETTINGS_FONT_NOW=1010 run_font status)
grep -Fqx $'preview\tactive\tpreview-revert\tInter\t1.50\t20\tAutomatic rollback is armed' <<<"$status"
run_font revert preview-revert >"$work/revert.out"
grep -Fqx $'result\trevert' "$work/revert.out"
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]

real_cp=$(command -v cp)
unlink "$bin/cp"
cat >"$bin/cp" <<EOF
#!/bin/bash
set -eu
source_path=\${@: -2:1}
target=\${!#}
if [[ \${DWM_TEST_FONT_FAIL_BASELINE_RESTORE:-0} == 1 &&
	\$source_path == */preview.baseline && \$target == */.font.conf.restore.* ]]; then
	printf 'partial rollback data\n' >"\$target"
	exit 1
fi
"$real_cp" "\$@"
if [[ \${DWM_TEST_FONT_EDIT_AFTER_BASELINE_COPY:-0} == 1 && \$source_path == */font.conf &&
	-n \${DWM_TEST_FONT_BASELINE_SENTINEL:-} && ! -e \$DWM_TEST_FONT_BASELINE_SENTINEL ]]; then
	: >"\$DWM_TEST_FONT_BASELINE_SENTINEL"
	printf 'appearance-font-protocol\t1\t0\nfamily\tInter\nscale\t0.80\n' >"\$source_path"
fi
EOF
chmod +x "$bin/cp"
run_font preview preview-restore-copy-failure 30 Inter 1.25 >/dev/null
preview_hash=$(sha256sum "$font_config" | awk '{ print $1 }')
if DWM_TEST_FONT_FAIL_BASELINE_RESTORE=1 run_font revert preview-restore-copy-failure \
	>"$work/restore-copy-failure.out" 2>"$work/restore-copy-failure.err"; then
	printf 'Font rollback unexpectedly succeeded after a baseline copy failure\n' >&2
	exit 1
fi
grep -Fq 'previous font configuration could not be restored' "$work/restore-copy-failure.err"
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$preview_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
[[ -e $state/dwm-titus/appearance/font/preview.current ]]
[[ -e $state/dwm-titus/appearance/font/preview.baseline ]]
status=$(run_font status)
grep -Fq $'preview\tfailed\tpreview-restore-copy-failure\tInter\t1.25\t0\t' <<<"$status"
run_font revert preview-restore-copy-failure >/dev/null
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
if DWM_TEST_FONT_EDIT_AFTER_BASELINE_COPY=1 \
	DWM_TEST_FONT_BASELINE_SENTINEL=$work/font-baseline-race \
	run_font preview preview-baseline-race 30 'Noto Sans' 1.25 \
	>"$work/baseline-race.out" 2>"$work/baseline-race.err"; then
	printf 'Font preview unexpectedly overwrote an edit made after baseline capture\n' >&2
	exit 1
fi
grep -Fqx 'font configuration changed outside Settings; preview was not applied' \
	"$work/baseline-race.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
unlink "$bin/cp"
ln -s "$real_cp" "$bin/cp"
run_font apply 'Noto Sans' 0.90 >/dev/null
baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')

unlink "$bin/mv"
cat >"$bin/mv" <<EOF
#!/bin/bash
set -eu
source_path=\${@: -2:1}
target=\${!#}
if [[ \${DWM_TEST_FONT_KILL_BEFORE_EXCHANGE:-0} == 1 &&
	\$source_path == */.font.conf.preview-exchange.* && \$target == */font.conf &&
	-n \${DWM_TEST_FONT_KILL_SENTINEL:-} && ! -e \$DWM_TEST_FONT_KILL_SENTINEL ]]; then
	: >"\$DWM_TEST_FONT_KILL_SENTINEL"
	kill -KILL "\$PPID"
	exit 137
fi
"$real_mv" "\$@"
if [[ \${DWM_TEST_FONT_KILL_ON_CONFIG_WRITE:-0} == 1 && \$target == */font.conf &&
	-n \${DWM_TEST_FONT_KILL_SENTINEL:-} && ! -e \$DWM_TEST_FONT_KILL_SENTINEL ]]; then
	: >"\$DWM_TEST_FONT_KILL_SENTINEL"
	kill -KILL "\$PPID"
fi
if [[ \${DWM_TEST_FONT_TERM_AFTER_EXCHANGE:-0} == 1 &&
	\$source_path == */.font.conf.preview-exchange.* && \$target == */font.conf &&
	-n \${DWM_TEST_FONT_TERM_SENTINEL:-} && ! -e \$DWM_TEST_FONT_TERM_SENTINEL ]]; then
	: >"\$DWM_TEST_FONT_TERM_SENTINEL"
	chmod 600 -- "\$target"
	kill -TERM "\$PPID"
	exit 143
fi
EOF
chmod +x "$bin/mv"
if DWM_TEST_FONT_KILL_BEFORE_EXCHANGE=1 \
	DWM_TEST_FONT_KILL_SENTINEL=$work/font-killed-before-exchange \
	run_font_watchdog preview preview-before-exchange 5 Inter 1.50 >/dev/null 2>&1; then
	printf 'Pre-exchange crash interruption unexpectedly succeeded\n' >&2
	exit 1
fi
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
i=0
while [[ -e $state/dwm-titus/appearance/font/preview.current && $i -lt 80 ]]; do
	((i += 1))
	sleep 0.1
done
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
if DWM_TEST_FONT_TERM_AFTER_EXCHANGE=1 \
	DWM_TEST_FONT_TERM_SENTINEL=$work/font-term-after-exchange \
	run_font preview preview-term-after-exchange 30 Inter 1.50 >/dev/null 2>&1; then
	printf 'Signal-interrupted font preview unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.50' "$font_config"
[[ $(stat -c %a "$font_config") == 600 ]]
[[ -e $state/dwm-titus/appearance/font/preview.current ]]
[[ -e $state/dwm-titus/appearance/font/preview.baseline ]]
status=$(run_font status)
grep -Fq $'preview\tfailed\tpreview-term-after-exchange\tInter\t1.50\t0\t' <<<"$status"
chmod 640 -- "$font_config"
run_font revert preview-term-after-exchange >/dev/null
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
if DWM_TEST_FONT_KILL_ON_CONFIG_WRITE=1 DWM_TEST_FONT_KILL_SENTINEL=$work/font-killed \
	run_font_watchdog preview preview-crash 5 Inter 1.50 >/dev/null 2>&1; then
	printf 'Crash-interrupted font preview unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fqx $'family\tInter' "$font_config"
i=0
while [[ -e $state/dwm-titus/appearance/font/preview.current && $i -lt 80 ]]; do
	((i += 1))
	sleep 0.1
done
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == 640 ]]
unlink "$bin/mv"
ln -s "$real_mv" "$bin/mv"

unlink "$bin/mv"
cat >"$bin/mv" <<EOF
#!/bin/bash
set -eu
source_path=\${@: -2:1}
target=\${!#}
if [[ \${DWM_TEST_FONT_EDIT_DURING_EXCHANGE:-0} == 1 && \$target == */font.conf &&
	\$source_path == */.font.conf.* && -n \${DWM_TEST_FONT_EXCHANGE_SENTINEL:-} &&
	! -e \$DWM_TEST_FONT_EXCHANGE_SENTINEL ]]; then
	: >"\$DWM_TEST_FONT_EXCHANGE_SENTINEL"
	printf 'appearance-font-protocol\t1\t0\nfamily\tInter\nscale\t0.80\n' >"\$target"
fi
exec "$real_mv" "\$@"
EOF
chmod +x "$bin/mv"
if DWM_TEST_FONT_EDIT_DURING_EXCHANGE=1 \
	DWM_TEST_FONT_EXCHANGE_SENTINEL=$work/font-exchange-race \
	run_font preview preview-exchange-race 30 'Noto Sans' 1.25 \
	>"$work/exchange-race.out" 2>"$work/exchange-race.err"; then
	printf 'Font preview unexpectedly overwrote an edit made during atomic exchange\n' >&2
	exit 1
fi
grep -Fqx 'font configuration changed outside Settings; preview was not applied' \
	"$work/exchange-race.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
run_font apply 'Noto Sans' 0.90 >/dev/null
baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')
run_font preview preview-restore-exchange 30 Inter 1.25 >/dev/null
if DWM_TEST_FONT_EDIT_DURING_EXCHANGE=1 \
	DWM_TEST_FONT_EXCHANGE_SENTINEL=$work/font-restore-exchange-race \
	run_font revert preview-restore-exchange \
	>"$work/restore-exchange-race.out" 2>"$work/restore-exchange-race.err"; then
	printf 'Font rollback unexpectedly overwrote an edit made during atomic exchange\n' >&2
	exit 1
fi
grep -Fq 'previous font configuration could not be restored' "$work/restore-exchange-race.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"
status=$(run_font status)
grep -Fq $'preview\tfailed\tpreview-restore-exchange\tInter\t0.80\t0\tFont configuration changed outside Settings; automatic rollback was not applied' \
	<<<"$status"
run_font abandon preview-restore-exchange >/dev/null
unlink "$bin/mv"
ln -s "$real_mv" "$bin/mv"
run_font apply 'Noto Sans' 0.90 >/dev/null
baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')

real_setsid=$(command -v setsid)
unlink "$bin/setsid"
cat >"$bin/setsid" <<EOF
#!/bin/bash
set -eu
if [[ \${DWM_TEST_FONT_EDIT_BEFORE_PUBLISH:-0} == 1 && -n \${DWM_TEST_FONT_CONFIG_PATH:-} ]]; then
	printf 'appearance-font-protocol\t1\t0\nfamily\tInter\nscale\t0.80\n' \
		>"\$DWM_TEST_FONT_CONFIG_PATH"
fi
exec "$real_setsid" "\$@"
EOF
chmod +x "$bin/setsid"
if DWM_TEST_FONT_EDIT_BEFORE_PUBLISH=1 DWM_TEST_FONT_CONFIG_PATH=$font_config \
	run_font_watchdog preview preview-race 30 'Noto Sans' 1.25 \
	>"$work/race.out" 2>"$work/race.err"; then
	printf 'Font preview unexpectedly overwrote a concurrent edit\n' >&2
	exit 1
fi
grep -Fqx 'font configuration changed outside Settings; preview was not applied' "$work/race.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
unlink "$bin/setsid"
ln -s "$real_setsid" "$bin/setsid"
run_font apply 'Noto Sans' 0.90 >/dev/null
baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')

DWM_SETTINGS_FONT_NOW=2000 run_font preview preview-keep 30 Inter 1.10 >/dev/null
DWM_SETTINGS_FONT_NOW=2010 run_font keep preview-keep >"$work/keep.out"
grep -Fqx $'result\tkeep' "$work/keep.out"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.10' "$font_config"
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]

DWM_SETTINGS_FONT_NOW=2500 run_font preview preview-late-keep 5 'Noto Sans' 1.50 >/dev/null
if DWM_SETTINGS_FONT_NOW=2506 run_font keep preview-late-keep >"$work/late-keep.out" 2>"$work/late-keep.err"; then
	printf 'Expired font preview was unexpectedly kept\n' >&2
	exit 1
fi
grep -Fqx 'font preview has expired' "$work/late-keep.err"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.10' "$font_config"

DWM_SETTINGS_FONT_NOW=2600 run_font preview preview-active-abandon 30 'Noto Sans' 1.25 >/dev/null
if DWM_SETTINGS_FONT_NOW=2601 run_font abandon preview-active-abandon \
	>"$work/active-abandon.out" 2>"$work/active-abandon.err"; then
	printf 'Healthy font preview was unexpectedly abandoned\n' >&2
	exit 1
fi
grep -Fqx 'font preview is not stale; use keep or revert' "$work/active-abandon.err"
run_font revert preview-active-abandon >/dev/null

DWM_SETTINGS_FONT_NOW=3000 run_font preview preview-expire 5 'Noto Sans' 1.50 >/dev/null
status=$(DWM_SETTINGS_FONT_NOW=3006 run_font status)
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.10' "$font_config"

test_boot_old=11111111-1111-1111-1111-111111111111
test_boot_new=22222222-2222-2222-2222-222222222222
DWM_SETTINGS_FONT_NOW=5000 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_old \
	run_font preview preview-reboot 30 'Noto Sans' 1.25 >/dev/null
shell_start=$(awk '{ line=$0; sub(/^.*\) /, "", line); split(line, field, " "); print field[20] }' "/proc/$$/stat")
awk -F '\t' -v pid="$$" -v start="$shell_start" \
	'BEGIN { OFS = "\t" } $1 == "watchdog-pid" { $2 = pid } $1 == "watchdog-start" { $2 = start } { print }' \
	"$state/dwm-titus/appearance/font/preview.meta" >"$work/reboot.meta"
mv "$work/reboot.meta" "$state/dwm-titus/appearance/font/preview.meta"
status=$(DWM_SETTINGS_FONT_NOW=5001 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new run_font status)
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
grep -Fqx $'family\tInter' "$font_config"
kill -0 $$

# Recover metadata that became durable before the preview configuration was
# published. The untouched baseline is not an external edit and can be cleared
# without rewriting the user's file.
baseline_hash=$(sha256sum "$font_config" | awk '{ print $1 }')
baseline_mode=$(stat -c %a "$font_config")
preview_hash=$(printf '%s\nfamily\t%s\nscale\t%s\n' \
	$'appearance-font-protocol\t1\t0' 'Noto Sans' 1.25 | sha256sum | awk '{ print $1 }')
font_state_dir=$state/dwm-titus/appearance/font
cp "$font_config" "$font_state_dir/preview.baseline"
chmod 600 "$font_state_dir/preview.baseline"
printf '%s\n' preview-never-published >"$font_state_dir/preview.current"
printf '%s\t%s\n' \
	token preview-never-published deadline 6000 boot-id "$test_boot_new" \
	family 'Noto Sans' scale 1.25 hash "$preview_hash" baseline-present yes \
	baseline-mode "$baseline_mode" watchdog-pid '' watchdog-start '' published no \
	>"$font_state_dir/preview.meta"
status=$(DWM_SETTINGS_FONT_NOW=6001 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new run_font status)
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
[[ $(sha256sum "$font_config" | awk '{ print $1 }') == "$baseline_hash" ]]
[[ $(stat -c %a "$font_config") == "$baseline_mode" ]]
[[ ! -e $font_state_dir/preview.current ]]

DWM_SETTINGS_FONT_NOW=7000 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new \
	run_font_watchdog preview preview-frozen 5 'Noto Sans' 1.25 >/dev/null
sleep 5.2
status=$(DWM_SETTINGS_FONT_NOW=7000 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new run_font_watchdog status)
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t1.10' "$font_config"

DWM_SETTINGS_FONT_NOW=8000 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new \
	run_font_watchdog preview preview-watchdog-external 5 'Noto Sans' 1.25 >/dev/null
printf '%s\nfamily\tInter\nscale\t0.80\n' $'appearance-font-protocol\t1\t0' >"$font_config"
status=$(DWM_SETTINGS_FONT_NOW=8006 DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new run_font_watchdog status)
grep -Fq $'preview\tfailed\tpreview-watchdog-external\tInter\t0.80\t0\tFont configuration changed outside Settings; automatic rollback was not applied' <<<"$status"
DWM_SETTINGS_FONT_BOOT_ID=$test_boot_new run_font_watchdog abandon preview-watchdog-external >/dev/null

run_font_watchdog preview preview-watchdog-lock 5 'Noto Sans' 1.25 >/dev/null
watchdog_lock=$state/dwm-titus/appearance/font/mutation.lock
exec 8>"$watchdog_lock"
flock -x 8
sleep 10.5
flock -u 8
exec 8>&-
i=0
while [[ -e $state/dwm-titus/appearance/font/preview.current && $i -lt 100 ]]; do
	((i += 1))
	sleep 0.1
done
[[ ! -e $state/dwm-titus/appearance/font/preview.current ]]
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"

run_font_watchdog preview preview-cleanup 30 'Noto Sans' 1.25 >/dev/null
cleanup_watchdog_pid=$(awk -F '\t' '$1 == "watchdog-pid" { print $2 }' \
	"$state/dwm-titus/appearance/font/preview.meta")
cleanup_children=''
for _ in {1..50}; do
	cleanup_children=$(cat "/proc/$cleanup_watchdog_pid/task/$cleanup_watchdog_pid/children" 2>/dev/null || true)
	[[ -n $cleanup_children ]] && break
	sleep 0.01
done
[[ -n $cleanup_children ]]
run_font_watchdog revert preview-cleanup >/dev/null
for _ in {1..50}; do
	if process_is_live "$cleanup_watchdog_pid"; then
		sleep 0.01
		continue
	fi
	children_gone=true
	for child in $cleanup_children; do
		process_is_live "$child" && children_gone=false
	done
	[[ $children_gone == true ]] && break
	sleep 0.01
done
if process_is_live "$cleanup_watchdog_pid"; then
	printf 'Font preview cleanup left watchdog process %s alive\n' "$cleanup_watchdog_pid" >&2
	exit 1
fi
for child in $cleanup_children; do
	if process_is_live "$child"; then
		printf 'Font preview cleanup left watchdog child %s alive\n' "$child" >&2
		exit 1
	fi
done

run_font_watchdog preview preview-watchdog 30 'Noto Sans' 1.25 >/dev/null
status=$(run_font_watchdog status)
grep -Fq $'preview\tactive\tpreview-watchdog\tNoto Sans\t1.25\t' <<<"$status"
watchdog_pid=$(awk -F '\t' '$1 == "watchdog-pid" { print $2 }' \
	"$state/dwm-titus/appearance/font/preview.meta")
kill -TERM -- "-$watchdog_pid"
i=0
while kill -0 "$watchdog_pid" 2>/dev/null && [[ $i -lt 50 ]]; do
	((i += 1))
	sleep 0.01
done
status=$(run_font_watchdog status)
grep -Fqx $'preview\tnone\t\t\t\t0\tNo font preview is active' <<<"$status"
grep -Fqx $'family\tInter' "$font_config"
grep -Fqx $'scale\t0.80' "$font_config"

DWM_SETTINGS_FONT_NOW=4000 run_font preview preview-external 30 'Noto Sans' 1.25 >/dev/null
printf '%s\nfamily\tInter\nscale\t0.80\n' $'appearance-font-protocol\t1\t0' >"$font_config"
if DWM_SETTINGS_FONT_NOW=4001 run_font status >"$work/external-status" 2>"$work/external.err"; then
	:
fi
grep -Fq $'preview\tfailed\tpreview-external\tInter\t0.80\t0\tFont configuration changed outside Settings' "$work/external-status"
run_font abandon preview-external >"$work/abandon.out"
grep -Fqx $'result\tabandon' "$work/abandon.out"
grep -Fqx $'family\tInter' "$font_config"

run_font apply 'Noto Sans' 0.90 >/dev/null
chmod 640 "$font_config"
run_font preview preview-mode-external 30 Inter 1.25 >/dev/null
chmod 600 "$font_config"
if run_font revert preview-mode-external >"$work/mode-revert.out" 2>"$work/mode-revert.err"; then
	printf 'Font rollback unexpectedly overwrote an external mode change\n' >&2
	exit 1
fi
grep -Fq 'previous font configuration could not be restored' "$work/mode-revert.err"
[[ $(stat -c %a "$font_config") == 600 ]]
status=$(run_font status)
grep -Fq $'preview\tfailed\tpreview-mode-external\tInter\t1.25\t0\tFont configuration changed outside Settings; automatic rollback was not applied' \
	<<<"$status"
run_font abandon preview-mode-external >/dev/null

printf '%s\nfamily\tInter\nscale\t9.00\n' $'appearance-font-protocol\t1\t0' >"$font_config"
status=$(run_font status)
grep -Fqx $'selection\tpartial\tMesloLGS Nerd Font Mono\t1.00\tFont configuration is malformed; safe shell defaults remain active' <<<"$status"

run_font reset >"$work/reset.out"
grep -Fqx $'result\treset' "$work/reset.out"
[[ ! -e $font_config ]]

printf '%04097d' 0 >"$font_config"
status=$(run_font status)
grep -Fqx $'selection\tpartial\tMesloLGS Nerd Font Mono\t1.00\tFont configuration is too large; safe shell defaults remain active' <<<"$status"
if run_font mutation-ready; then
	printf 'Oversized font configuration unexpectedly allowed mutation\n' >&2
	exit 1
fi
unlink "$font_config"

run_font apply Inter 1.00 >/dev/null
ln "$font_config" "$work/font-hardlink"
if run_font status >"$work/hardlink.out" 2>"$work/hardlink.err"; then
	printf 'Hard-linked font configuration unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'must not have multiple hard links' "$work/hardlink.err"
unlink "$work/font-hardlink"
run_font reset >/dev/null

unsafe=$work/unsafe
mkdir -p "$unsafe"
rmdir "$config/dwm-titus"
ln -s "$unsafe" "$config/dwm-titus"
if run_font status >"$work/symlink.out" 2>"$work/symlink.err"; then
	printf 'Symlinked font configuration directory unexpectedly succeeded\n' >&2
	exit 1
fi
grep -Fq 'unsafe font configuration path' "$work/symlink.err"

printf 'dwm-settings-font tests passed\n'
