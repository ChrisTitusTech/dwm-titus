#!/usr/bin/env bash
set -euo pipefail

repo=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper=$repo/scripts/dwm-xdg-autostart
test_tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
mkdir -p -- "$test_tmp_root"
work=$(mktemp -d "$test_tmp_root/dwm-xdg-autostart-test.XXXXXX")
watch_owner=
watch_helper=
watch_child=
watch_child_start=
boundary_helper=
boundary_reader=

cleanup() {
	set +e
	for pid in "$watch_owner" "$watch_helper" "$watch_child" "$boundary_helper" "$boundary_reader"; do
		case $pid in '' | *[!0-9]*) continue ;; esac
		kill -TERM "$pid" 2>/dev/null || true
	done
	wait "$watch_owner" 2>/dev/null || true
	rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

expect_success_boundary_signal() {
	local label=$1
	shift
	local fifo=$work/$label.fifo output=$work/$label.out error=$work/$label.err
	local block=$work/$label.block ready=$work/$label.ready release=$work/$label.release
	local pid_file=$work/$label.pid status=0
	rm -f -- "$fifo" "$output" "$error" "$block" "$ready" "$release" "$pid_file"
	mkfifo -- "$fifo"
	(
		local protocol_line helper_pid
		exec 7<"$fifo"
		IFS= read -r protocol_line <&7
		printf '%s\n' "$protocol_line" >"$output"
		: >"$block"
		wait_for test -e "$ready"
		wait_for test -s "$pid_file"
		helper_pid=$(cat "$pid_file")
		kill -TERM "$helper_pid"
		: >"$release"
		wait_for pid_gone "$helper_pid"
		exec 7<&-
	) &
	boundary_reader=$!
	env HOME="$work/home" XDG_CONFIG_HOME="$work/config" \
		XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" \
		PATH="$work/bin:/usr/bin:/bin" DWM_TEST_REAL_AWK="$real_awk" \
		DWM_TEST_SUCCESS_BLOCK="$block" DWM_TEST_SUCCESS_READY="$ready" \
		DWM_TEST_SUCCESS_RELEASE="$release" \
		"$helper" "$@" >"$fifo" 2>"$error" &
	boundary_helper=$!
	printf '%s\n' "$boundary_helper" >"$pid_file"
	wait "$boundary_helper" || status=$?
	boundary_helper=
	wait "$boundary_reader"
	boundary_reader=
	[[ $status -eq 143 ]]
	grep -Fqx $'autostart-protocol\t1\t0' "$output"
	if grep -Fq $'action\tsuccess\t' "$output"; then
		printf 'Interrupted success-boundary action emitted success: %s\n' "$label" >&2
		exit 1
	fi
	[[ ! -e $work/config/autostart/.dwm-titus.lock ]]
	rm -f -- "$fifo"
}

mkdir -p "$work/config/autostart" "$work/vendor-a/autostart" \
	"$work/vendor-b/autostart" "$work/bin" "$work/home"

cat >"$work/vendor-a/autostart/example.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Example Vendor
Exec=/bin/true
NotShowIn=GNOME;
# Preserve this comment and the custom group.

[X-DWM-Test]
CustomKey=preserve-me
EOF

cat >"$work/vendor-b/autostart/example.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Wrong Lower Priority Vendor
Exec=/bin/false
EOF

cat >"$work/vendor-a/autostart/only.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Only KDE
Exec=/bin/true
OnlyShowIn=KDE;
EOF

cat >"$work/vendor-a/autostart/only-dwm.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Only DWM
Exec=/bin/true
OnlyShowIn=X-DWM;
EOF

cat >"$work/vendor-a/autostart/hidden.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hidden Everywhere
Exec=/bin/true
Hidden=true
EOF

cat >"$work/vendor-a/autostart/conditional.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Conditional
Exec=/bin/true
AutostartCondition=GSettings org.example enabled
EOF

cat >"$work/vendor-a/autostart/missing-try.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Missing TryExec
Exec=/bin/true
TryExec=dwm-definitely-missing-command
EOF

cat >"$work/vendor-a/autostart/malformed.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Malformed
Exec=/bin/true
NotShowIn=GNOME;
NotShowIn=KDE;
EOF

cat >"$work/vendor-a/autostart/picom.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Picom
Exec=/bin/true
EOF

cat >"$work/config/autostart/user-only.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=User Only
Exec=/bin/true
EOF

cat >"$work/outside.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Outside
Exec=/bin/true
EOF
ln -s "$work/outside.desktop" "$work/config/autostart/symlink.desktop"

common_env=(
	HOME="$work/home"
	XDG_CONFIG_HOME="$work/config"
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b"
	PATH="/usr/bin:/bin"
)

run_helper() {
	env "${common_env[@]}" "$helper" "$@"
}

entry_field() {
	local output=$1 desktop_id=$2 field=$3
	awk -F '\t' -v id="$desktop_id" -v field="$field" \
		'$1 == "entry" && $2 == id { print $field; exit }' "$output"
}

action_field() {
	local output=$1 field=$2
	awk -F '\t' -v field="$field" '$1 == "action" { print $field; exit }' "$output"
}

expect_failure() {
	local pattern=$1
	shift
	if "$@" >"$work/failure.out" 2>"$work/failure.err"; then
		printf 'command unexpectedly succeeded: %s\n' "$*" >&2
		exit 1
	fi
	grep -Fq -- "$pattern" "$work/failure.err"
	if grep -Fq $'action\tsuccess\t' "$work/failure.out"; then
		printf 'failed action emitted a success record\n' >&2
		exit 1
	fi
}

expect_interrupted() {
	local status
	if "$@" >"$work/interrupted.out" 2>"$work/interrupted.err"; then
		printf 'interrupted command unexpectedly succeeded: %s\n' "$*" >&2
		exit 1
	else
		status=$?
	fi
	[[ $status == 143 ]]
	if grep -Fq $'action\tsuccess\t' "$work/interrupted.out"; then
		printf 'interrupted action emitted a success record\n' >&2
		exit 1
	fi
}

wait_for() {
	local attempts=0
	until "$@"; do
		attempts=$((attempts + 1))
		((attempts < 100)) || return 1
		sleep 0.05
	done
}

pid_gone() {
	! kill -0 "$1" 2>/dev/null
}

line_count_at_least() {
	local file=$1 line=$2 expected=$3 count
	count=$(grep -Fxc -- "$line" "$file" 2>/dev/null || true)
	((count >= expected))
}

watch_child_replaced() {
	local candidate start
	candidate=$(pgrep -P "$watch_helper" -x inotifywait 2>/dev/null || true)
	[[ $candidate =~ ^[0-9]+$ ]] || return 1
	start=$(sed 's/^.*) //' "/proc/$candidate/stat" 2>/dev/null | awk '{ print $20 }') || return 1
	[[ $candidate:$start != "$watch_child_start" ]] || return 1
	watch_child=$candidate
	watch_child_start=$candidate:$start
}

run_helper snapshot >"$work/snapshot"
grep -Fqx $'autostart-protocol\t1\t0' "$work/snapshot"
grep -Fqx $'provider\tdegraded\tone or more entries are unsupported or malformed' "$work/snapshot"
[[ $(entry_field "$work/snapshot" example.desktop 3) == 'Example Vendor' ]]
[[ $(entry_field "$work/snapshot" example.desktop 4) == vendor ]]
[[ $(entry_field "$work/snapshot" example.desktop 5) == enabled ]]
[[ $(entry_field "$work/snapshot" example.desktop 6) == visible ]]
[[ $(entry_field "$work/snapshot" example.desktop 7) == 0 ]]
[[ $(entry_field "$work/snapshot" example.desktop 8) == 1 ]]
[[ $(entry_field "$work/snapshot" example.desktop 9) == 0 ]]
[[ $(entry_field "$work/snapshot" example.desktop 10) == normal ]]
[[ $(entry_field "$work/snapshot" example.desktop 12) == 0 ]]
[[ $(entry_field "$work/snapshot" example.desktop 13) == 1 ]]
[[ $(entry_field "$work/snapshot" only.desktop 5) == non-applicable ]]
[[ $(entry_field "$work/snapshot" only.desktop 12) == 1 ]]
[[ $(entry_field "$work/snapshot" only.desktop 13) == 0 ]]
[[ $(entry_field "$work/snapshot" only-dwm.desktop 5) == enabled ]]
[[ $(entry_field "$work/snapshot" only-dwm.desktop 12) == 0 ]]
[[ $(entry_field "$work/snapshot" only-dwm.desktop 13) == 1 ]]
[[ $(entry_field "$work/snapshot" hidden.desktop 5) == disabled ]]
[[ $(entry_field "$work/snapshot" hidden.desktop 6) == hidden ]]
[[ $(entry_field "$work/snapshot" hidden.desktop 12) == 0 ]]
[[ $(entry_field "$work/snapshot" hidden.desktop 13) == 0 ]]
[[ $(entry_field "$work/snapshot" conditional.desktop 5) == conditional ]]
[[ $(entry_field "$work/snapshot" conditional.desktop 13) == 1 ]]
[[ $(entry_field "$work/snapshot" missing-try.desktop 5) == non-applicable ]]
[[ $(entry_field "$work/snapshot" missing-try.desktop 12) == 0 ]]
[[ $(entry_field "$work/snapshot" missing-try.desktop 13) == 0 ]]
[[ $(entry_field "$work/snapshot" malformed.desktop 5) == malformed ]]
[[ $(entry_field "$work/snapshot" symlink.desktop 5) == unsupported ]]
[[ $(entry_field "$work/snapshot" user-only.desktop 4) == user-only ]]
[[ $(entry_field "$work/snapshot" user-only.desktop 9) == 0 ]]
[[ $(entry_field "$work/snapshot" picom.desktop 10) == session-critical ]]

mkdir "$work/config-target"
ln -s "$work/config-target" "$work/config-link"
env HOME="$work/home" XDG_CONFIG_HOME="$work/config-link" \
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" PATH="/usr/bin:/bin" \
	"$helper" snapshot >"$work/symlinked-config-snapshot"
grep -Fqx $'autostart-protocol\t1\t0' "$work/symlinked-config-snapshot"
grep -Fqx $'provider\tunavailable\tXDG_CONFIG_HOME is symlinked or unsafe' \
	"$work/symlinked-config-snapshot"
if grep -Fq $'entry\t' "$work/symlinked-config-snapshot"; then
	printf 'symlinked XDG_CONFIG_HOME exposed an inconsistent entry snapshot\n' >&2
	exit 1
fi

example_revision=$(entry_field "$work/snapshot" example.desktop 11)
[[ $example_revision =~ ^[0-9a-f]{64}$ ]]
vendor_hash=$(sha256sum "$work/vendor-a/autostart/example.desktop")
run_helper set example.desktop disabled "$example_revision" >"$work/disable"
grep -Fqx $'autostart-protocol\t1\t0' "$work/disable"
[[ $(action_field "$work/disable" 2) == success ]]
[[ $(action_field "$work/disable" 3) == set ]]
[[ $(action_field "$work/disable" 4) == example.desktop ]]
[[ $(action_field "$work/disable" 5) == disabled ]]
[[ -z $(action_field "$work/disable" 7) ]]
grep -Fqx 'NotShowIn=GNOME;X-DWM;' "$work/config/autostart/example.desktop"
grep -Fqx '# Preserve this comment and the custom group.' "$work/config/autostart/example.desktop"
grep -Fqx 'CustomKey=preserve-me' "$work/config/autostart/example.desktop"
[[ $(sha256sum "$work/vendor-a/autostart/example.desktop") == "$vendor_hash" ]]

run_helper snapshot >"$work/disabled-snapshot"
[[ $(entry_field "$work/disabled-snapshot" example.desktop 4) == user-override ]]
[[ $(entry_field "$work/disabled-snapshot" example.desktop 9) == 1 ]]
disabled_revision=$(entry_field "$work/disabled-snapshot" example.desktop 11)
expect_failure 'changed; refresh and try again' run_helper set example.desktop enabled "$example_revision"

disabled_hash=$(sha256sum "$work/config/autostart/example.desktop" | awk '{ print $1 }')
run_helper set example.desktop enabled "$disabled_revision" >"$work/enable"
[[ $(action_field "$work/enable" 5) == enabled ]]
enable_backup=$(action_field "$work/enable" 7)
[[ -f $enable_backup ]]
[[ $(stat -c %a "$enable_backup") == 600 ]]
[[ $(sha256sum "$enable_backup" | awk '{ print $1 }') == "$disabled_hash" ]]
grep -Fqx 'NotShowIn=GNOME;' "$work/config/autostart/example.desktop"
grep -Fqx 'CustomKey=preserve-me' "$work/config/autostart/example.desktop"

run_helper snapshot >"$work/enabled-snapshot"
enabled_revision=$(entry_field "$work/enabled-snapshot" example.desktop 11)
run_helper reset example.desktop "$enabled_revision" >"$work/reset"
[[ $(action_field "$work/reset" 3) == reset ]]
[[ $(action_field "$work/reset" 5) == enabled ]]
reset_backup=$(action_field "$work/reset" 7)
[[ -f $reset_backup ]]
[[ ! -e $work/config/autostart/example.desktop ]]
[[ $(sha256sum "$work/vendor-a/autostart/example.desktop") == "$vendor_hash" ]]

run_helper snapshot >"$work/only-before"
only_revision=$(entry_field "$work/only-before" only.desktop 11)
run_helper set only.desktop enabled "$only_revision" >"$work/only-enable"
grep -Fqx 'OnlyShowIn=KDE;X-DWM;' "$work/config/autostart/only.desktop"
[[ $(action_field "$work/only-enable" 5) == enabled ]]

run_helper snapshot >"$work/only-dwm-before"
only_dwm_revision=$(entry_field "$work/only-dwm-before" only-dwm.desktop 11)
run_helper set only-dwm.desktop disabled "$only_dwm_revision" >"$work/only-dwm-disable"
[[ $(action_field "$work/only-dwm-disable" 5) == non-applicable ]]
grep -Fqx 'OnlyShowIn=' "$work/config/autostart/only-dwm.desktop"
if grep -Fq 'NotShowIn=' "$work/config/autostart/only-dwm.desktop"; then
	printf 'OnlyShowIn-only disable unexpectedly added NotShowIn\n' >&2
	exit 1
fi
run_helper snapshot >"$work/only-dwm-after"
[[ $(entry_field "$work/only-dwm-after" only-dwm.desktop 5) == non-applicable ]]
[[ $(entry_field "$work/only-dwm-after" only-dwm.desktop 12) == 1 ]]
[[ $(entry_field "$work/only-dwm-after" only-dwm.desktop 13) == 0 ]]
only_dwm_disabled_revision=$(entry_field "$work/only-dwm-after" only-dwm.desktop 11)
run_helper set only-dwm.desktop enabled "$only_dwm_disabled_revision" >"$work/only-dwm-enable"
[[ $(action_field "$work/only-dwm-enable" 5) == enabled ]]
grep -Fqx 'OnlyShowIn=X-DWM;' "$work/config/autostart/only-dwm.desktop"
only_dwm_enabled_hash=$(sha256sum "$work/config/autostart/only-dwm.desktop")
run_helper snapshot >"$work/only-dwm-enabled"
only_dwm_enabled_revision=$(entry_field "$work/only-dwm-enabled" only-dwm.desktop 11)
run_helper set only-dwm.desktop enabled "$only_dwm_enabled_revision" >"$work/only-dwm-no-change"
[[ -z $(action_field "$work/only-dwm-no-change" 7) ]]
[[ $(sha256sum "$work/config/autostart/only-dwm.desktop") == "$only_dwm_enabled_hash" ]]

run_helper snapshot >"$work/hidden-before"
hidden_revision=$(entry_field "$work/hidden-before" hidden.desktop 11)
hidden_vendor_hash=$(sha256sum "$work/vendor-a/autostart/hidden.desktop")
expect_failure 'Hidden=true cannot be overridden safely' \
	run_helper set hidden.desktop enabled "$hidden_revision"
[[ ! -e $work/config/autostart/hidden.desktop ]]
[[ $(sha256sum "$work/vendor-a/autostart/hidden.desktop") == "$hidden_vendor_hash" ]]

run_helper snapshot >"$work/risk-before"
picom_revision=$(entry_field "$work/risk-before" picom.desktop 11)
expect_failure 'confirmation token required' \
	run_helper set picom.desktop disabled "$picom_revision"
run_helper set picom.desktop disabled "$picom_revision" confirm-session-critical >"$work/risk-set"
[[ $(action_field "$work/risk-set" 5) == disabled ]]

symlink_revision=$(entry_field "$work/risk-before" symlink.desktop 11)
outside_hash=$(sha256sum "$work/outside.desktop")
expect_failure 'non-regular or symlinked user override' \
	run_helper set symlink.desktop disabled "$symlink_revision"
[[ $(sha256sum "$work/outside.desktop") == "$outside_hash" ]]

cat >"$work/config/autostart/hardlink.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Hard Link
Exec=/bin/true
EOF
ln "$work/config/autostart/hardlink.desktop" "$work/hardlink-peer"
run_helper snapshot >"$work/hardlink-before"
hardlink_revision=$(entry_field "$work/hardlink-before" hardlink.desktop 11)
expect_failure 'hard-linked user override' \
	run_helper set hardlink.desktop disabled "$hardlink_revision"

run_helper snapshot >"$work/user-only-before"
user_only_revision=$(entry_field "$work/user-only-before" user-only.desktop 11)
expect_failure 'user-only entries cannot be reset' \
	run_helper reset user-only.desktop "$user_only_revision"

run_helper snapshot >"$work/transaction-before"
only_transaction_revision=$(entry_field "$work/transaction-before" only.desktop 11)
conditional_transaction_revision=$(entry_field "$work/transaction-before" conditional.desktop 11)
only_transaction_hash=$(sha256sum "$work/config/autostart/only.desktop" | awk '{ print $1 }')
only_transaction_mode=$(stat -c %a "$work/config/autostart/only.desktop")
real_mv=$(command -v mv)
cat >"$work/bin/mv" <<'EOF'
#!/bin/sh
target=
for argument do
	target=$argument
done
if [ "$target" = "${DWM_TEST_SIGNAL_TARGET:?}" ] && [ ! -e "${DWM_TEST_SIGNAL_MARKER:?}" ]; then
	"${DWM_TEST_REAL_MV:?}" "$@" || exit $?
	: >"$DWM_TEST_SIGNAL_MARKER"
	kill -TERM "$PPID"
	exit 0
fi
exec "${DWM_TEST_REAL_MV:?}" "$@"
EOF
chmod +x "$work/bin/mv"

expect_interrupted env \
	HOME="$work/home" XDG_CONFIG_HOME="$work/config" \
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" \
	PATH="$work/bin:/usr/bin:/bin" DWM_TEST_REAL_MV="$real_mv" \
	DWM_TEST_SIGNAL_TARGET="$work/config/autostart/only.desktop" \
	DWM_TEST_SIGNAL_MARKER="$work/set-existing.signal" \
	"$helper" set only.desktop disabled "$only_transaction_revision"
[[ $(sha256sum "$work/config/autostart/only.desktop" | awk '{ print $1 }') == "$only_transaction_hash" ]]
[[ $(stat -c %a "$work/config/autostart/only.desktop") == "$only_transaction_mode" ]]
[[ ! -e $work/config/autostart/.dwm-titus.lock ]]

expect_interrupted env \
	HOME="$work/home" XDG_CONFIG_HOME="$work/config" \
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" \
	PATH="$work/bin:/usr/bin:/bin" DWM_TEST_REAL_MV="$real_mv" \
	DWM_TEST_SIGNAL_TARGET="$work/config/autostart/conditional.desktop" \
	DWM_TEST_SIGNAL_MARKER="$work/set-new.signal" \
	"$helper" set conditional.desktop disabled "$conditional_transaction_revision"
[[ ! -e $work/config/autostart/conditional.desktop ]]
[[ ! -e $work/config/autostart/.dwm-titus.lock ]]
rm -f "$work/bin/mv"

real_rm=$(command -v rm)
cat >"$work/bin/rm" <<'EOF'
#!/bin/sh
matched=0
for argument do
	if [ "$argument" = "${DWM_TEST_SIGNAL_TARGET:?}" ]; then
		matched=1
	fi
done
if [ "$matched" = 1 ] && [ ! -e "${DWM_TEST_SIGNAL_MARKER:?}" ]; then
	"${DWM_TEST_REAL_RM:?}" "$@" || exit $?
	: >"$DWM_TEST_SIGNAL_MARKER"
	kill -TERM "$PPID"
	exit 0
fi
exec "${DWM_TEST_REAL_RM:?}" "$@"
EOF
chmod +x "$work/bin/rm"
run_helper snapshot >"$work/reset-transaction-before"
reset_transaction_revision=$(entry_field "$work/reset-transaction-before" only.desktop 11)
expect_interrupted env \
	HOME="$work/home" XDG_CONFIG_HOME="$work/config" \
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" \
	PATH="$work/bin:/usr/bin:/bin" DWM_TEST_REAL_RM="$real_rm" \
	DWM_TEST_SIGNAL_TARGET="$work/config/autostart/only.desktop" \
	DWM_TEST_SIGNAL_MARKER="$work/reset.signal" \
	"$helper" reset only.desktop "$reset_transaction_revision"
[[ $(sha256sum "$work/config/autostart/only.desktop" | awk '{ print $1 }') == "$only_transaction_hash" ]]
[[ $(stat -c %a "$work/config/autostart/only.desktop") == "$only_transaction_mode" ]]
[[ ! -e $work/config/autostart/.dwm-titus.lock ]]
rm -f "$work/bin/rm"

real_awk=$(command -v awk)
cat >"$work/bin/awk" <<'EOF'
#!/bin/sh
if [ -n "${DWM_TEST_SUCCESS_BLOCK:-}" ] && [ -e "$DWM_TEST_SUCCESS_BLOCK" ]; then
	: >"${DWM_TEST_SUCCESS_READY:?}"
	while [ ! -e "${DWM_TEST_SUCCESS_RELEASE:?}" ]; do
		sleep 0.01
	done
fi
exec "${DWM_TEST_REAL_AWK:-/usr/bin/awk}" "$@"
EOF
chmod +x "$work/bin/awk"

run_helper snapshot >"$work/success-boundary-set-before"
boundary_set_revision=$(entry_field "$work/success-boundary-set-before" conditional.desktop 11)
expect_success_boundary_signal success-boundary-set \
	set conditional.desktop disabled "$boundary_set_revision"
[[ -f $work/config/autostart/conditional.desktop ]]
run_helper snapshot >"$work/success-boundary-set-after"
[[ $(entry_field "$work/success-boundary-set-after" conditional.desktop 5) == disabled ]]

boundary_reset_revision=$(entry_field "$work/success-boundary-set-after" conditional.desktop 11)
expect_success_boundary_signal success-boundary-reset \
	reset conditional.desktop "$boundary_reset_revision"
[[ ! -e $work/config/autostart/conditional.desktop ]]
run_helper snapshot >"$work/success-boundary-reset-after"
[[ $(entry_field "$work/success-boundary-reset-after" conditional.desktop 5) == conditional ]]
rm -f "$work/bin/awk"

run_helper snapshot >"$work/backup-failure-before"
only_current_revision=$(entry_field "$work/backup-failure-before" only.desktop 11)
only_hash=$(sha256sum "$work/config/autostart/only.desktop")
cat >"$work/bin/cp" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$work/bin/cp"
expect_failure 'could not back up' env \
	HOME="$work/home" XDG_CONFIG_HOME="$work/config" \
	XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" \
	PATH="$work/bin:/usr/bin:/bin" \
	"$helper" set only.desktop disabled "$only_current_revision"
[[ $(sha256sum "$work/config/autostart/only.desktop") == "$only_hash" ]]
rm -f "$work/bin/cp"

mkdir "$work/config/autostart/.dwm-titus.lock"
expect_failure 'another autostart action' \
	run_helper set only.desktop disabled "$only_current_revision"
rmdir "$work/config/autostart/.dwm-titus.lock"

expect_failure 'invalid desktop id' \
	run_helper set ../escape.desktop disabled "$only_current_revision"

if command -v inotifywait >/dev/null 2>&1; then
	(
		env "${common_env[@]}" "$helper" watch >"$work/watch.out" 2>"$work/watch.err" &
		printf '%s\n' "$!" >"$work/watch-helper.pid"
		wait
	) &
	watch_owner=$!
	wait_for test -s "$work/watch-helper.pid"
	watch_helper=$(cat "$work/watch-helper.pid")
	wait_for grep -Fqx $'ready\tautostart' "$work/watch.out"
	watch_child=$(pgrep -P "$watch_helper" -x inotifywait || true)
	[[ $watch_child =~ ^[0-9]+$ ]]
	watch_child_start=$watch_child:$(sed 's/^.*) //' "/proc/$watch_child/stat" | awk '{ print $20 }')
	printf '\n# changed after watch opened\n' >>"$work/config/autostart/user-only.desktop"
	wait_for grep -Fqx $'changed\tautostart' "$work/watch.out"
	kill -STOP "$watch_owner"
	sleep 0.3
	kill -0 "$watch_helper"
	kill -0 "$watch_child"
	kill -CONT "$watch_owner"
	kill -TERM "$watch_owner"
	wait "$watch_owner" 2>/dev/null || true
	watch_owner=
	wait_for pid_gone "$watch_helper"
	wait_for pid_gone "$watch_child"
	watch_helper=
	watch_child=
	watch_child_start=

	mkdir "$work/watch-config"
	(
		env HOME="$work/home" XDG_CONFIG_HOME="$work/watch-config" \
			XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" PATH="/usr/bin:/bin" \
			"$helper" watch >"$work/watch-absent.out" 2>"$work/watch-absent.err" &
		printf '%s\n' "$!" >"$work/watch-absent-helper.pid"
		wait
	) &
	watch_owner=$!
	wait_for test -s "$work/watch-absent-helper.pid"
	watch_helper=$(cat "$work/watch-absent-helper.pid")
	wait_for line_count_at_least "$work/watch-absent.out" $'ready\tautostart' 1
	watch_child=$(pgrep -P "$watch_helper" -x inotifywait || true)
	[[ $watch_child =~ ^[0-9]+$ ]]
	watch_child_start=$watch_child:$(sed 's/^.*) //' "/proc/$watch_child/stat" | awk '{ print $20 }')
	mkdir "$work/watch-config/autostart"
	wait_for line_count_at_least "$work/watch-absent.out" $'changed\tautostart' 1
	wait_for line_count_at_least "$work/watch-absent.out" $'ready\tautostart' 2
	wait_for watch_child_replaced
	cp "$work/vendor-a/autostart/example.desktop" "$work/watch-config/autostart/watched.desktop"
	wait_for line_count_at_least "$work/watch-absent.out" $'changed\tautostart' 2
	kill -TERM "$watch_owner"
	wait "$watch_owner" 2>/dev/null || true
	watch_owner=
	wait_for pid_gone "$watch_helper"
	wait_for pid_gone "$watch_child"
	watch_helper=
	watch_child=
	watch_child_start=

	mkdir "$work/watch-deep"
	(
		env HOME="$work/home" XDG_CONFIG_HOME="$work/watch-deep/one/two/config" \
			XDG_CONFIG_DIRS="$work/vendor-a:$work/vendor-b" PATH="/usr/bin:/bin" \
			"$helper" watch >"$work/watch-deep.out" 2>"$work/watch-deep.err" &
		printf '%s\n' "$!" >"$work/watch-deep-helper.pid"
		wait
	) &
	watch_owner=$!
	wait_for test -s "$work/watch-deep-helper.pid"
	watch_helper=$(cat "$work/watch-deep-helper.pid")
	wait_for line_count_at_least "$work/watch-deep.out" $'ready\tautostart' 1
	watch_child=$(pgrep -P "$watch_helper" -x inotifywait || true)
	[[ $watch_child =~ ^[0-9]+$ ]]
	watch_child_start=$watch_child:$(sed 's/^.*) //' "/proc/$watch_child/stat" | awk '{ print $20 }')
	for component in one one/two one/two/config one/two/config/autostart; do
		mkdir "$work/watch-deep/$component"
		ready_count=$(grep -Fxc $'ready\tautostart' "$work/watch-deep.out")
		wait_for line_count_at_least "$work/watch-deep.out" $'changed\tautostart' "$ready_count"
		wait_for line_count_at_least "$work/watch-deep.out" $'ready\tautostart' "$((ready_count + 1))"
		wait_for watch_child_replaced
	done
	cp "$work/vendor-a/autostart/example.desktop" "$work/watch-deep/one/two/config/autostart/watched.desktop"
	wait_for line_count_at_least "$work/watch-deep.out" $'changed\tautostart' 5
	kill -TERM "$watch_owner"
	wait "$watch_owner" 2>/dev/null || true
	watch_owner=
	wait_for pid_gone "$watch_helper"
	wait_for pid_gone "$watch_child"
	watch_helper=
	watch_child=
	watch_child_start=
fi

printf 'dwm XDG autostart helper tests passed\n'
